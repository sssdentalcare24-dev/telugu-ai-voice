"""Telugu AI Voice - PC voice server.

Runs AI4Bharat IndicF5 on this computer so the phone app can make natural
voices and cloned voices with no daily limit and no cost. The app talks to it
over the home/clinic Wi-Fi with the same API the free online server uses
(Gradio-style /gradio_api/... calls), so nothing else in the app changes.

Security: every address starts with a secret access code (/k/<code>/...), so
other people on the same Wi-Fi cannot use the server or fetch audio without it.
Files are only served from this server's own data folder.

Started by Telugu-Voice-PC-Server.bat; can also be run with:  python voice_server.py
"""

from __future__ import annotations

import json
import os
import secrets
import socket
import sys
import threading
import time
import traceback
import urllib.request
import uuid
from pathlib import Path
from typing import Any, Callable

import numpy as np
import soundfile as sf
from fastapi import APIRouter, FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, PlainTextResponse

VERSION = 1
PORT = int(os.environ.get("TELUGU_VOICE_PORT", "7860"))
MODEL_ID = "ai4bharat/IndicF5"
PUBLIC_SPACE = "https://ai4bharat-indicf5.hf.space"
SAMPLE_RATE = 24000
EXAMPLE_COUNT = 5  # the app's built-in voices use examples 1, 3 and 4

# model(text, ref_audio_path=..., ref_text=...) -> numpy audio at 24 kHz
Model = Callable[..., Any]


def log(message: str) -> None:
    print(time.strftime("%H:%M:%S"), message, flush=True)


# --- The AI model ---------------------------------------------------------------------


def _friendly_load_error(exc: BaseException) -> str:
    text = f"{type(exc).__name__}: {exc}"
    low = text.lower()
    if any(k in low for k in ("gated", "401", "403", "access to model", "restricted", "awaiting a review")):
        return (
            "Your Hugging Face account cannot download IndicF5 yet. Open https://huggingface.co/ai4bharat/IndicF5, "
            "log in, click 'Agree and access repository', then close and restart this window."
        )
    if any(k in low for k in ("connection", "timed out", "name resolution", "offline")):
        return "Could not download the AI model. Check the PC's internet connection, then restart this window."
    return "The AI model could not start: " + text[:400]


class Engine:
    """Loads IndicF5 once and speaks one request at a time."""

    def __init__(self, home: Path, model: Model | None = None, device: str = "test"):
        self.home = home
        self.outputs = home / "data" / "outputs"
        self.outputs.mkdir(parents=True, exist_ok=True)
        self.model = model
        self.device = device if model is not None else "not loaded"
        self.error: str | None = None
        self.ready = threading.Event()
        self.lock = threading.Lock()
        if model is not None:
            self.ready.set()

    def load(self) -> None:
        try:
            token_file = self.home / "hf_token.txt"
            token = token_file.read_text(encoding="utf-8").strip() if token_file.exists() else os.environ.get("HF_TOKEN")
            if token:
                os.environ["HF_TOKEN"] = token
            log("Loading the IndicF5 voice model (the first time it downloads about 1.4 GB)...")
            import torch
            from transformers import AutoModel

            model = AutoModel.from_pretrained(MODEL_ID, trust_remote_code=True, token=token or None)
            if torch.cuda.is_available():
                model = model.to("cuda")
                self.device = f"GPU ({torch.cuda.get_device_name(0)})"
            else:
                model = model.to("cpu")
                self.device = "CPU (no NVIDIA graphics found - slower, still unlimited)"
            self.model = model
            log(f"Voice model ready on {self.device}.")
        except BaseException as exc:  # noqa: BLE001 - report every failure to the user
            self.error = _friendly_load_error(exc)
            log("ERROR: " + self.error)
            traceback.print_exc()
        finally:
            self.ready.set()

    @staticmethod
    def _as_wav(path: Path) -> Path:
        """IndicF5 reads reference audio most reliably as plain PCM WAV."""
        try:
            data, rate = sf.read(str(path), always_2d=False)
        except Exception as exc:
            raise ValueError("Please use a WAV or MP3 recording (this file could not be read).") from exc
        if getattr(data, "ndim", 1) > 1:
            data = data.mean(axis=1)
        out = path.with_name(path.stem + "_ref.wav")
        sf.write(str(out), data, rate, subtype="PCM_16")
        return out

    def speak(self, text: str, ref_audio: Path, ref_text: str) -> Path:
        if not self.ready.wait(timeout=1800):
            raise RuntimeError("The voice model is still loading. Please try again in a minute.")
        if self.model is None:
            raise RuntimeError(self.error or "The voice model is not loaded.")
        if not text.strip():
            raise ValueError("Type some text first.")
        if not ref_text.strip():
            raise ValueError("The voice sample has no transcript.")
        ref = self._as_wav(ref_audio)
        started = time.time()
        with self.lock:
            audio = self.model(text, ref_audio_path=str(ref), ref_text=ref_text)
        audio = np.asarray(audio)
        if audio.dtype == np.int16:
            audio = audio.astype(np.float32) / 32768.0
        audio = np.clip(audio.astype(np.float32).reshape(-1), -1.0, 1.0)
        out = self.outputs / f"{uuid.uuid4().hex}.wav"
        sf.write(str(out), audio, SAMPLE_RATE, subtype="PCM_16")
        log(f"Made {len(audio) / SAMPLE_RATE:.1f} s of speech in {time.time() - started:.1f} s.")
        return out


