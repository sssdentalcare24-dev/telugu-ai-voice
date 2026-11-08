from __future__ import annotations

from fastapi import APIRouter

from ...core.errors import ApiError
from ...providers.base import ProviderError, SynthesisRequest
from ...schemas import AudioItemOut, TTSRequest
from ...services.audio import validate_audio
from ...services.text import contains_telugu, normalize_text
from ..deps import Ctx, CurrentUser

router = APIRouter(prefix="/api/tts", tags=["text-to-speech"])


@router.post("/generate", response_model=AudioItemOut, status_code=201, summary="Generate Telugu speech")
def generate(body: TTSRequest, ctx: Ctx, user: CurrentUser) -> AudioItemOut:
    s = ctx.settings
    text = normalize_text(body.text)
    if not text:
        raise ApiError(422, "VALIDATION_ERROR", "Please enter some Telugu text.", [{"field": "text", "message": "Empty"}])
    if len(text) > s.max_tts_chars:
        raise ApiError(
            422,
            "TEXT_TOO_LONG",
            f"Text is {len(text)} characters; the limit is {s.max_tts_chars}.",
            [{"field": "text", "message": "Too long"}],
        )
    if not contains_telugu(text):
        raise ApiError(422, "NOT_TELUGU", "Please include Telugu text (తెలుగు). This studio is for Telugu speech.")

    voice = ctx.catalog.get(body.voice_id)
    if voice is None or voice.provider not in s.enabled_tts_providers:
        raise ApiError(422, "UNKNOWN_VOICE", "That voice is not available.", [{"field": "voice_id", "message": "Unknown"}])
    if body.pitch != 0 and not voice.supports_pitch:
        raise ApiError(422, "PITCH_UNSUPPORTED", f"{voice.display_name} does not support pitch changes.")
    if body.style and body.style not in voice.styles:
        raise ApiError(422, "STYLE_UNSUPPORTED", f"{voice.display_name} does not support the '{body.style}' style.")

    provider = ctx.registry.tts_provider(voice.provider)  # 503 if not configured
    try:
        audio = provider.synthesize(
            SynthesisRequest(
                text=text,
                language_code=voice.language_code,
                provider_voice=voice.provider_voice,
                speed=body.speed,
                pitch=body.pitch,
                style=body.style,
                audio_format="mp3",
            )
        )
    except ProviderError as exc:
        raise ApiError(502, "PROVIDER_ERROR", str(exc), {"provider": voice.provider}) from exc

    # Long outputs are allowed past the upload duration limit (they come from our own provider).
    info = validate_audio(audio.data, max_bytes=200 * 1024 * 1024, max_seconds=6 * 3600)
    title = (body.title or text.replace("\n", " "))[:60]
    record = ctx.store_audio(
        owner_id=user.uid,
        kind="tts",
        title=title,
        data=audio.data,
        info=info,
        parameters={
            "voice_id": voice.id,
            "provider": voice.provider,
            "gender": voice.gender,
            "speed": body.speed,
            "pitch": body.pitch,
            "style": body.style,
            "characters": len(text),
        },
    )
    return ctx.to_out(record)
