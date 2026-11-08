from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, File, Form, UploadFile

from ...core.errors import ApiError
from ...providers.base import AudioPayload, ConversionRequest, ProviderError
from ...schemas import ConvertOut, Direction, LiveSessionOut, LiveSessionRequest
from ...services.audio import validate_audio
from ..deps import Ctx, CurrentUser
from .audio import clean_title, read_upload

router = APIRouter(prefix="/api/voice", tags=["voice conversion"])

CONSENT_MESSAGE = (
    "Please confirm that this is your own voice, or that you have the speaker's permission, "
    "and that you will not use it to impersonate anyone."
)


@router.post("/convert", response_model=ConvertOut, status_code=201, summary="Convert recorded speech M→F or F→M")
def convert(
    ctx: Ctx,
    user: CurrentUser,
    direction: Annotated[Direction, Form()],
    consent: Annotated[bool, Form()] = False,
    file: Annotated[UploadFile | None, File()] = None,
    source_audio_id: Annotated[str | None, Form(max_length=64)] = None,
) -> ConvertOut:
    s = ctx.settings
    if not consent:
        raise ApiError(400, "CONSENT_REQUIRED", CONSENT_MESSAGE)
    if (file is None) == (source_audio_id is None):
        raise ApiError(422, "VALIDATION_ERROR", "Send either an audio file or source_audio_id (exactly one).")

    provider = ctx.registry.conversion_provider()  # 503 if not configured

    if file is not None:
        data = read_upload(file, s.max_upload_bytes)
        info = validate_audio(data, max_bytes=s.max_upload_bytes, max_seconds=s.max_audio_seconds)
        original = ctx.store_audio(
            owner_id=user.uid,
            kind="original",
            title=clean_title(file.filename),
            data=data,
            info=info,
            parameters={"source": "upload"},
        )
    else:
        original = ctx.owned_record(source_audio_id or "", user)
        data = ctx.storage.read(original.storage_key)

    target = s.vc_target_female_voice_id if direction == "male_to_female" else s.vc_target_male_voice_id
    try:
        result = provider.convert(
            ConversionRequest(
                audio=AudioPayload(data=data, format=original.format, mime_type=original.mime_type),
                direction=direction,
                target_voice=target,
            )
        )
    except ProviderError as exc:
        raise ApiError(502, "PROVIDER_ERROR", str(exc)) from exc

    out_info = validate_audio(result.data, max_bytes=200 * 1024 * 1024, max_seconds=6 * 3600)
    arrow = "M→F" if direction == "male_to_female" else "F→M"
    converted = ctx.store_audio(
        owner_id=user.uid,
        kind="converted",
        title=f"{original.title} ({arrow})"[:120],
        data=result.data,
        info=out_info,
        source_audio_id=original.id,
        parameters={"direction": direction, "provider": provider.name, "consent": True},
    )
    return ConvertOut(original=ctx.to_out(original), converted=ctx.to_out(converted))


@router.post("/live/session", response_model=LiveSessionOut, status_code=201, summary="Start a live conversion session")
def live_session(body: LiveSessionRequest, ctx: Ctx, user: CurrentUser) -> LiveSessionOut:
    if not body.consent:
        raise ApiError(400, "CONSENT_REQUIRED", CONSENT_MESSAGE)
    provider = ctx.registry.live_provider()  # 503 LIVE_CONVERSION_UNAVAILABLE if none
    info = provider.create_session(user.uid, body.direction)
    return LiveSessionOut(
        session_id=info.session_id,
        websocket_url=info.websocket_url,
        expires_at=info.expires_at,
        sample_rate=info.sample_rate,
        encoding=info.encoding,
    )