# --- The built-in example voices (Female 1/2, Male) ------------------------------------------


def _space_call(api: str, data: list, timeout: float = 60) -> list:
    req = urllib.request.Request(
        f"{PUBLIC_SPACE}/gradio_api/call/{api}",
        data=json.dumps({"data": data}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        event_id = json.loads(r.read())["event_id"]
    with urllib.request.urlopen(f"{PUBLIC_SPACE}/gradio_api/call/{api}/{event_id}", timeout=timeout) as r:
        lines = r.read().decode("utf-8").splitlines()
    for i, line in enumerate(lines):
        if line.startswith("event: complete") and i + 1 < len(lines):
            return json.loads(lines[i + 1][5:].strip())
    raise RuntimeError("no result")


class Examples:
    """Copies AI4Bharat's sample speakers from the free online server once.
    (Loading examples uses no GPU time there.)"""

    def __init__(self, home: Path):
        self.dir = home / "data" / "examples"
        self.dir.mkdir(parents=True, exist_ok=True)
        self.lock = threading.Lock()

    def get(self, index: int) -> dict | None:
        meta = self.dir / f"ex{index}.json"
        audio = self.dir / f"ex{index}.wav"
        if meta.exists() and audio.exists():
            info = json.loads(meta.read_text(encoding="utf-8"))
            return {**info, "path": str(audio)}
        return None

    def fetch(self, index: int) -> dict | None:
        with self.lock:
            existing = self.get(index)
            if existing:
                return existing
            try:
                out = _space_call("load_example", [index])
                value = lambda o: o.get("value") if isinstance(o, dict) and "__type__" in o else o  # noqa: E731
                ref = value(out[1])
                with urllib.request.urlopen(f"{PUBLIC_SPACE}/gradio_api/file={ref['path']}", timeout=60) as r:
                    (self.dir / f"ex{index}.wav").write_bytes(r.read())
                info = {"text": value(out[0]) or "", "ref_text": value(out[2]) or ""}
                (self.dir / f"ex{index}.json").write_text(json.dumps(info, ensure_ascii=False), encoding="utf-8")
                return self.get(index)
            except Exception as exc:  # noqa: BLE001
                log(f"Could not copy sample voice {index} yet ({exc}); will try again later.")
                return None

    def count(self) -> int:
        return sum(1 for i in range(EXAMPLE_COUNT) if self.get(i))

    def fetch_all_in_background(self) -> None:
        threading.Thread(target=lambda: [self.fetch(i) for i in range(EXAMPLE_COUNT)], daemon=True).start()


# --- The web API (same shape as Gradio's) ----------------------------------------------------


def create_app(home: Path, engine: Engine, code: str, examples: Examples | None = None) -> FastAPI:
    home = home.resolve()
    data_dir = (home / "data").resolve()
    uploads = data_dir / "uploads"
    uploads.mkdir(parents=True, exist_ok=True)
    examples = examples or Examples(home)
    jobs: dict[str, tuple[str, list, float]] = {}
    jobs_lock = threading.Lock()

    app = FastAPI(title="Telugu AI Voice - PC voice server", docs_url=None, redoc_url=None, openapi_url=None)
    api = APIRouter(prefix=f"/k/{code}")

    # Paths given to the app are relative to the data folder, with forward
    # slashes, so they are safe inside URLs on Windows too.
    def file_data(path: Path) -> dict:
        return {"path": path.resolve().relative_to(data_dir).as_posix(), "meta": {"_type": "gradio.FileData"}}

    def inside_data(path_text: str) -> Path:
        path = (data_dir / path_text.replace("\\", "/").lstrip("/")).resolve()
        if data_dir not in path.parents or not path.is_file():
            raise HTTPException(404, "Not found")
        return path

    @api.get("/info")
    def info() -> dict:
        return {
            "server": "telugu-voice-pc",
            "version": VERSION,
            "model_ready": engine.model is not None,
            "loading": not engine.ready.is_set(),
            "device": engine.device,
            "error": engine.error,
            "examples": examples.count(),
        }

    @api.post("/gradio_api/upload")
    def upload(files: list[UploadFile] = File(...)) -> list[str]:
        saved = []
        for f in files:
            folder = uploads / uuid.uuid4().hex
            folder.mkdir(parents=True)
            name = "".join(c for c in (f.filename or "audio.wav") if c.isalnum() or c in "._-")[-60:] or "audio.wav"
            target = folder / name
            with open(target, "wb") as out:
                while chunk := f.file.read(1 << 20):
                    out.write(chunk)
                    if out.tell() > 25 * 1024 * 1024:
                        raise HTTPException(413, "File too large")
            saved.append(target.relative_to(data_dir).as_posix())
        return saved

    @api.post("/gradio_api/call/{api_name}")
    async def start(api_name: str, request: Request) -> dict:
        body = await request.json()
        data = body.get("data") if isinstance(body, dict) else None
        if api_name not in ("synthesize_speech", "load_example") or not isinstance(data, list):
            raise HTTPException(404, "Unknown API")
        event_id = uuid.uuid4().hex
        with jobs_lock:
            now = time.time()
            for key in [k for k, (_, _, t) in jobs.items() if now - t > 3600]:
                jobs.pop(key, None)
            jobs[event_id] = (api_name, data, now)
        return {"event_id": event_id}

    def run(api_name: str, data: list) -> list:
        if api_name == "load_example":
            index = int(data[0])
            ex = examples.get(index) or examples.fetch(index)
            if ex is None:
                raise RuntimeError("The sample voices are not copied yet. Check the PC's internet and try again.")
            return [
                {"__type__": "update", "value": ex["text"]},
                {"__type__": "update", "value": file_data(Path(ex["path"]))},
                {"__type__": "update", "value": ex["ref_text"]},
            ]
        text, ref, ref_text = data[0], data[1], data[2]
        try:
            ref_path = inside_data(ref.get("path", "") if isinstance(ref, dict) else str(ref))
        except HTTPException:
            raise RuntimeError("The voice sample did not reach the PC. Please try again.") from None
        return [file_data(engine.speak(str(text), ref_path, str(ref_text)))]

    @api.get("/gradio_api/call/{api_name}/{event_id}")
    def result(api_name: str, event_id: str) -> PlainTextResponse:
        with jobs_lock:
            job = jobs.pop(event_id, None)
        if job is None or job[0] != api_name:
            raise HTTPException(404, "Unknown request")
        try:
            out = run(api_name, job[1])
            body = f"event: complete\ndata: {json.dumps(out, ensure_ascii=False)}\n\n"
        except Exception as exc:  # noqa: BLE001 - shown to the user in the app
            log(f"Request failed: {exc}")
            body = f"event: error\ndata: {json.dumps(str(exc)[:300], ensure_ascii=False)}\n\n"
        return PlainTextResponse(body, media_type="text/event-stream")

    @api.get("/gradio_api/file={path:path}")
    def download(path: str) -> FileResponse:
        return FileResponse(inside_data(path), media_type="audio/wav")

    app.include_router(api)
    return app


# --- Start-up -----------------------------------------------------------------------------


def load_code(home: Path) -> str:
    config = home / "config.json"
    if config.exists():
        try:
            code = json.loads(config.read_text(encoding="utf-8")).get("code")
            if isinstance(code, str) and code.isdigit():
                return code
        except Exception:  # noqa: BLE001
            pass
    code = f"{secrets.randbelow(900000) + 100000}"
    config.write_text(json.dumps({"code": code}), encoding="utf-8")
    return code


def lan_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def keep_awake() -> None:
    """Stops Windows from sleeping while this window is open."""
    if sys.platform == "win32":
        try:
            import ctypes

            ctypes.windll.kernel32.SetThreadExecutionState(0x80000000 | 0x00000001)  # CONTINUOUS | SYSTEM_REQUIRED
        except Exception:  # noqa: BLE001
            pass


def main() -> None:
    import uvicorn

    home = Path(os.environ.get("TELUGU_VOICE_HOME") or Path(__file__).resolve().parent)
    home.mkdir(parents=True, exist_ok=True)
    code = load_code(home)
    engine = Engine(home)
    threading.Thread(target=engine.load, daemon=True).start()
    examples = Examples(home)
    examples.fetch_all_in_background()
    app = create_app(home, engine, code, examples)
    address = f"http://{lan_ip()}:{PORT}/k/{code}"
    (home / "address.txt").write_text(address, encoding="utf-8")
    keep_awake()
    line = "=" * 64
    print(f"\n{line}\n  Telugu AI Voice - PC voice server is ON\n\n"
          f"  In the phone app: Settings > My PC voice server, type:\n\n      {address}\n\n"
          f"  * Keep this window open (the PC will not sleep while it is open).\n"
          f"  * Phone and PC must be on the same Wi-Fi.\n"
          f"  * If Windows asks about the firewall, tick 'Private networks' and click Allow.\n{line}\n", flush=True)
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="warning")


if __name__ == "__main__":
    main()
