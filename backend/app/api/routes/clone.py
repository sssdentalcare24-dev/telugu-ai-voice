"""Personal voice cloning: profiles (with consent), samples, cloning, and
speech in a saved voice, plus generation history.

Flow: POST /profiles (name, category, language, consent) -> POST
/profiles/{id}/sample (recording) -> POST /profiles/{id}/clone -> POST /tts
as often as wanted. The voice never has to be recorded again.
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, File, Form, Query, Response, UploadFile

from ...core.auth import User
from ...core.errors import ApiError
from ...providers.base import AudioPayload
from ...providers.cloning import LANGUAGE_BY_CODE, LANGUAGES, PREVIEW_TEXT, ClonedVoice, VoiceSample
from ...schemas import (
    CloneTtsIn,
    CreateProfileIn,
    GenerationOut,
    GenerationsOut,
    ProfileOut,
    ProfilesOut,
)
from ...services.audio import MIME_TYPES, AudioInfo, probe_duration, sniff_format, validate_audio
from ...services.clone_repository import GenerationRecord, VoiceProfileRecord
from ...services.text import normalize_text
from ..deps import AppContext, Ctx, CurrentUser
from .audio import read_upload

router = APIRouter(prefix="/api/clone", tags=["voice cloning"])
log = logging.getLogger("telugu_voice.clone")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds")


def _profile_out(ctx: AppContext, p: VoiceProfileRecord, warning: str | None = None) -> ProfileOut:
    def audio(audio_id: str | None):
        if not audio_id:
            return None
        record = ctx.repo.get(audio_id)
        return ctx.to_out(record) if record else None

    return ProfileOut(
        id=p.id,
        name=p.name,
        category=p.category,  # type: ignore[arg-type]
        recording_language=p.recording_language,
        provider=p.provider,
        provider_voice_id=p.provider_voice_id,
        status=p.status,
        created_at=p.created_at,
        updated_at=p.updated_at,
        transcript=p.transcript,
        consent=p.consent,
        sample=audio(p.sample_audio_id),
        preview=audio(p.preview_audio_id),
        error=p.error,
        warning=warning,
    )


def _owned_profile(ctx: AppContext, profile_id: str, user: User) -> VoiceProfileRecord:
    p = ctx.clone_repo.get_profile(profile_id)
    if p is None or p.owner_id != user.uid:
        raise ApiError(404, "NOT_FOUND", "Voice profile not found.")
    return p


def _payload_info(payload: AudioPayload) -> AudioInfo:
    fmt = sniff_format(payload.data)
    duration = probe_duration(payload.data) if fmt else None
    if fmt is None or duration is None:
        raise ApiError(502, "PROVIDER_ERROR", "The voice provider returned audio that could not be read.")
    return AudioInfo(format=fmt, mime_type=MIME_TYPES[fmt], duration_seconds=round(duration, 2), size_bytes=len(payload.data))


def _cloned_voice(ctx: AppContext, p: VoiceProfileRecord) -> ClonedVoice:
    sample = None
    if p.sample_audio_id:
        record = ctx.repo.get(p.sample_audio_id)
        if record is not None:
            try:
                data = ctx.storage.read(record.storage_key)
            except FileNotFoundError:
                data = None
            if data:
                sample = VoiceSample(data, record.format, record.mime_type, p.name, p.recording_language, p.transcript)
    if p.provider_voice_id is None:
        raise ApiError(409, "VOICE_NOT_READY", "This voice has not been created yet.")
    return ClonedVoice(p.provider_voice_id, sample)


def _speak(ctx: AppContext, user: User, p: VoiceProfileRecord, text: str, language: str, speed: float, *, title: str, preview: bool):
    provider = ctx.clone.get(p.provider)
    payload = provider.synthesize(_cloned_voice(ctx, p), text, language, speed)
    info = _payload_info(payload)
    return ctx.store_audio(
        owner_id=user.uid,
        kind="tts",
        title=title,
        data=payload.data,
        info=info,
        parameters={
            "clone_profile_id": p.id,
            "profile_name": p.name,
            "language": language,
            "provider": p.provider,
            "speed": speed,
            "preview": preview,
        },
    )


# --- Providers & languages ------------------------------------------------------------


@router.get("/providers", summary="Voice cloning providers, their status and requirements")
def providers(ctx: Ctx) -> dict:
    return {
        **ctx.clone.capability(),
        "languages": [{"code": lang.code, "name": lang.name, "native": lang.native} for lang in LANGUAGES],
        "limits": {
            "max_profiles": ctx.settings.max_voice_profiles,
            "max_chars": ctx.settings.max_clone_chars,
        },
    }


# --- Profiles ----------------------------------------------------------------------------


@router.post("/profiles", response_model=ProfileOut, status_code=201, summary="Create a voice profile (step 1)")
def create_profile(body: CreateProfileIn, ctx: Ctx, user: CurrentUser) -> ProfileOut:
    if not body.consent.confirmed:
        raise ApiError(400, "CONSENT_REQUIRED", "Confirm that this is your voice or that the speaker gave permission.")
    if body.recording_language not in LANGUAGE_BY_CODE:
        raise ApiError(422, "UNSUPPORTED_LANGUAGE", "Unknown recording language.")
    provider = ctx.clone.get(body.provider)
    if ctx.clone_repo.count_profiles(user.uid) >= ctx.settings.max_voice_profiles:
        raise ApiError(409, "PROFILE_LIMIT", f"You can save up to {ctx.settings.max_voice_profiles} voices. Delete one first.")
    ctx.limiter.check(f"clone-create:{user.uid}", ctx.settings.clone_create_per_hour)
    now = _now()
    record = VoiceProfileRecord(
        id=uuid.uuid4().hex,
        owner_id=user.uid,
        name=body.name.strip(),
        category=body.category,
        recording_language=body.recording_language,
        provider=provider.name,
        status="draft",
        created_at=now,
        updated_at=now,
        consent={**body.consent.model_dump(), "accepted_at": now, "user_id": user.uid},
    )
    ctx.clone_repo.save_profile(record)
    return _profile_out(ctx, record)


@router.post("/profiles/{profile_id}/sample", response_model=ProfileOut, summary="Upload the voice recording (step 2)")
def upload_sample(
    profile_id: str,
    ctx: Ctx,
    user: CurrentUser,
    file: Annotated[UploadFile, File(description="WAV, MP3, OGG, FLAC or M4A recording of one speaker")],
    transcript: Annotated[str | None, Form(max_length=1000)] = None,
) -> ProfileOut:
    p = _owned_profile(ctx, profile_id, user)
    provider = ctx.clone.get(p.provider)
    req = provider.requirements
    data = read_upload(file, ctx.settings.max_upload_bytes)
    info = validate_audio(data, max_bytes=ctx.settings.max_upload_bytes, max_seconds=int(req.max_seconds) + 1)
    if info.duration_seconds < req.min_seconds:
        raise ApiError(
            422,
            "SAMPLE_TOO_SHORT",
            f"The recording is {info.duration_seconds:.0f} s. Please record at least {req.min_seconds:.0f} seconds.",
        )
    text = normalize_text(transcript or "") if transcript else None
    if req.needs_transcript and not (text and len(text) >= 2):
        raise ApiError(422, "TRANSCRIPT_REQUIRED", "Type the exact words spoken in the recording.")
    record = ctx.store_audio(
        owner_id=user.uid,
        kind="original",
        title=f"Voice sample · {p.name}",
        data=data,
        info=info,
        parameters={"source": "voice_sample", "clone_profile_id": p.id},
    )
    old = p.sample_audio_id
    p.sample_audio_id = record.id
    p.transcript = text
    p.status = "draft"
    p.provider_voice_id = None
    p.error = None
    p.updated_at = _now()
    ctx.clone_repo.save_profile(p)
    if old:
        _delete_audio(ctx, old)
    return _profile_out(ctx, p)


@router.post("/profiles/{profile_id}/clone", response_model=ProfileOut, summary="Create the AI voice (step 3)")
def clone_profile(profile_id: str, ctx: Ctx, user: CurrentUser) -> ProfileOut:
    p = _owned_profile(ctx, profile_id, user)
    if not p.sample_audio_id:
        raise ApiError(409, "SAMPLE_MISSING", "Upload a voice recording first.")
    provider = ctx.clone.get(p.provider)
    sample_record = ctx.repo.get(p.sample_audio_id)
    if sample_record is None:
        raise ApiError(409, "SAMPLE_MISSING", "The voice recording was deleted. Upload it again.")
    sample = VoiceSample(
        ctx.storage.read(sample_record.storage_key),
        sample_record.format,
        sample_record.mime_type,
        p.name,
        p.recording_language,
        p.transcript,
    )
    try:
        p.provider_voice_id = provider.create_voice(sample)
    except ApiError as exc:
        p.status = "failed"
        p.error = exc.message
        p.updated_at = _now()
        ctx.clone_repo.save_profile(p)
        raise
    p.status = "ready"
    p.error = None
    p.updated_at = _now()
    ctx.clone_repo.save_profile(p)

    # A short preview proves the clone works. A busy provider does not undo the
    # saved voice; the user can generate speech later.
    warning = None
    langs = provider.requirements.languages
    lang = next((c for c in (p.recording_language, "te", "hi", "en") if c in PREVIEW_TEXT and c in langs), None)
    try:
        if lang is None:
            raise ApiError(422, "UNSUPPORTED_LANGUAGE", "No preview sentence for this provider's languages.")
        preview = _speak(ctx, user, p, PREVIEW_TEXT[lang], lang, 1.0, title=f"Preview · {p.name}", preview=True)
        if p.preview_audio_id:
            _delete_audio(ctx, p.preview_audio_id)
        p.preview_audio_id = preview.id
        ctx.clone_repo.save_profile(p)
    except ApiError as exc:
        warning = f"Voice saved, but the preview could not be made now: {exc.message}"
    return _profile_out(ctx, p, warning)


@router.get("/profiles", response_model=ProfilesOut, summary="My voice library")
def list_profiles(ctx: Ctx, user: CurrentUser) -> ProfilesOut:
    return ProfilesOut(profiles=[_profile_out(ctx, p) for p in ctx.clone_repo.list_profiles(user.uid)])


@router.get("/profiles/{profile_id}", response_model=ProfileOut, summary="One voice profile")
def get_profile(profile_id: str, ctx: Ctx, user: CurrentUser) -> ProfileOut:
    return _profile_out(ctx, _owned_profile(ctx, profile_id, user))


@router.delete("/profiles/{profile_id}", status_code=204, summary="Delete a voice profile and its sample")
def delete_profile(profile_id: str, ctx: Ctx, user: CurrentUser) -> Response:
    p = _owned_profile(ctx, profile_id, user)
    if p.provider_voice_id and p.provider in ctx.clone.providers:
        try:
            ctx.clone.providers[p.provider].delete_voice(p.provider_voice_id)
        except ApiError as exc:
            # The local profile is still removed; log so an admin can clean up.
            log.warning("Could not delete voice %s at %s: %s", p.provider_voice_id, p.provider, exc.message)
    for audio_id in (p.sample_audio_id, p.preview_audio_id):
        if audio_id:
            _delete_audio(ctx, audio_id)
    ctx.clone_repo.delete_profile(p.id)
    return Response(status_code=204)


def _delete_audio(ctx: AppContext, audio_id: str) -> None:
    record = ctx.repo.get(audio_id)
    if record is not None:
        ctx.storage.delete(record.storage_key)
        ctx.repo.delete(record.id)


# --- Speech in a saved voice ----------------------------------------------------------


def _generation_out(ctx: AppContext, g: GenerationRecord) -> GenerationOut:
    record = ctx.repo.get(g.audio_id)
    return GenerationOut(
        id=g.id,
        profile_id=g.profile_id,
        profile_name=g.profile_name,
        text=g.text,
        language=g.language,
        provider=g.provider,
        speed=g.speed,
        created_at=g.created_at,
        audio=ctx.to_out(record) if record else None,
    )


@router.post("/tts", response_model=GenerationOut, status_code=201, summary="Speak text in a saved voice")
def clone_tts(body: CloneTtsIn, ctx: Ctx, user: CurrentUser) -> GenerationOut:
    p = _owned_profile(ctx, body.profile_id, user)
    if p.status != "ready":
        raise ApiError(409, "VOICE_NOT_READY", "This voice is not ready yet. Finish creating it first.")
    provider = ctx.clone.get(p.provider)
    if body.language not in provider.requirements.languages:
        name = LANGUAGE_BY_CODE.get(body.language).name if body.language in LANGUAGE_BY_CODE else body.language
        raise ApiError(422, "UNSUPPORTED_LANGUAGE", f"{provider.label} does not speak {name}.")
    text = normalize_text(body.text)
    if not text:
        raise ApiError(422, "EMPTY_TEXT", "Type some text first.")
    if len(text) > ctx.settings.max_clone_chars:
        raise ApiError(422, "TEXT_TOO_LONG", f"Text must be {ctx.settings.max_clone_chars} characters or fewer.")
    ctx.limiter.check(f"clone-tts:{user.uid}", ctx.settings.clone_generate_per_hour)
    speed = body.speed if provider.requirements.supports_speed else 1.0
    title = (body.title or "").strip() or (text[:48] + ("…" if len(text) > 48 else ""))
    record = _speak(ctx, user, p, text, body.language, speed, title=title, preview=False)
    g = GenerationRecord(
        id=uuid.uuid4().hex,
        owner_id=user.uid,
        profile_id=p.id,
        profile_name=p.name,
        audio_id=record.id,
        text=text,
        language=body.language,
        provider=p.provider,
        speed=speed,
        created_at=record.created_at,
    )
    ctx.clone_repo.add_generation(g)
    return _generation_out(ctx, g)


@router.get("/history", response_model=GenerationsOut, summary="Speech made with saved voices, newest first")
def history(
    ctx: Ctx,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    before: Annotated[str | None, Query(max_length=40)] = None,
    profile_id: Annotated[str | None, Query(max_length=64)] = None,
) -> GenerationsOut:
    items = ctx.clone_repo.list_generations(user.uid, limit=limit, before=before, profile_id=profile_id)
    next_cursor = items[-1].created_at if len(items) == limit else None
    return GenerationsOut(items=[_generation_out(ctx, g) for g in items], next_cursor=next_cursor)


@router.delete("/history/{generation_id}", status_code=204, summary="Delete generated audio")
def delete_generation(generation_id: str, ctx: Ctx, user: CurrentUser) -> Response:
    g = ctx.clone_repo.get_generation(generation_id)
    if g is None or g.owner_id != user.uid:
        raise ApiError(404, "NOT_FOUND", "Generated audio not found.")
    _delete_audio(ctx, g.audio_id)
    ctx.clone_repo.delete_generation(g.id)
    return Response(status_code=204)
