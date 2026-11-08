from __future__ import annotations

import io
import math
import os
import struct
import tempfile
import wave
from pathlib import Path

import pytest

# Keep the module-level `app` in app.main away from the real data folder.
_tmp = Path(tempfile.mkdtemp(prefix="tav-import-"))
os.environ.setdefault("LOCAL_STORAGE_DIR", str(_tmp / "audio"))
os.environ.setdefault("SQLITE_PATH", str(_tmp / "db.sqlite"))
os.environ.setdefault("AUTH_MODE", "dev")
os.environ.setdefault("APP_ENV", "test")

from fastapi.testclient import TestClient  # noqa: E402

from app.core.config import Settings  # noqa: E402
from app.main import create_app  # noqa: E402
from app.providers.base import (  # noqa: E402
    AudioPayload,
    ConversionRequest,
    LiveConversionProvider,
    LiveSessionInfo,
    ProviderState,
    ProviderStatus,
    SynthesisRequest,
    TTSProvider,
    VoiceConversionProvider,
)
from app.providers.registry import ProviderRegistry, build_registry  # noqa: E402


def make_wav(seconds: float = 1.0, rate: int = 8000, freq: float = 440.0) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = int(seconds * rate)
        w.writeframes(
            b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * freq * i / rate))) for i in range(frames))
        )
    return buf.getvalue()


class FakeTTS(TTSProvider):
    name = "google"

    def __init__(self) -> None:
        self.requests: list[SynthesisRequest] = []

    def status(self) -> ProviderStatus:
        return ProviderStatus(self.name, ProviderState.READY, "Fake provider for tests", paid=False)

    def synthesize(self, request: SynthesisRequest) -> AudioPayload:
        self.requests.append(request)
        return AudioPayload(make_wav(0.5), "wav", "audio/wav")


class FakeConverter(VoiceConversionProvider):
    name = "fake-vc"

    def __init__(self) -> None:
        self.requests: list[ConversionRequest] = []

    def status(self) -> ProviderStatus:
        return ProviderStatus(self.name, ProviderState.READY, "Fake converter", paid=False)

    def convert(self, request: ConversionRequest) -> AudioPayload:
        self.requests.append(request)
        return AudioPayload(make_wav(0.5, freq=660), "wav", "audio/wav")


class FakeLive(LiveConversionProvider):
    name = "fake-live"

    def status(self) -> ProviderStatus:
        return ProviderStatus(self.name, ProviderState.READY, "Fake live", paid=False)

    def create_session(self, user_id: str, direction: str) -> LiveSessionInfo:
        return LiveSessionInfo("sess-1", "wss://example.test/live/sess-1", 9999999999, 16000, "pcm_s16le")


@pytest.fixture()
def settings(tmp_path: Path) -> Settings:
    return Settings(
        _env_file=None,
        app_env="test",
        auth_mode="dev",
        secret_key="test-secret-key-0123456789abcdef",
        local_storage_dir=tmp_path / "audio",
        sqlite_path=tmp_path / "db.sqlite",
        max_upload_mb=1,
        max_audio_seconds=10,
        max_tts_chars=500,
    )


@pytest.fixture()
def client(settings: Settings) -> TestClient:
    return TestClient(create_app(settings))


@pytest.fixture()
def fake_tts() -> FakeTTS:
    return FakeTTS()


@pytest.fixture()
def fake_vc() -> FakeConverter:
    return FakeConverter()


@pytest.fixture()
def ready_client(settings: Settings, fake_tts: FakeTTS, fake_vc: FakeConverter) -> TestClient:
    reg: ProviderRegistry = build_registry(settings)
    reg.tts["google"] = fake_tts
    reg.conversion = fake_vc
    reg.live = FakeLive()
    return TestClient(create_app(settings, registry=reg))


ALICE = {"X-Dev-User": "alice"}
BOB = {"X-Dev-User": "bob"}
