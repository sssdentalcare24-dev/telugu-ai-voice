"""Builds the active providers from settings and reports honest status.

To add a vendor: implement the interface in base.py, then register a factory
in TTS_FACTORIES / CONVERSION_FACTORIES / LIVE_FACTORIES. Nothing else changes.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

from ..core.config import Settings
from ..core.errors import ApiError
from .base import (
    LiveConversionProvider,
    ProviderState,
    ProviderStatus,
    TTSProvider,
    VoiceConversionProvider,
)

# Factories for implemented integrations. Stage 3 registers "google" and
# "azure" here; Stages 4-6 register conversion and live engines.
TTS_FACTORIES: dict[str, Callable[[Settings], TTSProvider]] = {}
CONVERSION_FACTORIES: dict[str, Callable[[Settings], VoiceConversionProvider]] = {}
LIVE_FACTORIES: dict[str, Callable[[Settings], LiveConversionProvider]] = {}

# Human-readable names and the build stage that delivers each integration.
KNOWN_PROVIDERS: dict[str, tuple[str, int]] = {
    "google": ("Google Cloud Text-to-Speech", 3),
    "azure": ("Azure AI Speech", 3),
    "elevenlabs": ("ElevenLabs Voice Changer", 4),
}


def _not_implemented(name: str, feature: str) -> ProviderStatus:
    label, stage = KNOWN_PROVIDERS.get(name, (f"'{name}' ({feature})", 0))
    when = f" It is scheduled for Stage {stage}." if stage else " No integration exists for it."
    return ProviderStatus(name, ProviderState.NOT_IMPLEMENTED, f"{label} is not integrated yet.{when}")


@dataclass
class ProviderRegistry:
    tts: dict[str, TTSProvider] = field(default_factory=dict)
    conversion: VoiceConversionProvider | None = None
    live: LiveConversionProvider | None = None
    tts_statuses: list[ProviderStatus] = field(default_factory=list)
    conversion_status: ProviderStatus | None = None
    live_status: ProviderStatus | None = None

    # -- Lookups that raise user-facing errors ------------------------------------
    def tts_provider(self, name: str) -> TTSProvider:
        provider = self.tts.get(name)
        if provider is None or not provider.status().ready:
            status = next((s for s in self.tts_statuses if s.name == name), None)
            msg = status.message if status else f"Text-to-speech provider '{name}' is not enabled on the server."
            raise ApiError(503, "PROVIDER_NOT_CONFIGURED", msg, {"provider": name})
        return provider

    def conversion_provider(self) -> VoiceConversionProvider:
        if self.conversion is None or not self.conversion.status().ready:
            msg = (
                self.conversion_status.message
                if self.conversion_status
                else "No voice-conversion provider is configured on the server."
            )
            raise ApiError(503, "PROVIDER_NOT_CONFIGURED", msg)
        return self.conversion

    def live_provider(self) -> LiveConversionProvider:
        if self.live is None or not self.live.status().ready:
            msg = (
                self.live_status.message
                if self.live_status
                else "Live conversion is unavailable: no streaming voice-conversion engine is configured."
            )
            raise ApiError(503, "LIVE_CONVERSION_UNAVAILABLE", msg)
        return self.live

    # -- Health summary ---------------------------------------------------------------
    def capabilities(self) -> dict:
        tts_ready = any(p.status().ready for p in self.tts.values())
        tts_statuses = [p.status() for p in self.tts.values()] + [
            s for s in self.tts_statuses if s.name not in self.tts
        ]
        conv = self.conversion.status() if self.conversion else self.conversion_status
        live = self.live.status() if self.live else self.live_status
        return {
            "tts": {
                "available": tts_ready,
                "ready_providers": sorted(n for n, p in self.tts.items() if p.status().ready),
                "providers": [s.as_dict() for s in tts_statuses],
            },
            "voice_conversion": {
                "available": bool(conv and conv.ready),
                "provider": conv.as_dict() if conv else None,
            },
            "live_conversion": {
                "available": bool(live and live.ready),
                "streaming": bool(live and live.ready),
                "provider": live.as_dict() if live else None,
            },
        }


def build_registry(settings: Settings) -> ProviderRegistry:
    reg = ProviderRegistry()

    for name in settings.enabled_tts_providers:
        factory = TTS_FACTORIES.get(name)
        if factory is None:
            reg.tts_statuses.append(_not_implemented(name, "text-to-speech"))
            continue
        provider = factory(settings)
        reg.tts[name] = provider
        reg.tts_statuses.append(provider.status())

    vc = settings.voice_conversion_provider.strip().lower()
    if vc in ("", "none"):
        reg.conversion_status = ProviderStatus(
            "none",
            ProviderState.NOT_CONFIGURED,
            "Voice conversion is turned off (VOICE_CONVERSION_PROVIDER=none). "
            "It needs a speech-to-speech provider and paid API credentials.",
        )
    elif vc in CONVERSION_FACTORIES:
        reg.conversion = CONVERSION_FACTORIES[vc](settings)
        reg.conversion_status = reg.conversion.status()
    else:
        reg.conversion_status = _not_implemented(vc, "speech-to-speech conversion")

    live = settings.live_conversion_provider.strip().lower()
    if live in ("", "none"):
        reg.live_status = ProviderStatus(
            "none",
            ProviderState.UNSUPPORTED,
            "Live conversion is unavailable: no genuine streaming voice-conversion engine is configured. "
            "The app will not imitate it with simple pitch shifting.",
        )
    elif live in LIVE_FACTORIES:
        reg.live = LIVE_FACTORIES[live](settings)
        reg.live_status = reg.live.status()
    else:
        reg.live_status = _not_implemented(live, "live streaming conversion")

    return reg
