import os
from unittest.mock import MagicMock, patch

import pytest

os.environ.setdefault("DATABASE_URL", "postgres://user:pass@localhost:5432/ngodb")
os.environ["DISABLE_OTEL"] = "true"


@pytest.fixture(scope="module")
def client():
    # O pool é criado no import do módulo; substituímos por um mock para que o
    # teste não dependa de um PostgreSQL real.
    with patch("psycopg2.pool.SimpleConnectionPool", return_value=MagicMock()):
        import app as app_module
    app_module.app.config.update(TESTING=True)
    return app_module.app.test_client()


def test_health_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["service"] == "ngo-service"


def test_create_ngo_missing_fields(client):
    resp = client.post("/ngos", json={"name": "Anjos de Patas"})
    assert resp.status_code == 400
    assert "error" in resp.get_json()
