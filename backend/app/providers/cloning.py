"""Personal voice cloning providers.

A provider turns one authorised voice sample into a reusable voice, then speaks
any text in that voice. Each vendor sits behind VoiceCloneProvider, so the app
and the API routes never change when a provider is added or swapped:

* indicf5    - AI4Bharat IndicF5 on a Hugging Face Space. Free, zero-shot:
               the sample and its transcript are sent with every request.
               11 Indian languages, no English. Small free daily GPU allowance
               (an optional HF_TOKEN raises it). Licence: see README.
* sarvam     - Sarvam AI Instant Voice Cloning (beta). Paid per character.
               Saved voice ids, Indian languages + Indian English, pace control.
* elevenlabs - ElevenLabs Instant Voice Cloning with the eleven_v4 model.
               Paid plan required (Starter or higher). 90+ languages.

API keys are read from server settings only; nothing here is sent to the app.
"""

from __future__ import annotations

import base64
import io
import json
import logging
import wave
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Callable

import httpx

from ..core.config import Settings
from ..core.errors import ApiError
from ..services.text import split_for_tts
from .base import AudioPayload, ProviderState, ProviderStatus

log = logging.getLogger("telugu_voice.cloning")


# --- Languages ----------------------------------------------------------------------


@dataclass(frozen=True)
class CloneLanguage:
    code: str  # ISO 639-1 (what the app sends)
    name: str
    native: str
    sarvam: str | None  # Sarvam language_code, None if not offered


LANGUAGES: tuple[CloneLanguage, ...] = (
    CloneLanguage("te", "Telugu", "తెలుగు", "te-IN"),
    CloneLanguage("hi", "Hindi", "हिन्दी", "hi-IN"),
    CloneLanguage("en", "English", "English", "en-IN"),
    CloneLanguage("ta", "Tamil", "தமிழ்", "ta-IN"),
    CloneLanguage("kn", "Kannada", "ಕನ್ನಡ", "kn-IN"),
    CloneLanguage("ml", "Malayalam", "മലയാളം", "ml-IN"),
    CloneLanguage("mr", "Marathi", "मराठी", "mr-IN"),
    CloneLanguage("bn", "Bengali", "বাংলা", "bn-IN"),
    CloneLanguage("gu", "Gujarati", "ગુજરાતી", "gu-IN"),
    CloneLanguage("pa", "Punjabi", "ਪੰਜਾਬੀ", "pa-IN"),
    CloneLanguage("or", "Odia", "ଓଡ଼ିଆ", "od-IN"),
    CloneLanguage("as", "Assamese", "অসমীয়া", None),
)
LANGUAGE_BY_CODE = {lang.code: lang for lang in LANGUAGES}

# Short line spoken in each new voice so the user can hear the clone at once.
PREVIEW_TEXT = {
    "te": "నమస్కారం! ఇది నా కొత్త AI స్వరం. మీకు ఎలా అనిపిస్తోంది?",
    "hi": "नमस्ते! यह मेरी नई AI आवाज़ है। आपको कैसी लगी?",
    "en": "Hello! This is my new AI voice. How does it sound?",
}


# --- Types ----------------------------------------------------------------------------


@dataclass(frozen=True)
class CloneRequirements:
    min_seconds: float
    max_seconds: float
    recommended: str
    needs_transcript: bool
    languages: tuple[str, ...]
    cross_lingual: bool
    supports_speed: bool


@dataclass(frozen=True)
class VoiceSample:
    data: bytes
    format: str
    mime_type: str
    name: str
    language: str
    transcript: str | None = None


@dataclass(frozen=True)
class ClonedVoice:
    provider_voice_id: str
    sample: VoiceSample | None = None


