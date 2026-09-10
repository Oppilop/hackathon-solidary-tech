# =============================================================================
# Utilitários de desenvolvimento.
#
# `_shared/telemetry.py` é a fonte da verdade do módulo de instrumentação
# Python. Cada serviço precisa de uma cópia local porque o build Docker só
# enxerga o contexto da própria pasta. Rode `make sync-telemetry` sempre que
# alterar o módulo compartilhado.
# =============================================================================

PY_SERVICES := ngo-service volunteer-service

.PHONY: sync-telemetry check-telemetry test up down

sync-telemetry:
	@for s in $(PY_SERVICES); do \
		cp _shared/telemetry.py $$s/telemetry.py; \
		echo "telemetry.py -> $$s/"; \
	done

check-telemetry:
	@for s in $(PY_SERVICES); do \
		diff -q _shared/telemetry.py $$s/telemetry.py >/dev/null \
			|| { echo "ERRO: $$s/telemetry.py divergente de _shared. Rode 'make sync-telemetry'."; exit 1; }; \
	done
	@echo "telemetry.py sincronizado em todos os serviços Python."

test:
	cd donation-service && go test ./... -count=1
	cd ngo-service && python3 -m pytest -q
	cd volunteer-service && python3 -m pytest -q

up:
	docker compose up --build -d

down:
	docker compose down -v
