from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.core.config import Settings
from app.main import create_app

from .conftest import ALICE


def test_health_reports_honest_capabilities(client: TestClient) -> None:
    r = client.get("/api/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["auth_mode"] == "dev"
    caps = body["capabilities"]
    # Stage 2: no AI provider is integrated, and the API says so.
    assert caps["tts"]["available"] is False
    states = {p["name"]: p["state"] for p in caps["tts"]["providers"]}
    assert states == {"google": "not_implemented", "azure": "not_implemented"}
    assert caps["voice_conversion"]["available"] is False
    assert caps["live_conversion"]["available"] is False
    assert caps["live_conversion"]["streaming"] is False
    assert "pitch shifting" in caps["live_conversion"]["provider"]["message"]
    assert caps["storage"]["available"] is True
    assert body["limits"]["allowed_formats"] == ["wav", "mp3", "ogg", "flac", "m4a"]


def test_security_headers(client: TestClient) -> None:
    r = client.get("/api/health")
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["x-frame-options"] == "DENY"


def test_voices_listed_from_config(client: TestClient) -> None:
    r = client.get("/api/voices")
    assert r.status_code == 200
    voices = r.json()["voices"]
    assert {v["gender"] for v in voices} == {"female", "male"}
    assert all(v["available"] is False for v in voices)
    assert all("provider_voice" not in v for v in voices)


def test_dev_auth_required(client: TestClient) -> None:
    r = client.get("/api/audio/history")
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "UNAUTHENTICATED"
    assert client.get("/api/audio/history", headers={"X-Dev-User": "x"}).status_code == 401  # too short
    assert client.get("/api/audio/history", headers={"X-Dev-User": "../etc"}).status_code == 401
    assert client.get("/api/audio/history", headers=ALICE).status_code == 200


def test_dev_mode_refused_in_production() -> None:
    with pytest.raises(ValidationError):
        Settings(_env_file=None, app_env="production", auth_mode="dev", secret_key="x" * 40)
    with pytest.raises(ValidationError):
        Settings(_env_file=None, app_env="production", auth_mode="firebase")  # default secret


def test_firebase_mode_verifies_tokens(settings: Settings) -> None:
    fb_settings = settings.model_copy(update={"auth_mode": "firebase"})

    def verifier(token: str) -> dict:
        if token != "good-token":
            raise ValueError("bad token")
        return {"uid": "firebase-user-1", "email": "a@example.com"}

    c = TestClient(create_app(fb_settings, token_verifier=verifier))
    assert c.get("/api/audio/history").status_code == 401
    assert c.get("/api/audio/history", headers={"X-Dev-User": "alice"}).status_code == 401  # dev header ignored
    bad = c.get("/api/audio/history", headers={"Authorization": "Bearer nope"})
    assert bad.status_code == 401
    assert "expired" in bad.json()["error"]["message"]
    ok = c.get("/api/audio/history", headers={"Authorization": "Bearer good-token"})
    assert ok.status_code == 200
    assert ok.json() == {"items": [], "next_cursor": None}


def test_cors_allows_local_flutter_dev_server(client: TestClient) -> None:
    r = client.options(
        "/api/health",
        headers={"Origin": "http://localhost:53211", "Access-Control-Request-Method": "GET"},
    )
    assert r.headers.get("access-control-allow-origin") == "http://localhost:53211"
