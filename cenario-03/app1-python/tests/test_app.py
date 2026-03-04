import json
import pytest
from unittest.mock import patch, MagicMock
from app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_hello_returns_200(client):
    with patch("app.redis_client") as mock_redis:
        mock_redis.get.return_value = None
        mock_redis.setex.return_value = True
        resp = client.get("/")
    assert resp.status_code == 200


def test_hello_returns_message(client):
    with patch("app.redis_client") as mock_redis:
        mock_redis.get.return_value = None
        mock_redis.setex.return_value = True
        resp = client.get("/")
    data = json.loads(resp.data)
    assert "message" in data
    assert "app1" in data["message"]


def test_hello_cache_hit(client):
    cached = json.dumps({"message": "Hello from App1 — Python/Flask!", "app": "app1"})
    with patch("app.redis_client") as mock_redis:
        mock_redis.get.return_value = cached
        resp = client.get("/")
    data = json.loads(resp.data)
    assert data["cached"] is True


def test_time_returns_server_time(client):
    with patch("app.redis_client") as mock_redis:
        mock_redis.get.return_value = None
        mock_redis.setex.return_value = True
        resp = client.get("/time")
    assert resp.status_code == 200
    data = json.loads(resp.data)
    assert "server_time" in data


def test_health_returns_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    data = json.loads(resp.data)
    assert data["status"] == "ok"
