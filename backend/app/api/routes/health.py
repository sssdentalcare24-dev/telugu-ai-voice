from __future__ import annotations

from fastapi import APIRouter

from ...core.config import ALLOWED_AUDIO_FORMATS
from ...schemas import VoiceOut, VoicesOut
from ..deps import Ctx

router = APIRouter(prefix="/api", tags=["system"])


@router.get("/health", summary="Service health and honest feature availability")
def health(ctx: Ctx) -> dict:
    s = ctx.settings
    caps = ctx.registry.capabilities()
    caps["storage"] = {"available": True, "backend": ctx.storage.backend_name}
    caps["history"] = {"available": True, "backend": ctx.repo.backend_name}
    caps["voice_cloning"] = ctx.clone.capability()
    return {
        "status": "ok",
        "service": s.app_name,
        "version": s.app_version,
        "environment": s.app_env,
        "auth_mode": s.auth_mode,
        "capabilities": caps,
        "limits": {
            "max_upload_mb": s.max_upload_mb,
            "max_audio_seconds": s.max_audio_seconds,
            "max_tts_chars": s.max_tts_chars,
            "allowed_formats": list(ALLOWED_AUDIO_FORMATS),
        },
    }


@router.get("/voices", response_model=VoicesOut, summary="Telugu voices from config/voices.yaml")
def voices(ctx: Ctx) -> VoicesOut:
    ready = set(ctx.registry.capabilities()["tts"]["ready_providers"])
    out = [
        VoiceOut(**v.model_dump(exclude={"provider_voice"}), available=v.provider in ready)
        for v in ctx.catalog.voices
        if v.provider in ctx.settings.enabled_tts_providers
    ]
    return VoicesOut(voices=out)
