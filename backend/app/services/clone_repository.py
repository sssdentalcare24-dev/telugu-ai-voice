"""Voice profiles, consent records and generation history (SQLite).

Stored per profile: owner (user id), profile id, provider + provider voice id,
category, recording language, transcript, consent record, sample and preview
audio ids, timestamps. Each generation links a profile to an audio item.
"""

from __future__ import annotations

import json
import sqlite3
from contextlib import closing
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Literal

ProfileStatus = Literal["draft", "ready", "failed"]

_SCHEMA = """
CREATE TABLE IF NOT EXISTS voice_profiles (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    recording_language TEXT NOT NULL,
    provider TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    provider_voice_id TEXT,
    sample_audio_id TEXT,
    transcript TEXT,
    preview_audio_id TEXT,
    consent TEXT NOT NULL DEFAULT '{}',
    error TEXT
);
CREATE INDEX IF NOT EXISTS idx_profiles_owner ON voice_profiles (owner_id, created_at DESC);
CREATE TABLE IF NOT EXISTS clone_generations (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL,
    profile_id TEXT NOT NULL,
    profile_name TEXT NOT NULL,
    audio_id TEXT NOT NULL,
    text TEXT NOT NULL,
    language TEXT NOT NULL,
    provider TEXT NOT NULL,
    speed REAL NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_generations_owner ON clone_generations (owner_id, created_at DESC);
"""

_PROFILE_COLS = (
    "id, owner_id, name, category, recording_language, provider, status, created_at, updated_at, "
    "provider_voice_id, sample_audio_id, transcript, preview_audio_id, consent, error"
)
_GEN_COLS = "id, owner_id, profile_id, profile_name, audio_id, text, language, provider, speed, created_at"


@dataclass
class VoiceProfileRecord:
    id: str
    owner_id: str
    name: str
    category: str  # "female" | "male" - a label chosen by the user
    recording_language: str
    provider: str
    status: ProfileStatus
    created_at: str
    updated_at: str
    provider_voice_id: str | None = None
    sample_audio_id: str | None = None
    transcript: str | None = None
    preview_audio_id: str | None = None
    consent: dict[str, Any] = field(default_factory=dict)
    error: str | None = None


@dataclass
class GenerationRecord:
    id: str
    owner_id: str
    profile_id: str
    profile_name: str
    audio_id: str
    text: str
    language: str
    provider: str
    speed: float
    created_at: str


class SqliteCloneRepository:
    backend_name = "sqlite"

    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with closing(self._connect()) as conn:
            conn.executescript(_SCHEMA)
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn

    # -- profiles ---------------------------------------------------------------------
    @staticmethod
    def _profile(row: sqlite3.Row) -> VoiceProfileRecord:
        data = dict(row)
        data["consent"] = json.loads(data.get("consent") or "{}")
        return VoiceProfileRecord(**data)

    def save_profile(self, record: VoiceProfileRecord) -> None:
        data = asdict(record)
        data["consent"] = json.dumps(record.consent, ensure_ascii=False)
        cols = [c.strip() for c in _PROFILE_COLS.split(",")]
        placeholders = ", ".join(f":{c}" for c in cols)
        with closing(self._connect()) as conn:
            conn.execute(f"INSERT OR REPLACE INTO voice_profiles ({_PROFILE_COLS}) VALUES ({placeholders})", data)
            conn.commit()

    def get_profile(self, profile_id: str) -> VoiceProfileRecord | None:
        with closing(self._connect()) as conn:
            row = conn.execute(f"SELECT {_PROFILE_COLS} FROM voice_profiles WHERE id = ?", (profile_id,)).fetchone()
        return self._profile(row) if row else None

    def list_profiles(self, owner_id: str) -> list[VoiceProfileRecord]:
        with closing(self._connect()) as conn:
            rows = conn.execute(
                f"SELECT {_PROFILE_COLS} FROM voice_profiles WHERE owner_id = ? ORDER BY created_at DESC, id DESC",
                (owner_id,),
            ).fetchall()
        return [self._profile(r) for r in rows]

    def count_profiles(self, owner_id: str) -> int:
        with closing(self._connect()) as conn:
            return conn.execute("SELECT COUNT(*) FROM voice_profiles WHERE owner_id = ?", (owner_id,)).fetchone()[0]

    def delete_profile(self, profile_id: str) -> None:
        with closing(self._connect()) as conn:
            conn.execute("DELETE FROM voice_profiles WHERE id = ?", (profile_id,))
            conn.commit()

    # -- generations ----------------------------------------------------------------
    def add_generation(self, record: GenerationRecord) -> None:
        cols = [c.strip() for c in _GEN_COLS.split(",")]
        placeholders = ", ".join(f":{c}" for c in cols)
        with closing(self._connect()) as conn:
            conn.execute(f"INSERT INTO clone_generations ({_GEN_COLS}) VALUES ({placeholders})", asdict(record))
            conn.commit()

    def get_generation(self, generation_id: str) -> GenerationRecord | None:
        with closing(self._connect()) as conn:
            row = conn.execute(f"SELECT {_GEN_COLS} FROM clone_generations WHERE id = ?", (generation_id,)).fetchone()
        return GenerationRecord(**dict(row)) if row else None

    def list_generations(
        self, owner_id: str, *, limit: int, before: str | None = None, profile_id: str | None = None
    ) -> list[GenerationRecord]:
        sql = f"SELECT {_GEN_COLS} FROM clone_generations WHERE owner_id = ?"
        args: list[Any] = [owner_id]
        if before:
            sql += " AND created_at < ?"
            args.append(before)
        if profile_id:
            sql += " AND profile_id = ?"
            args.append(profile_id)
        sql += " ORDER BY created_at DESC, id DESC LIMIT ?"
        args.append(limit)
        with closing(self._connect()) as conn:
            rows = conn.execute(sql, args).fetchall()
        return [GenerationRecord(**dict(r)) for r in rows]

    def delete_generation(self, generation_id: str) -> None:
        with closing(self._connect()) as conn:
            conn.execute("DELETE FROM clone_generations WHERE id = ?", (generation_id,))
            conn.commit()