class VoiceCloneProvider(ABC):
    name: str
    label: str
    paid: bool
    requirements: CloneRequirements

    @abstractmethod
    def status(self) -> ProviderStatus: ...

    @abstractmethod
    def create_voice(self, sample: VoiceSample) -> str:
        """Registers the voice and returns the provider's voice id."""

    @abstractmethod
    def synthesize(self, voice: ClonedVoice, text: str, language: str, speed: float) -> AudioPayload: ...

    def delete_voice(self, provider_voice_id: str) -> None:  # noqa: B027 - optional
        """Removes the voice at the provider (no-op when nothing is stored there)."""

    def describe(self) -> dict:
        st = self.status()
        r = self.requirements
        return {
            **st.as_dict(),
            "label": self.label,
            "ready": st.ready,
            "min_seconds": r.min_seconds,
            "max_seconds": r.max_seconds,
            "recommended": r.recommended,
            "needs_transcript": r.needs_transcript,
            "languages": list(r.languages),
            "cross_lingual": r.cross_lingual,
            "supports_speed": r.supports_speed,
        }


# --- Helpers ----------------------------------------------------------------------------


def join_wavs(clips: list[bytes], gap_seconds: float = 0.3) -> bytes:
    """Concatenates PCM WAV clips of one format with a short pause between them."""
    if len(clips) == 1:
        return clips[0]
    params = None
    frames: list[bytes] = []
    for clip in clips:
        with wave.open(io.BytesIO(clip)) as w:
            p = (w.getnchannels(), w.getsampwidth(), w.getframerate())
            if params is None:
                params = p
            elif p != params:
                raise ApiError(502, "PROVIDER_ERROR", "The voice provider returned audio in mixed formats.")
            if frames:
                frames.append(b"\x00" * int(p[2] * gap_seconds) * p[0] * p[1])
            frames.append(w.readframes(w.getnframes()))
    assert params is not None
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(params[0])
        w.setsampwidth(params[1])
        w.setframerate(params[2])
        w.writeframes(b"".join(frames))
    return out.getvalue()


def _raise_for(provider: str, response: httpx.Response) -> None:
    if response.is_success:
        return
    code = response.status_code
    detail = ""
    try:
        body = response.json()
        detail = str(
            (body.get("error") or {}).get("message")
            if isinstance(body.get("error"), dict)
            else body.get("detail") or body.get("error") or body.get("message") or ""
        )
    except Exception:
        detail = response.text[:200]
    if isinstance(detail, str) and len(detail) > 240:
        detail = detail[:240] + "…"
    log.warning("%s returned HTTP %s: %s", provider, code, detail)
    if code in (401, 403):
        raise ApiError(503, "PROVIDER_NOT_CONFIGURED", f"{provider} rejected the server's API key. Check it in the server settings.")
    if code == 402 or "quota" in detail.lower() or "credits" in detail.lower():
        raise ApiError(402, "PROVIDER_QUOTA", f"{provider}: the account's quota or credits are used up. {detail}".strip())
    if code == 429:
        raise ApiError(429, "PROVIDER_BUSY", f"{provider} is getting too many requests. Please try again in a minute.")
    if code in (502, 503, 504):
        raise ApiError(503, "PROVIDER_BUSY", f"{provider} is busy or starting up. Please try again in a minute.")
    if 400 <= code < 500:
        raise ApiError(422, "PROVIDER_REJECTED", f"{provider} could not use this request: {detail or 'HTTP ' + str(code)}")
    raise ApiError(502, "PROVIDER_ERROR", f"{provider} returned an error (HTTP {code}).")


def _request(provider: str, fn: Callable[[], httpx.Response]) -> httpx.Response:
    try:
        response = fn()
    except httpx.TimeoutException as exc:
        raise ApiError(504, "PROVIDER_TIMEOUT", f"{provider} took too long to answer. Please try again.") from exc
    except httpx.HTTPError as exc:
        raise ApiError(503, "PROVIDER_UNREACHABLE", f"The server cannot reach {provider} right now.") from exc
    _raise_for(provider, response)
    return response


# --- IndicF5 (free) ------------------------------------------------------------------


