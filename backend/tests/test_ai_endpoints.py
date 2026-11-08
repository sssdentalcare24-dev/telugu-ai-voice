"""TTS, conversion and live endpoints: honest 503s when no provider is
configured, and the full flow when one is (using fake providers)."""

from __future__ import annotations

from fastapi.testclient import TestClient

from .conftest import ALICE, BOB, FakeConverter, FakeTTS, make_wav

SAMPLE = "నమస్కారం! మీరు ఎలా ఉన్నారు? తెలుగు AI Voice యాప్‌కు స్వాగతం."


# ---- Text-to-speech -----------------------------------------------------------------
def test_tts_without_provider_returns_503(client: TestClient) -> None:
    r = client.post("/api/tts/generate", headers=ALICE, json={"text": SAMPLE, "voice_id": "google-te-female-hd"})
    assert r.status_code == 503
    err = r.json()["error"]
    assert err["code"] == "PROVIDER_NOT_CONFIGURED"
    assert "Stage 3" in err["message"]


def test_tts_validation(client: TestClient) -> None:
    def post(**kw):
        body = {"text": SAMPLE, "voice_id": "google-te-female-hd", **kw}
        return client.post("/api/tts/generate", headers=ALICE, json=body)

    assert post(text="   ").json()["error"]["code"] == "VALIDATION_ERROR"
    assert post(text="hello only english").json()["error"]["code"] == "NOT_TELUGU"
    assert post(text="తె" * 600).json()["error"]["code"] == "TEXT_TOO_LONG"
    assert post(voice_id="no-such-voice").json()["error"]["code"] == "UNKNOWN_VOICE"
    assert post(speed=3.0).status_code == 422
    assert post(pitch=4).json()["error"]["code"] == "PITCH_UNSUPPORTED"  # Chirp 3 HD has no pitch
    assert post(style="cheerful").json()["error"]["code"] == "STYLE_UNSUPPORTED"
    assert client.post("/api/tts/generate", json={"text": SAMPLE, "voice_id": "x"}).status_code == 401


def test_tts_success_flow_with_provider(ready_client: TestClient, fake_tts: FakeTTS) -> None:
    r = ready_client.post(
        "/api/tts/generate",
        headers=ALICE,
        json={"text": "  " + SAMPLE + "\u0000 ", "voice_id": "google-te-male-standard", "speed": 1.25, "pitch": -2},
    )
    assert r.status_code == 201, r.text
    item = r.json()
    assert item["kind"] == "tts"
    assert item["parameters"]["gender"] == "male"
    req = fake_tts.requests[0]
    assert req.provider_voice == "te-IN-Standard-B"
    assert req.language_code == "te-IN"
    assert req.text == SAMPLE  # normalised: trimmed, control char removed, ZWNJ kept
    assert "‌" in req.text
    assert req.speed == 1.25 and req.pitch == -2

    health = ready_client.get("/api/health").json()
    assert health["capabilities"]["tts"]["available"] is True
    voices = {v["id"]: v["available"] for v in ready_client.get("/api/voices").json()["voices"]}
    assert voices["google-te-female-hd"] is True
    assert voices["azure-te-female-shruti"] is False

    hist = ready_client.get("/api/audio/history?kind=tts", headers=ALICE).json()["items"]
    assert [h["id"] for h in hist] == [item["id"]]
    assert ready_client.get(item["download_url"]).status_code == 200


def test_tts_unconfigured_provider_still_503_when_other_ready(ready_client: TestClient) -> None:
    r = ready_client.post("/api/tts/generate", headers=ALICE, json={"text": SAMPLE, "voice_id": "azure-te-male-mohan"})
    assert r.status_code == 503


# ---- Recorded conversion ----------------------------------------------------------------
def convert(client: TestClient, consent: bool = True, direction: str = "male_to_female", **extra):
    files = extra.pop("files", {"file": ("voice.wav", make_wav(1.0), "audio/wav")})
    data = {"direction": direction, "consent": str(consent).lower(), **extra}
    return client.post("/api/voice/convert", headers=ALICE, data=data, files=files)


def test_convert_requires_consent_before_anything(client: TestClient) -> None:
    r = convert(client, consent=False)
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "CONSENT_REQUIRED"


def test_convert_without_provider_returns_503(client: TestClient) -> None:
    r = convert(client)
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "PROVIDER_NOT_CONFIGURED"
    # Nothing was stored for a request that could not be fulfilled.
    assert client.get("/api/audio/history", headers=ALICE).json()["items"] == []


def test_convert_rejects_bad_direction(client: TestClient) -> None:
    assert convert(client, direction="robot").status_code == 422


def test_convert_success_both_directions(ready_client: TestClient, fake_vc: FakeConverter) -> None:
    r = convert(ready_client)
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["original"]["kind"] == "original"
    assert body["converted"]["kind"] == "converted"
    assert body["converted"]["source_audio_id"] == body["original"]["id"]
    assert body["converted"]["title"].endswith("(M→F)")

    # Re-use the stored original for the opposite direction.
    r2 = convert(ready_client, direction="female_to_male", files={}, source_audio_id=body["original"]["id"])
    assert r2.status_code == 201, r2.text
    assert r2.json()["original"]["id"] == body["original"]["id"]
    assert fake_vc.requests[-1].direction == "female_to_male"


def test_convert_cannot_use_other_users_audio(ready_client: TestClient) -> None:
    alice_item = convert(ready_client).json()["original"]["id"]
    r = ready_client.post(
        "/api/voice/convert",
        headers=BOB,
        data={"direction": "male_to_female", "consent": "true", "source_audio_id": alice_item},
    )
    assert r.status_code == 404


def test_convert_needs_exactly_one_source(ready_client: TestClient) -> None:
    r = convert(ready_client, files={})
    assert r.status_code == 422


# ---- Live ------------------------------------------------------------------------------------
def test_live_session_unavailable_without_streaming_engine(client: TestClient) -> None:
    r = client.post("/api/voice/live/session", headers=ALICE, json={"direction": "male_to_female", "consent": True})
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "LIVE_CONVERSION_UNAVAILABLE"


def test_live_session_requires_consent(client: TestClient) -> None:
    r = client.post("/api/voice/live/session", headers=ALICE, json={"direction": "male_to_female", "consent": False})
    assert r.status_code == 400


def test_live_session_with_engine(ready_client: TestClient) -> None:
    r = ready_client.post(
        "/api/voice/live/session", headers=ALICE, json={"direction": "female_to_male", "consent": True}
    )
    assert r.status_code == 201
    assert r.json()["websocket_url"].startswith("wss://")
