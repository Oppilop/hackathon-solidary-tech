package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// O /health é o alvo das probes do Kubernetes e do SLI de disponibilidade.
// Se ele quebrar, o Pod entra em CrashLoop — por isso o teste é obrigatório.
func TestHealthHandler(t *testing.T) {
	app := &App{}
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()

	app.HealthHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status esperado 200, recebido %d", rec.Code)
	}

	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("resposta não é JSON válido: %v", err)
	}
	if body["service"] != "donation-service" {
		t.Errorf("service esperado 'donation-service', recebido %q", body["service"])
	}
}

func TestDonationHandlerMethodNotAllowed(t *testing.T) {
	app := &App{}
	req := httptest.NewRequest(http.MethodDelete, "/donations", nil)
	rec := httptest.NewRecorder()

	app.DonationHandler(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status esperado 405, recebido %d", rec.Code)
	}
}

func TestDonationHandlerInvalidPayload(t *testing.T) {
	app := &App{}
	req := httptest.NewRequest(http.MethodPost, "/donations", http.NoBody)
	rec := httptest.NewRecorder()

	app.DonationHandler(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status esperado 400 para payload vazio, recebido %d", rec.Code)
	}
}