class IndicF5CloneProvider(VoiceCloneProvider):
    name = "indicf5"
    label = "AI4Bharat IndicF5 (free, Hugging Face)"
    paid = False
    requirements = CloneRequirements(
        min_seconds=4,
        max_seconds=15,
        recommended="8–12 seconds of one person reading the shown sentence, in a quiet room.",
        needs_transcript=True,
        languages=("te", "hi", "ta", "kn", "ml", "mr", "bn", "gu", "pa", "or", "as"),
        cross_lingual=True,
        supports_speed=False,
    )
    CHUNK_BYTES = 1800  # about 600 Telugu letters; one ZeroGPU call each

    def __init__(self, settings: Settings, client: httpx.Client | None = None):
        self.base = settings.indicf5_space_url.rstrip("/")
        headers = {"Authorization": f"Bearer {settings.hf_token}"} if settings.hf_token else {}
        self.client = client or httpx.Client(timeout=httpx.Timeout(240, connect=20), headers=headers)
        self.has_token = bool(settings.hf_token)

    def status(self) -> ProviderStatus:
        extra = "" if self.has_token else " Without HF_TOKEN each server connection gets only a few requests per day."
        return ProviderStatus(
            self.name,
            ProviderState.READY,
            "Free public Hugging Face server; can be busy." + extra,
            paid=False,
        )

    def create_voice(self, sample: VoiceSample) -> str:
        if not (sample.transcript and sample.transcript.strip()):
            raise ApiError(422, "TRANSCRIPT_REQUIRED", "Type the exact words spoken in the sample.")
        # Zero-shot: nothing is stored at the provider. The sample is kept by
        # this server and sent with each request.
        return "indicf5:zero-shot"

    def _call(self, api: str, data: list) -> list:
        start = _request(self.label, lambda: self.client.post(f"{self.base}/gradio_api/call/{api}", json={"data": data}))
        event_id = start.json().get("event_id")
        if not event_id:
            raise ApiError(502, "PROVIDER_ERROR", "The free voice server did not accept the request.")
        result = _request(self.label, lambda: self.client.get(f"{self.base}/gradio_api/call/{api}/{event_id}"))
        event = None
        for line in result.text.splitlines():
            if line.startswith("event:"):
                event = line[6:].strip()
            elif line.startswith("data:"):
                payload = line[5:].strip()
                if event == "complete":
                    return json.loads(payload)
                if event == "error":
                    msg = ""
                    try:
                        msg = json.loads(payload) or ""
                    except Exception:
                        msg = payload
                    msg = str(msg)
                    if "quota" in msg.lower() or not msg or msg == "None":
                        raise ApiError(
                            429,
                            "PROVIDER_BUSY",
                            "The free voice server is busy or its daily free limit is used up. "
                            "Try again later, or set HF_TOKEN on the server for a larger allowance.",
                        )
                    raise ApiError(502, "PROVIDER_ERROR", f"The free voice server reported: {msg[:200]}")
        raise ApiError(503, "PROVIDER_BUSY", "The free voice server stopped without a result. Please try again.")

    def synthesize(self, voice: ClonedVoice, text: str, language: str, speed: float) -> AudioPayload:
        sample = voice.sample
        if sample is None or not sample.transcript:
            raise ApiError(409, "SAMPLE_MISSING", "This voice has no saved sample.")
        upload = _request(
            self.label,
            lambda: self.client.post(
                f"{self.base}/gradio_api/upload",
                files={"files": (f"sample.{sample.format}", sample.data, sample.mime_type)},
            ),
        )
        paths = upload.json()
        if not isinstance(paths, list) or not paths:
            raise ApiError(502, "PROVIDER_ERROR", "The free voice server could not receive the sample.")
        ref = {"path": paths[0], "meta": {"_type": "gradio.FileData"}}
        clips = []
        for chunk in split_for_tts(text, self.CHUNK_BYTES):
            out = self._call("synthesize_speech", [chunk, ref, sample.transcript])
            first = out[0] if out else None
            value = first.get("value", first) if isinstance(first, dict) and "__type__" in first else first
            path = value.get("path") if isinstance(value, dict) else None
            if not path:
                raise ApiError(502, "PROVIDER_ERROR", "The free voice server did not return audio.")
            audio = _request(self.label, lambda p=path: self.client.get(f"{self.base}/gradio_api/file={p}"))
            clips.append(audio.content)
        return AudioPayload(join_wavs(clips), "wav", "audio/wav")


