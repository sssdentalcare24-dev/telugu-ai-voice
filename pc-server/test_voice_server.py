"""Tests for the PC voice server with a stand-in model (the real IndicF5 model
is ~1.4 GB and runs only on the user's PC). They exercise the exact calls the
phone app makes."""

from __future__ import annotations

import io
import json
from pathlib import Path

import numpy as np
import pytest
import soundfile as sf
from fastapi.testclient import TestClient

import voice_server as vs

CODE = "123456"
BASE = f"/k/{CODE}"


def wav_bytes(seconds: float = 1.0, rate: int = 16000) -> bytes:
    t = np.arange(int(seconds * rate)) / rate
    buf = io.BytesIO()
    sf.write(buf, (0.3 * np.sin(2 * np.pi * 220 * t)).astype(np.float32), rate, format="WAV", subtype="PCM_16")
    return buf.getvalue()


class FakeModel:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str, str]] = []

    def __call__(self, text: str, ref_audio_path: str, ref_text: str):
        self.calls.append((text, ref_audio_path, ref_text))
        assert Path(ref_audio_path).exists()
        return (np.ones(SAMPLES, dtype=np.int16) * 1000)  # int16, like IndicF5 sometimes returns


SAMPLES = vs.SAMPLE_RATE * 2


@pytest.fixture()
def setup(tmp_path: Path):
    model = FakeModel()
    engine = vs.Engine(tmp_path, model=model)
    examples = vs.Examples(tmp_path)
    # A cached sample speaker, as if copied from the online server.
    (examples.dir / "ex4.wav").write_bytes(wav_bytes(3))
    (examples.dir / "ex4.json").write_text(json.dumps({"text": "x", "ref_text": "ಕನ್ನಡ"}), encoding="utf-8")
    client = TestClient(vs.create_app(tmp_path, engine, CODE, examples))
    return client, model


def call(client: TestClient, api: str, data: list) -> str:
    r = client.post(f"{BASE}/gradio_api/call/{api}", json={"data": data})
    assert r.status_code == 200, r.text
    r = client.get(f"{BASE}/gradio_api/call/{api}/{r.json()['event_id']}")
    assert r.status_code == 200
    return r.text


def complete(sse: str) -> list:
    lines = sse.splitlines()
    i = lines.index("event: complete")
    return json.loads(lines[i + 1][5:].strip())


def test_clone_flow_like_the_app(setup) -> None:
    client, model = setup
    info = client.get(f"{BASE}/info").json()
    assert info["server"] == "telugu-voice-pc" and info["model_ready"] is True and info["examples"] == 1

    up = client.post(f"{BASE}/gradio_api/upload", files={"files": ("voice_sample.wav", wav_bytes(8), "audio/wav")})
    path = up.json()[0]
    assert path.startswith("uploads/") and "\\" not in path and ":" not in path

    sse = call(client, "synthesize_speech", ["భోజనం చేశారా?", {"path": path, "meta": {"_type": "gradio.FileData"}}, "నమస్కారం"])
    out = complete(sse)[0]["path"]
    assert model.calls[0][0] == "భోజనం చేశారా?" and model.calls[0][2] == "నమస్కారం"

    audio = client.get(f"{BASE}/gradio_api/file={out}")
    assert audio.status_code == 200
    data, rate = sf.read(io.BytesIO(audio.content), dtype="int16")
    assert rate == 24000 and len(data) == SAMPLES  # 16-bit PCM WAV, as the app joins clips


def test_built_in_voices_come_from_cached_examples(setup) -> None:
    client, _ = setup
    out = complete(call(client, "load_example", [4]))
    assert out[2]["value"] == "ಕನ್ನಡ"
    ref = out[1]["value"]["path"]
    assert client.get(f"{BASE}/gradio_api/file={ref}").status_code == 200


def test_access_code_and_file_safety(setup, tmp_path: Path) -> None:
    client, _ = setup
    assert client.get("/k/999999/info").status_code == 404
    assert client.get("/info").status_code == 404
    secret = tmp_path / "hf_token.txt"
    secret.write_text("hf_secret", encoding="utf-8")
    for bad in ("../hf_token.txt", "uploads/../../hf_token.txt", str(secret), "C:/Windows/win.ini"):
        assert client.get(f"{BASE}/gradio_api/file={bad}").status_code == 404
    # A request pointing at a file outside the data folder is refused, not read.
    sse = call(client, "synthesize_speech", ["x", {"path": "../hf_token.txt"}, "y"])
    assert sse.startswith("event: error") and "did not reach the PC" in sse


def test_errors_are_readable(tmp_path: Path) -> None:
    engine = vs.Engine(tmp_path)
    engine.error = "Your Hugging Face account cannot download IndicF5 yet."
    engine.ready.set()
    client = TestClient(vs.create_app(tmp_path, engine, CODE, vs.Examples(tmp_path)))
    up = client.post(f"{BASE}/gradio_api/upload", files={"files": ("a.wav", wav_bytes(5), "audio/wav")}).json()[0]
    sse = call(client, "synthesize_speech", ["hello", {"path": up}, "hello"])
    assert sse.startswith("event: error") and "cannot download IndicF5" in sse
    assert client.get(f"{BASE}/info").json()["model_ready"] is False
    assert client.post(f"{BASE}/gradio_api/call/other", json={"data": []}).status_code == 404


def test_access_code_is_kept(tmp_path: Path) -> None:
    code = vs.load_code(tmp_path)
    assert len(code) == 6 and code.isdigit()
    assert vs.load_code(tmp_path) == code
    assert "gated" not in vs._friendly_load_error(RuntimeError("Cannot access gated repo"))
    assert "Agree" in vs._friendly_load_error(RuntimeError("Cannot access gated repo"))
