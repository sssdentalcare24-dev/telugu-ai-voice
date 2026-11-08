"""Personal voice cloning: profile lifecycle, consent, validation, rate limits,
MP3 download, and the three provider integrations against mocked HTTP."""

from __future__ import annotations

import base64
import json
from urllib.parse import parse_qs

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.core.errors import ApiError
from app.main import create_app
from app.providers.base import AudioPayload, ProviderState, ProviderStatus
from app.providers.cloning import (
    CloneRegistry,
    CloneRequirements,
    ClonedVoice,
    ElevenLabsCloneProvider,
    IndicF5CloneProvider,
    SarvamCloneProvider,
    VoiceCloneProvider,
    VoiceSample,
    build_clone_registry,
    join_wavs,
)

from .conftest import ALICE, BOB, make_wav

CONSENT = {
    "confirmed": True,
    "relationship": "self",
    "speaker_name": "Alice",
    "statement": "This is my own voice and I agree to create an AI copy of it.",
}
TELUGU = "నమస్కారం! మీరు ఎలా ఉన్నారు?"


class FakeCloner(VoiceCloneProvider):
    name = "fake"
    label = "Fake cloner"
    paid = False
    requirements = CloneRequirements(
        min_seconds=1,
        max_seconds=8,
        recommended="",
        needs_transcript=True,
        languages=("te", "hi"),
        cross_lingual=True,
        supports_speed=False,
    )

    def __init__(self) -> None:
        self.created: list[VoiceSample] = []
        self.spoken: list[tuple[ClonedVoice, str, str, float]] = []
        self.deleted: list[str] = []

    def status(self) -> ProviderStatus:
        return ProviderStatus(self.name, ProviderState.READY, "Fake", paid=False)

    def create_voice(self, sample: VoiceSample) -> str:
        self.created.append(sample)
        return "fake-voice-1"

    def synthesize(self, voice: ClonedVoice, text: str, language: str, speed: float) -> AudioPayload:
        self.spoken.append((voice, text, language, speed))
        return AudioPayload(make_wav(0.5, rate=16000), "wav", "audio/wav")

    def delete_voice(self, provider_voice_id: str) -> None:
        self.deleted.append(provider_voice_id)


@pytest.fixture()
def cloner() -> FakeCloner:
    return FakeCloner()


@pytest.fixture()
def clone_client(settings: Settings, cloner: FakeCloner) -> TestClient:
    settings.clone_generate_per_hour = 3
    reg = CloneRegistry(providers={"fake": cloner}, default="fake")
    return TestClient(create_app(settings, clone_registry=reg))


def _ready_profile(client: TestClient, name: str = "My voice") -> dict:
    r = client.post(
        "/api/clone/profiles",
        json={"name": name, "category": "male", "recording_language": "te", "consent": CONSENT},
        headers=ALICE,
    )
    assert r.status_code == 201, r.text
    pid = r.json()["id"]
    r = client.post(
        f"/api/clone/profiles/{pid}/sample",
        files={"file": ("me.wav", make_wav(2.0), "audio/wav")},
        data={"transcript": TELUGU},
        headers=ALICE,
    )
    assert r.status_code == 200, r.text
    r = client.post(f"/api/clone/profiles/{pid}/clone", headers=ALICE)
    assert r.status_code == 200, r.text
    return r.json()


def test_consent_is_required(clone_client: TestClient) -> None:
    body = {"name": "x", "category": "female", "recording_language": "te", "consent": {**CONSENT, "confirmed": False}}
    r = clone_client.post("/api/clone/profiles", json=body, headers=ALICE)
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "CONSENT_REQUIRED"