# --- Sarvam AI ------------------------------------------------------------------------


class SarvamCloneProvider(VoiceCloneProvider):
    name = "sarvam"
    label = "Sarvam AI Instant Voice Cloning"
    paid = True
    requirements = CloneRequirements(
        min_seconds=5,
        max_seconds=60,
        recommended="10–15 seconds of continuous, clean speech from one person.",
        needs_transcript=False,
        languages=tuple(lang.code for lang in LANGUAGES if lang.sarvam),
        cross_lingual=True,
        supports_speed=True,
    )
    BASE = "https://api.sarvam.ai"
    CHUNK_BYTES = 2400  # the API accepts up to 1,000 characters per request

    def __init__(self, settings: Settings, client: httpx.Client | None = None):
        self.key = settings.sarvam_api_key
        self.client = client or httpx.Client(timeout=httpx.Timeout(120, connect=15))

    def _headers(self) -> dict[str, str]:
        return {"api-subscription-key": self.key or ""}

    def status(self) -> ProviderStatus:
        if not self.key:
            return ProviderStatus(self.name, ProviderState.NOT_CONFIGURED, "Set SARVAM_API_KEY on the server (paid, per character).")
        return ProviderStatus(self.name, ProviderState.READY, "Sarvam AI voice cloning (beta), billed per character.")

    def create_voice(self, sample: VoiceSample) -> str:
        lang = LANGUAGE_BY_CODE.get(sample.language)
        response = _request(
            self.label,
            lambda: self.client.post(
                f"{self.BASE}/voices/create",
                headers=self._headers(),
                files={"file": (f"sample.{sample.format}", sample.data, sample.mime_type)},
                data={"name": sample.name[:60], "language": (lang.sarvam if lang and lang.sarvam else "en-IN")},
            ),
        )
        body = response.json()
        data = body.get("data", body) if isinstance(body, dict) else {}
        voice_id = data.get("voice_id") if isinstance(data, dict) else None
        if not voice_id:
            raise ApiError(502, "PROVIDER_ERROR", "Sarvam AI did not return a voice id.")
        return str(voice_id)

    def synthesize(self, voice: ClonedVoice, text: str, language: str, speed: float) -> AudioPayload:
        lang = LANGUAGE_BY_CODE[language]
        clips = []
        for chunk in split_for_tts(text, self.CHUNK_BYTES):
            response = _request(
                self.label,
                lambda c=chunk: self.client.post(
                    f"{self.BASE}/voices/clone",
                    headers=self._headers(),
                    data={
                        "voice_id": voice.provider_voice_id,
                        "text": c,
                        "language_code": lang.sarvam,
                        "output_audio_codec": "wav",
                        "pace": str(min(2.0, max(0.5, speed))),
                    },
                ),
            )
            body = response.json()
            b64 = body.get("audio") or body.get("audio_b64")
            if not b64:
                raise ApiError(502, "PROVIDER_ERROR", "Sarvam AI did not return audio.")
            clips.append(base64.b64decode(b64))
        return AudioPayload(join_wavs(clips), "wav", "audio/wav")

    def delete_voice(self, provider_voice_id: str) -> None:
        _request(self.label, lambda: self.client.delete(f"{self.BASE}/voices/delete/{provider_voice_id}", headers=self._headers()))


# --- ElevenLabs ---------------------------------------------------------------------------


