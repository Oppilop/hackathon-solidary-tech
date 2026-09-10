package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	_ "github.com/jackc/pgx/v4/stdlib"
	"github.com/joho/godotenv"

	"donation-service/telemetry"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

type Donation struct {
	ID        int       `json:"id"`
	NgoID     int       `json:"ngo_id"`
	Amount    float64   `json:"amount"`
	DonorName string    `json:"donor_name"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type App struct {
	DB          *sql.DB
	SqsSvc      *sqs.SQS
	SqsQueueURL string
}

func main() {
	_ = godotenv.Load()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8082"
	}

	// Fase 5: OpenTelemetry (traces + métricas + /metrics em :9464).
	ctx := context.Background()
	shutdownTelemetry, err := telemetry.Init(ctx, "donation-service")
	if err != nil {
		log.Printf("Aviso: OpenTelemetry não inicializado: %v", err)
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL é obrigatória")
	}

	db, err := sql.Open("pgx", dbURL)
	if err != nil || db.Ping() != nil {
		log.Fatalf("Erro ao conectar ao banco de dados: %v", err)
	}
	// Pool dimensionado para os limits do Pod (ver gitops/base/donation/deployment.yaml).
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)
	log.Println("Conectado ao PostgreSQL (donation-service).")

	var sqsSvc *sqs.SQS
	queueURL := os.Getenv("AWS_SQS_URL")
	region := os.Getenv("AWS_REGION")
	if queueURL != "" && region != "" {
		sess, _ := session.NewSession(&aws.Config{Region: aws.String(region)})
		sqsSvc = sqs.New(sess)
		log.Println("Integração com AWS SQS ativada.")
	}

	app := &App{DB: db, SqsSvc: sqsSvc, SqsQueueURL: queueURL}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.HealthHandler)
	mux.HandleFunc("/donations", app.DonationHandler)

	srv := &http.Server{
		Addr: ":" + port,
		// WrapHandler cria o span raiz (otelhttp) e registra as métricas
		// http_requests_total / http_request_duration_seconds usadas nos SLOs.
		Handler:           telemetry.WrapHandler(mux, "donation-service"),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("donation-service rodando na porta %s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Erro no servidor HTTP: %v", err)
		}
	}()

	// Encerramento gracioso: o Pod recebe SIGTERM ao ser removido do Endpoints.
	// Terminar as requisições em voo evita 5xx artificiais durante rollouts —
	// isso protege diretamente o error budget do SLO de disponibilidade.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
	log.Println("SIGTERM recebido — drenando conexões...")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
	if shutdownTelemetry != nil {
		_ = shutdownTelemetry(shutdownCtx)
	}
	_ = db.Close()
	log.Println("donation-service encerrado.")
}

func (a *App) HealthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok","service":"donation-service"}`))
}

func (a *App) DonationHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	if r.Method == http.MethodPost {
		var d Donation
		if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
			http.Error(w, `{"error":"Payload inválido"}`, http.StatusBadRequest)
			return
		}

		d.Status = "APPROVED" // Simulação de gateway de pagamento
		err := a.DB.QueryRowContext(r.Context(),
			"INSERT INTO donations (ngo_id, amount, donor_name, status) VALUES ($1, $2, $3, $4) RETURNING id, created_at",
			d.NgoID, d.Amount, d.DonorName, d.Status,
		).Scan(&d.ID, &d.CreatedAt)

		if err != nil {
			log.Printf("Erro ao salvar doação: %v", err)
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}

		if a.SqsSvc != nil {
			// O contexto da requisição é encerrado quando a resposta é enviada,
			// então propagamos apenas o span context para a goroutine — assim o
			// envio ao SQS continua aparecendo no mesmo trace distribuído.
			asyncCtx := trace.ContextWithSpanContext(
				context.Background(),
				trace.SpanContextFromContext(r.Context()),
			)
			go a.sendNotificationEvent(asyncCtx, d)
		}

		w.WriteHeader(http.StatusCreated)
		_ = json.NewEncoder(w).Encode(d)
		return
	}

	if r.Method == http.MethodGet {
		rows, err := a.DB.QueryContext(r.Context(),
			"SELECT id, ngo_id, amount, donor_name, status, created_at FROM donations ORDER BY id DESC LIMIT 100")
		if err != nil {
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		donations := []Donation{}
		for rows.Next() {
			var d Donation
			if err := rows.Scan(&d.ID, &d.NgoID, &d.Amount, &d.DonorName, &d.Status, &d.CreatedAt); err != nil {
				log.Printf("Erro ao ler linha: %v", err)
				continue
			}
			donations = append(donations, d)
		}
		if err := rows.Err(); err != nil {
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}

		_ = json.NewEncoder(w).Encode(donations)
		return
	}

	http.Error(w, `{"error":"Método não permitido"}`, http.StatusMethodNotAllowed)
}

// sendNotificationEvent publica o evento da doação no SQS.
// O traceparent do W3C viaja em MessageAttributes, permitindo que qualquer
// consumidor futuro continue o MESMO trace distribuído (requisito de APM).
func (a *App) sendNotificationEvent(ctx context.Context, d Donation) {
	tracer := otel.Tracer("solidarytech.donation")
	ctx, span := tracer.Start(ctx, "sqs.SendMessage",
		trace.WithSpanKind(trace.SpanKindProducer),
		trace.WithAttributes(
			attribute.String("messaging.system", "aws_sqs"),
			attribute.String("messaging.destination.name", "solidary-donations"),
			attribute.Int("donation.ngo_id", d.NgoID),
		),
	)
	defer span.End()

	body, err := json.Marshal(d)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "falha ao serializar doação")
		return
	}

	carrier := propagation.MapCarrier{}
	otel.GetTextMapPropagator().Inject(ctx, carrier)

	attrs := map[string]*sqs.MessageAttributeValue{}
	for k, v := range carrier {
		attrs[k] = &sqs.MessageAttributeValue{
			DataType:    aws.String("String"),
			StringValue: aws.String(v),
		}
	}

	_, err = a.SqsSvc.SendMessageWithContext(ctx, &sqs.SendMessageInput{
		MessageBody:       aws.String(string(body)),
		QueueUrl:          aws.String(a.SqsQueueURL),
		MessageAttributes: attrs,
	})
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "falha ao despachar evento SQS")
		log.Printf("Falha ao despachar evento SQS: %v", err)
	}
}