def test_full_flow_record_once_then_speak_any_text(clone_client: TestClient, cloner: FakeCloner) -> None:
    r = clone_client.post(
        "/api/clone/profiles",
        json={"name": "Amma", "category": "female", "recording_language": "te", "consent": CONSENT},
        headers=ALICE,
    )
    profile = r.json()
    assert profile["status"] == "draft"
    assert profile["consent"]["confirmed"] is True and profile["consent"]["accepted_at"]
    pid = profile["id"]

    # Not yet: no sample.
    assert clone_client.post(f"/api/clone/profiles/{pid}/clone", headers=ALICE).json()["error"]["code"] == "SAMPLE_MISSING"

    # Too short, then missing transcript, then good.
    short = clone_client.post(
        f"/api/clone/profiles/{pid}/sample", files={"file": ("a.wav", make_wav(0.5), "audio/wav")},
        data={"transcript": TELUGU}, headers=ALICE,
    )
    assert short.json()["error"]["code"] == "SAMPLE_TOO_SHORT"
    no_text = clone_client.post(
        f"/api/clone/profiles/{pid}/sample", files={"file": ("a.wav", make_wav(2.0), "audio/wav")}, headers=ALICE
    )
    assert no_text.json()["error"]["code"] == "TRANSCRIPT_REQUIRED"
    ok = clone_client.post(
        f"/api/clone/profiles/{pid}/sample", files={"file": ("a.wav", make_wav(2.0), "audio/wav")},
        data={"transcript": TELUGU}, headers=ALICE,
    )
    assert ok.status_code == 200
    assert ok.json()["sample"]["duration_seconds"] == pytest.approx(2.0, abs=0.05)

    cloned = clone_client.post(f"/api/clone/profiles/{pid}/clone", headers=ALICE).json()
    assert cloned["status"] == "ready"
    assert cloned["provider_voice_id"] == "fake-voice-1"
    assert cloned["preview"]["kind"] == "tts"
    assert cloner.created[0].transcript == TELUGU

    # Speak new text - no new recording needed.
    r = clone_client.post(
        "/api/clone/tts", json={"profile_id": pid, "text": "భోజనం చేశారా?", "language": "te", "speed": 1.3}, headers=ALICE
    )
    assert r.status_code == 201, r.text
    gen = r.json()
    assert gen["profile_name"] == "Amma" and gen["language"] == "te"
    assert gen["speed"] == 1.0  # provider has no speed control
    voice, text, language, _ = cloner.spoken[-1]
    assert text == "భోజనం చేశారా?" and voice.sample is not None and voice.sample.transcript == TELUGU

    # Cross-lingual: Hindi in the same voice.
    assert clone_client.post(
        "/api/clone/tts", json={"profile_id": pid, "text": "नमस्ते", "language": "hi"}, headers=ALICE
    ).status_code == 201
    # A language the provider does not speak.
    bad = clone_client.post("/api/clone/tts", json={"profile_id": pid, "text": "Hello", "language": "en"}, headers=ALICE)
    assert bad.json()["error"]["code"] == "UNSUPPORTED_LANGUAGE"

    history = clone_client.get("/api/clone/history", headers=ALICE).json()["items"]
    assert [h["text"] for h in history] == ["नमस्ते", "భోజనం చేశారా?"]

    # MP3 download of generated WAV.
    url = history[0]["audio"]["download_url"]
    mp3 = clone_client.get(url + "&format=mp3&download=true")
    assert mp3.status_code == 200
    assert mp3.headers["content-type"] == "audio/mpeg"
    assert mp3.content[:3] == b"ID3" or mp3.content[0] == 0xFF
    assert "attachment" in mp3.headers["content-disposition"]

    # Delete one generation.
    assert clone_client.delete(f"/api/clone/history/{history[0]['id']}", headers=ALICE).status_code == 204
    assert len(clone_client.get("/api/clone/history", headers=ALICE).json()["items"]) == 1

    # Delete the profile: removed at the provider, sample gone.
    sample_id = cloned["sample"]["id"]
    assert clone_client.delete(f"/api/clone/profiles/{pid}", headers=ALICE).status_code == 204
    assert cloner.deleted == ["fake-voice-1"]
    assert clone_client.get(f"/api/audio/{sample_id}", headers=ALICE).status_code == 404
    assert clone_client.get("/api/clone/profiles", headers=ALICE).json()["profiles"] == []


