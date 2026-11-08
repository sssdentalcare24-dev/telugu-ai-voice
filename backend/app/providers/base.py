"""Provider interfaces.

Every AI vendor sits behind one of these small interfaces, so Google, Azure,
ElevenLabs or a self-hosted model can be swapped by configuration without
touching the API routes or the app.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Literal

Direction = Literal["male_to_female", "female_to_male"]


class ProviderState(str, Enum):
    READY = "ready"  # implemented and credentials present
    NOT_CONFIGURED = "not_configured"  # implemented, credentials missing
    NOT_IMPLEMENTED = "not_implemented"  # integration arrives in a later stage
    UNSUPPORTED = "unsupported"  # vendor cannot do this (e.g. no streaming)


@dataclass(frozen=True)
class ProviderStatus:
    name: str
    state: ProviderState
    message: str
    paid: bool = True

    @property
    def ready(self) -> bool:
        return self.state is ProviderState.READY

    def as_dict(self) -> dict[str, Any]:
        return {"name": self.name, "state": self.state.value, "message": self.message, "paid": self.paid}


@dataclass(frozen=True)
class AudioPayload:
    data: bytes
    format: str  # "mp3", "wav", ...
    mime_type: str


@dataclass(frozen=True)
class SynthesisRequest:
    text: str
    language_code: str
    provider_voice: str
    speed: float = 1.0
    pitch: float = 0.0
    style: str | None = None
    audio_format: str = "mp3"


@dataclass(frozen=True)
class ConversionRequest:
    audio: AudioPayload
    direction: Direction
    target_voice: str | None = None
    options: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class LiveSessionInfo:
    session_id: str
    websocket_url: str
    expires_at: int
    sample_rate: int
    encoding: str


class TTSProvider(ABC):
    name: str

    @abstractmethod
    def status(self) -> ProviderStatus: ...

    @abstractmethod
    def synthesize(self, request: SynthesisRequest) -> AudioPayload: ...


class VoiceConversionProvider(ABC):
    name: str

    @abstractmethod
    def status(self) -> ProviderStatus: ...

    @abstractmethod
    def convert(self, request: ConversionRequest) -> AudioPayload: ...


class LiveConversionProvider(ABC):
    """A genuine streaming speech-to-speech engine. Never a pitch shifter."""

    name: str

    @abstractmethod
    def status(self) -> ProviderStatus: ...

    @abstractmethod
    def create_session(self, user_id: str, direction: Direction) -> LiveSessionInfo: ...


class ProviderError(Exception):
    """Raised by providers when the vendor call fails. Message must be safe to show users."""
