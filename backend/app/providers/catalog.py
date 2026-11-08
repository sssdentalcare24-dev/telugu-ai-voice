"""Voice catalog loaded from config/voices.yaml (no voice is hard-coded)."""

from __future__ import annotations

from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, Field


class Voice(BaseModel):
    id: str = Field(pattern=r"^[a-z0-9][a-z0-9\-]{2,63}$")
    provider: str
    provider_voice: str
    language_code: str = "te-IN"
    gender: Literal["female", "male"]
    display_name: str
    display_name_te: str | None = None
    quality: Literal["standard", "neural", "hd"] = "standard"
    accent: str = "standard"
    supports_pitch: bool = False
    supports_speed: bool = True
    styles: list[str] = Field(default_factory=list)
    notes: str | None = None


class VoiceCatalog(BaseModel):
    voices: list[Voice]

    def get(self, voice_id: str) -> Voice | None:
        return next((v for v in self.voices if v.id == voice_id), None)


def load_catalog(path: Path) -> VoiceCatalog:
    with open(path, encoding="utf-8") as fh:
        raw = yaml.safe_load(fh) or {}
    catalog = VoiceCatalog.model_validate(raw)
    ids = [v.id for v in catalog.voices]
    if len(ids) != len(set(ids)):
        raise ValueError(f"Duplicate voice ids in {path}")
    return catalog