class ElevenLabsCloneProvider(VoiceCloneProvider):
    name = "elevenlabs"
    label = "ElevenLabs Instant Voice Cloning"
    paid = True
    requirements = CloneRequirements(
        min_seconds=10,
        max_seconds=180,
        recommended="1–2 minutes of clean speech from one person (at least 10 seconds).",
        needs_transcript=False,
        languages=tuple(lang.code for lang in LANGUAGES),
        cross_lingual=True,
        supports_speed=True,
    )
    BASE = "https://api.elevenlabs.io"

    def __init__(self, settings: Settings, client: httpx.Client | None = None):
        self.key = settings.elevenlabs_api_key
        self.model = settings.elevenlabs_tts_model
        self.client = client or httpx.Client(timeout=httpx.Timeout(120, connect=15))

    def _headers(self) -> dict[str, str]:
        return {"xi-api-key": self.key or ""}

    def status(self) -> ProviderStatus:
        if not self.key:
            return ProviderStatus(
                self.name, ProviderState.NOT_CONFIGURED, "Set ELEVENLABS_API_KEY on the server (paid plan with voice cloning)."
            )
        return ProviderStatus(self.name, ProviderState.READY, f"ElevenLabs voice cloning with {self.model}.")

    def create_voice(self, sample: VoiceSample) -> str:
        response = _request(
            self.label,
            lambda: self.client.post(
                f"{self.BASE}/v1/voices/add",
                headers=self._headers(),
                files=[("files", (f"sample.{sample.format}", sample.data, sample.mime_type))],
                data={
                    "name": sample.name[:100],
                    "remove_background_noise": "true",
                    "description": "Personal voice created in Telugu AI Voice with the speaker's consent.",
                },
            ),
        )
        voice_id = response.json().get("voice_id")
        if not voice_id:
            raise ApiError(502, "PROVIDER_ERROR", "ElevenLabs did not return a voice id.")
        return str(voice_id)

    def synthesize(self, voice: ClonedVoice, text: str, language: str, speed: float) -> AudioPayload:
        response = _request(
            self.label,
            lambda: self.client.post(
                f"{self.BASE}/v1/text-to-speech/{voice.provider_voice_id}",
                params={"output_format": "mp3_44100_128"},
                headers={**self._headers(), "Content-Type": "application/json"},
                json={
                    "text": text,
                    "model_id": self.model,
                    "language_code": language,
                    "voice_settings": {"speed": min(1.2, max(0.7, speed))},
                },
            ),
        )
        return AudioPayload(response.content, "mp3", "audio/mpeg")

    def delete_voice(self, provider_voice_id: str) -> None:
        _request(self.label, lambda: self.client.delete(f"{self.BASE}/v1/voices/{provider_voice_id}", headers=self._headers()))


# --- Registry -----------------------------------------------------------------------------

CLONE_FACTORIES: dict[str, Callable[[Settings], VoiceCloneProvider]] = {
    "indicf5": IndicF5CloneProvider,
    "sarvam": SarvamCloneProvider,
    "elevenlabs": ElevenLabsCloneProvider,
}


@dataclass
class CloneRegistry:
    providers: dict[str, VoiceCloneProvider] = field(default_factory=dict)
    default: str = "indicf5"

    def get(self, name: str | None) -> VoiceCloneProvider:
        key = (name or self.default).lower()
        provider = self.providers.get(key)
        if provider is None:
            raise ApiError(400, "UNKNOWN_PROVIDER", f"Voice cloning provider '{key}' is not enabled on this server.")
        status = provider.status()
        if not status.ready:
            raise ApiError(503, "PROVIDER_NOT_CONFIGURED", status.message, {"provider": key})
        return provider

    def capability(self) -> dict:
        described = [p.describe() for p in self.providers.values()]
        return {
            "available": any(d["ready"] for d in described),
            "default": self.default,
            "providers": described,
        }


def build_clone_registry(settings: Settings) -> CloneRegistry:
    providers: dict[str, VoiceCloneProvider] = {}
    for name in settings.enabled_clone_providers:
        factory = CLONE_FACTORIES.get(name)
        if factory is None:
            log.warning("Unknown voice cloning provider in VOICE_CLONE_PROVIDERS: %s", name)
            continue
        providers[name] = factory(settings)
    default = settings.voice_clone_default if settings.voice_clone_default in providers else next(iter(providers), "")
    return CloneRegistry(providers=providers, default=default)