def test_profiles_are_private(clone_client: TestClient) -> None:
    profile = _ready_profile(clone_client)
    assert clone_client.get(f"/api/clone/profiles/{profile['id']}", headers=BOB).status_code == 404
    assert clone_client.get("/api/clone/profiles", headers=BOB).json()["profiles"] == []
    r = clone_client.post("/api/clone/tts", json={"profile_id": profile["id"], "text": TELUGU, "language": "te"}, headers=BOB)
    assert r.status_code == 404


def test_generation_is_rate_limited(clone_client: TestClient) -> None:
    pid = _ready_profile(clone_client)["id"]
    body = {"profile_id": pid, "text": TELUGU, "language": "te"}
    for _ in range(3):
        assert clone_client.post("/api/clone/tts", json=body, headers=ALICE).status_code == 201
    limited = clone_client.post("/api/clone/tts", json=body, headers=ALICE)
    assert limited.status_code == 429
    assert limited.json()["error"]["code"] == "RATE_LIMITED"


def test_providers_and_health_report_cloning(settings: Settings) -> None:
    client = TestClient(create_app(settings))
    data = client.get("/api/clone/providers").json()
    by_name = {p["name"]: p for p in data["providers"]}
    assert by_name["indicf5"]["ready"] is True and by_name["indicf5"]["paid"] is False
    assert "en" not in by_name["indicf5"]["languages"]
    assert by_name["sarvam"]["state"] == "not_configured"
    assert by_name["elevenlabs"]["state"] == "not_configured"
    assert len(data["languages"]) == 12
    health = client.get("/api/health").json()
    assert health["capabilities"]["voice_cloning"]["available"] is True
    # Paid providers refuse to work without keys.
    r = client.post(
        "/api/clone/profiles",
        json={"name": "x", "category": "male", "recording_language": "te", "provider": "elevenlabs", "consent": CONSENT},
        headers=ALICE,
    )
    assert r.json()["error"]["code"] == "PROVIDER_NOT_CONFIGURED"


# --- Providers against mocked HTTP -------------------------------------------------------


def _sample(transcript: str | None = TELUGU) -> VoiceSample:
    return VoiceSample(make_wav(3.0, rate=16000), "wav", "audio/wav", "Amma", "te", transcript)


def test_indicf5_uploads_sample_and_joins_chunks(settings: Settings) -> None:
    settings.hf_token = "hf_test"
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        path = request.url.path
        assert request.headers["authorization"] == "Bearer hf_test"
        if path == "/gradio_api/upload":
            return httpx.Response(200, json=["/tmp/gradio/ref/sample.wav"])
        if path == "/gradio_api/call/synthesize_speech" and request.method == "POST":
            data = json.loads(request.content)["data"]
            assert data[1]["path"] == "/tmp/gradio/ref/sample.wav" and data[2] == TELUGU
            return httpx.Response(200, json={"event_id": "e1"})
        if path.startswith("/gradio_api/call/synthesize_speech/"):
            return httpx.Response(200, text='event: complete\ndata: [{"path": "/tmp/gradio/out/audio.wav"}]\n\n')
        if path.startswith("/gradio_api/file="):
            return httpx.Response(200, content=make_wav(1.0, rate=24000))
        return httpx.Response(404)

    provider = IndicF5CloneProvider(settings, client=httpx.Client(transport=httpx.MockTransport(handler), headers={"Authorization": "Bearer hf_test"}))
    assert provider.create_voice(_sample()) == "indicf5:zero-shot"
    with pytest.raises(ApiError) as exc:
        provider.create_voice(_sample(transcript=None))
    assert exc.value.code == "TRANSCRIPT_REQUIRED"

    long_text = "మా డాక్టర్లు ప్రతి రోజు అందుబాటులో ఉంటారు. " * 40  # needs more than one request
    payload = provider.synthesize(ClonedVoice("indicf5:zero-shot", _sample()), long_text, "te", 1.0)
    calls = [r for r in seen if r.method == "POST" and r.url.path == "/gradio_api/call/synthesize_speech"]
    assert len(calls) >= 2
    import io
    import wave

    with wave.open(io.BytesIO(payload.data)) as w:
        assert w.getframerate() == 24000
        assert w.getnframes() / 24000 > len(calls) * 1.0  # clips plus pauses


