import os
from unittest.mock import MagicMock, patch

import pytest

os.environ.setdefault("AWS_DYNAMODB_TABLE", "SolidaryTechVolunteers")
os.environ.setdefault("AWS_REGION", "us-east-1")
os.environ["DISABLE_OTEL"] = "true"


@pytest.fixture(scope="module")
def client():
    # boto3.resource é chamado no import do módulo; substituímos por um mock
    # para que o teste não precise de credenciais nem de DynamoDB real.
    with patch("boto3.resource", return_value=MagicMock()):
        import app as app_module
    app_module.app.config.update(TESTING=True)
    return app_module.app.test_client()


def test_health_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["service"] == "volunteer-service"


def test_register_volunteer_missing_fields(client):
    resp = client.post("/volunteers", json={"name": "Maria"})
    assert resp.status_code == 400
    assert "error" in resp.get_json()
