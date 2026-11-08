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


# --- Personal voice cloning ------------------------------------------------------------

CloneCategory = Literal["female", "male"]


class ConsentIn(BaseModel):
    confirmed: bool = Field(description="Must be true: the user owns the voice or has explicit permission.")
    relationship: Literal["self", "permission"] = Field(description="My own voice, or a speaker who gave permission.")
    speaker_name: str | None = Field(default=None, max_length=80, description="Who is speaking in the sample.")
    statement: str = Field(min_length=10, max_length=600, description="The consent text the user agreed to.")


class CreateProfileIn(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    category: CloneCategory = Field(description="Label only; the voice always comes from the recorded speaker.")
    recording_language: str = Field(min_length=2, max_length=5)
    provider: str | None = Field(default=None, max_length=20, description="Defaults to the server's default provider.")
    consent: ConsentIn


class ProfileOut(BaseModel):
    id: str
    name: str
    category: CloneCategory
    recording_language: str
    provider: str
    provider_voice_id: str | None = None
    status: Literal["draft", "ready", "failed"]
    created_at: str
    updated_at: str
    transcript: str | None = None
    consent: dict[str, Any] = Field(default_factory=dict)
    sample: AudioItemOut | None = None
    preview: AudioItemOut | None = None
    error: str | None = None
    warning: str | None = None


class ProfilesOut(BaseModel):
    profiles: list[ProfileOut]


class CloneTtsIn(BaseModel):
    profile_id: str = Field(min_length=8, max_length=64)
    text: str = Field(min_length=1, max_length=20_000)
    language: str = Field(min_length=2, max_length=5)
    speed: float = Field(default=1.0, ge=0.5, le=2.0)
    title: str | None = Field(default=None, max_length=120)


class GenerationOut(BaseModel):
    id: str
    profile_id: str
    profile_name: str
    text: str
    language: str
    provider: str
    speed: float
    created_at: str
    audio: AudioItemOut | None = None


class GenerationsOut(BaseModel):
    items: list[GenerationOut]
    next_cursor: str | None = None
