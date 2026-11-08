"""Audio history metadata. SQLite for development; Firestore implements the
same interface in Stage 7."""

from __future__ import annotations

import json
import sqlite3
from abc import ABC, abstractmethod
from contextlib import closing
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Literal

AudioKind = Literal["tts", "original", "converted"]


@dataclass
class AudioRecord:
    id: str
    owner_id: str
    kind: AudioKind
    title: str
    format: str
    mime_type: str
    size_bytes: int
    duration_seconds: float
    created_at: str  # ISO-8601 UTC
    storage_key: str
    source_audio_id: str | None = None
    parameters: dict[str, Any] = field(default_factory=dict)


class AudioRepository(ABC):
    backend_name: str

    @abstractmethod
    def add(self, record: AudioRecord) -> None: ...

    @abstractmethod
    def get(self, audio_id: str) -> AudioRecord | None: ...

    @abstractmethod
    def list_for_owner(
        self, owner_id: str, *, limit: int, before: str | None = None, kind: str | None = None
    ) -> list[AudioRecord]: ...

    @abstractmethod
    def delete(self, audio_id: str) -> None: ...


_SCHEMA = """
CREATE TABLE IF NOT EXISTS audio_items (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    format TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    size_bytes INTEGER NOT NULL,
    duration_seconds REAL NOT NULL,
    created_at TEXT NOT NULL,
    storage_key TEXT NOT NULL,
    source_audio_id TEXT,
    parameters TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS idx_audio_owner_created ON audio_items (owner_id, created_at DESC);
"""

_COLUMNS = (
    "id, owner_id, kind, title, format, mime_type, size_bytes, duration_seconds, "
    "created_at, storage_key, source_audio_id, parameters"
)


class SqliteAudioRepository(AudioRepository):
    backend_name = "sqlite"

    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with closing(self._connect()) as conn:
            conn.executescript(_SCHEMA)
            conn.execute("PRAGMA journal_mode=WAL")
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn

    @staticmethod
    def _row(row: sqlite3.Row) -> AudioRecord:
        data = dict(row)
        data["parameters"] = json.loads(data.get("parameters") or "{}")
        return AudioRecord(**data)

    def add(self, record: AudioRecord) -> None:
        data = asdict(record)
        data["parameters"] = json.dumps(record.parameters, ensure_ascii=False)
        placeholders = ", ".join(f":{c.strip()}" for c in _COLUMNS.split(","))
        with closing(self._connect()) as conn:
            conn.execute(f"INSERT INTO audio_items ({_COLUMNS}) VALUES ({placeholders})", data)
            conn.commit()

    def get(self, audio_id: str) -> AudioRecord | None:
        with closing(self._connect()) as conn:
            row = conn.execute(f"SELECT {_COLUMNS} FROM audio_items WHERE id = ?", (audio_id,)).fetchone()
        return self._row(row) if row else None

    def list_for_owner(
        self, owner_id: str, *, limit: int, before: str | None = None, kind: str | None = None
    ) -> list[AudioRecord]:
        sql = f"SELECT {_COLUMNS} FROM audio_items WHERE owner_id = ?"
        args: list[Any] = [owner_id]
        if before:
            sql += " AND created_at < ?"
            args.append(before)
        if kind:
            sql += " AND kind = ?"
            args.append(kind)
        sql += " ORDER BY created_at DESC, id DESC LIMIT ?"
        args.append(limit)
        with closing(self._connect()) as conn:
            rows = conn.execute(sql, args).fetchall()
        return [self._row(r) for r in rows]

    def delete(self, audio_id: str) -> None:
        with closing(self._connect()) as conn:
            conn.execute("DELETE FROM audio_items WHERE id = ?", (audio_id,))
            conn.commit()