def test_indicf5_busy_server_gives_clear_error(settings: Settings) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/gradio_api/upload":
            return httpx.Response(200, json=["/tmp/x.wav"])
        if request.method == "POST":
            return httpx.Response(200, json={"event_id": "e1"})
        return httpx.Response(200, text="event: error\ndata: null\n\n")

    provider = IndicF5CloneProvider(settings, client=httpx.Client(transport=httpx.MockTransport(handler)))
    with pytest.raises(ApiError) as exc:
        provider.synthesize(ClonedVoice("z", _sample()), TELUGU, "te", 1.0)
    assert exc.value.status_code == 429 and "daily free limit" in exc.value.message


def test_sarvam_create_and_speak(settings: Settings) -> None:
    settings.sarvam_api_key = "sk-sarvam"
    wav = make_wav(0.5, rate=24000)

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["api-subscription-key"] == "sk-sarvam"
        if request.url.path == "/voices/create":
            assert b'name="language"' in request.content and b"te-IN" in request.content
            return httpx.Response(200, json={"data": {"voice_id": "svc-123", "status": "saved"}})
        if request.url.path == "/voices/clone":
            form = parse_qs(request.content.decode())
            assert form["voice_id"] == ["svc-123"] and form["language_code"] == ["te-IN"]
            assert form["pace"] == ["1.5"] and form["output_audio_codec"] == ["wav"]
            return httpx.Response(200, json={"audio": base64.b64encode(wav).decode(), "request_id": "r1"})
        if request.url.path == "/voices/delete/svc-123":
            return httpx.Response(200, json={})
        return httpx.Response(404)

    provider = SarvamCloneProvider(settings, client=httpx.Client(transport=httpx.MockTransport(handler)))
    assert provider.status().ready
    vid = provider.create_voice(_sample())
    assert vid == "svc-123"
    out = provider.synthesize(ClonedVoice(vid), TELUGU, "te", 1.5)
    assert out.format == "wav" and out.data == wav
    provider.delete_voice(vid)


def test_elevenlabs_create_speak_and_bad_key(settings: Settings) -> None:
    settings.elevenlabs_api_key = "xi-key"

    def handler(request: httpx.Request) -> httpx.Response:
        if request.headers.get("xi-api-key") != "xi-key":
            return httpx.Response(401, json={"detail": {"message": "invalid key"}})
        if request.url.path == "/v1/voices/add":
            assert b'name="files"' in request.content
            return httpx.Response(200, json={"voice_id": "el-1", "requires_verification": False})
        if request.url.path == "/v1/text-to-speech/el-1":
            body = json.loads(request.content)
            assert body["model_id"] == "eleven_v4" and body["language_code"] == "te"
            assert body["voice_settings"]["speed"] == 1.2  # clamped to the API's range
            assert request.url.params["output_format"] == "mp3_44100_128"
            return httpx.Response(200, content=b"ID3fake-mp3")
        return httpx.Response(404)

    provider = ElevenLabsCloneProvider(settings, client=httpx.Client(transport=httpx.MockTransport(handler)))
    vid = provider.create_voice(_sample(transcript=None))
    out = provider.synthesize(ClonedVoice(vid), TELUGU, "te", 1.5)
    assert out.format == "mp3" and out.data.startswith(b"ID3")

    provider.key = "wrong"
    with pytest.raises(ApiError) as exc:
        provider.create_voice(_sample())
    assert exc.value.code == "PROVIDER_NOT_CONFIGURED"


def test_registry_and_wav_join(settings: Settings) -> None:
    settings.voice_clone_providers = "sarvam,indicf5,unknown"
    reg = build_clone_registry(settings)
    assert list(reg.providers) == ["sarvam", "indicf5"]
    assert reg.default == "indicf5"
    with pytest.raises(ApiError):
        reg.get("sarvam")  # no key
    joined = join_wavs([make_wav(1.0), make_wav(1.0)], gap_seconds=0.5)
    import io
    import wave

    with wave.open(io.BytesIO(joined)) as w:
        assert w.getnframes() == 8000 * 2 + 4000
