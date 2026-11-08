"""Application settings, loaded from environment variables (or a .env file).

Secrets (API keys, service-account paths) live ONLY here, on the server.
The Flutter app never sees them.
"""

from __future__ import annotations

from functools import cached_property
from pathlib import Path
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]

ALLOWED_AUDIO_FORMATS = ("wav", "mp3", "ogg", "flac", "m4a")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # --- General -----------------------------------------------------------
    app_name: str = "Telugu AI Voice API"
    app_version: str = "0.2.0"
    app_env: Literal["development", "production", "test"] = "development"

    # Used to sign short-lived download URLs. MUST be overridden in production.
    secret_key: str = Field(default="dev-only-change-me", min_length=16)
    download_url_ttl_seconds: int = Field(default=900, ge=60, le=86_400)

    # Comma-separated list of allowed browser origins for the web app.
    cors_origins: str = "http://localhost:5000,http://127.0.0.1:5000"

    # --- Authentication ------------------------------------------------------
    # "firebase": verify Firebase ID tokens (production).
    # "dev": trust the X-Dev-User header. Refused when app_env=production.
    auth_mode: Literal["firebase", "dev"] = "firebase"
    firebase_project_id: str | None = None
    # Path to a service-account JSON. If unset, Application Default Credentials are used.
    firebase_credentials_file: str | None = None

    # --- Storage & metadata --------------------------------------------------
    storage_backend: Literal["local"] = "local"  # "gcs" arrives in Stage 7
    local_storage_dir: Path = BACKEND_DIR / "data" / "audio"
    metadata_backend: Literal["sqlite"] = "sqlite"  # "firestore" arrives in Stage 7
    sqlite_path: Path = BACKEND_DIR / "data" / "telugu_voice.db"

    # --- Limits --------------------------------------------------------------
    max_upload_mb: int = Field(default=20, ge=1, le=200)
    max_audio_seconds: int = Field(default=300, ge=5, le=3600)
    max_tts_chars: int = Field(default=5000, ge=100, le=50_000)

    # --- AI providers ---------------------------------------------------------
    voices_config_file: Path = BACKEND_DIR / "config" / "voices.yaml"
    # Comma-separated TTS providers to enable, e.g. "google,azure".
    tts_providers: str = "google,azure"
    # Recorded speech-to-speech conversion provider ("none" disables it).
    voice_conversion_provider: str = "none"
    # Real-time streaming conversion provider ("none" disables it).
    live_conversion_provider: str = "none"

    # Google Cloud Text-to-Speech (Stage 3)
    google_tts_credentials_file: str | None = None
    google_tts_api_key: str | None = None

    # Azure AI Speech (Stage 3)
    azure_speech_key: str | None = None
    azure_speech_region: str | None = None

    # Speech-to-speech conversion (Stage 4/5)
    elevenlabs_api_key: str | None = None
    vc_target_female_voice_id: str | None = None
    vc_target_male_voice_id: str | None = None

    @model_validator(mode="after")
    def _guard_production(self) -> "Settings":
        if self.app_env == "production":
            if self.auth_mode == "dev":
                raise ValueError("AUTH_MODE=dev is not allowed when APP_ENV=production.")
            if self.secret_key == "dev-only-change-me" or len(self.secret_key) < 32:
                raise ValueError("Set a strong SECRET_KEY (32+ characters) in production.")
        return self

    @cached_property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @cached_property
    def enabled_tts_providers(self) -> list[str]:
        return [p.strip().lower() for p in self.tts_providers.split(",") if p.strip()]

    @property
    def max_upload_bytes(self) -> int:
        return self.max_upload_mb * 1024 * 1024
