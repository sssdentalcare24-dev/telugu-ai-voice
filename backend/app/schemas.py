"""Request/response models (validated by Pydantic)."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field

Direction = Literal["male_to_female", "female_to_male"]


class TTSRequest(BaseModel):
    text: str = Field(min_length=1, max_length=60_000, description="Telugu text (Unicode).")
    voice_id: str = Field(min_length=3, max_length=64, description="An id from GET /api/voices.")
    speed: float = Field(default=1.0, ge=0.25, le=2.0, description="Speaking rate multiplier.")
    pitch: float = Field(default=0.0, ge=-20.0, le=20.0, description="Pitch in semitones (voice must support it).")
    style: str | None = Field(default=None, max_length=40)
    title: str | None = Field(default=None, max_length=120)


class AudioItemOut(BaseModel):
    id: str
    kind: Literal["tts", "original", "converted"]
    title: str
    format: str
    mime_type: str
    size_bytes: int
    duration_seconds: float
    created_at: str
    source_audio_id: str | None = None
    parameters: dict[str, Any] = Field(default_factory=dict)
    download_url: str = Field(description="Relative, signed, short-lived URL. Prefix with the API base URL.")
    download_url_expires_at: int


class HistoryOut(BaseModel):
    items: list[AudioItemOut]
    next_cursor: str | None = None


class ConvertOut(BaseModel):
    original: AudioItemOut
    converted: AudioItemOut


class LiveSessionRequest(BaseModel):
    direction: Direction
    consent: bool = Field(description="User confirms it is their own voice or they have permission.")


class LiveSessionOut(BaseModel):
    session_id: str
    websocket_url: str
    expires_at: int
    sample_rate: int
    encoding: str


class VoiceOut(BaseModel):
    id: str
    provider: str
    language_code: str
    gender: Literal["female", "male"]
    display_name: str
    display_name_te: str | None = None
    quality: str
    accent: str
    supports_pitch: bool
    supports_speed: bool
    styles: list[str]
    notes: str | None = None
    available: bool


class VoicesOut(BaseModel):
    voices: list[VoiceOut]
