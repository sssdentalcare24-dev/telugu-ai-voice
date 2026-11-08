"""Audio blob storage. Local disk for development; a Cloud Storage backend
implements the same interface in Stage 7."""

from __future__ import annotations

import hashlib
import os
from abc import ABC, abstractmethod
from pathlib import Path


def storage_key(owner_id: str, audio_id: str, fmt: str) -> str:
    owner_dir = hashlib.sha256(owner_id.encode()).hexdigest()[:24]
    return f"{owner_dir}/{audio_id}.{fmt}"


class AudioStorage(ABC):
    backend_name: str

    @abstractmethod
    def save(self, key: str, data: bytes) -> None: ...

    @abstractmethod
    def path_for(self, key: str) -> Path: ...

    @abstractmethod
    def read(self, key: str) -> bytes: ...

    @abstractmethod
    def delete(self, key: str) -> None: ...


class LocalAudioStorage(AudioStorage):
    backend_name = "local"

    def __init__(self, base_dir: Path):
        self.base = Path(base_dir).resolve()
        self.base.mkdir(parents=True, exist_ok=True)

    def path_for(self, key: str) -> Path:
        path = (self.base / key).resolve()
        if self.base not in path.parents:
            raise ValueError("Invalid storage key")
        return path

    def save(self, key: str, data: bytes) -> None:
        path = self.path_for(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".part")
        with open(tmp, "wb") as fh:
            fh.write(data)
        os.replace(tmp, path)

    def read(self, key: str) -> bytes:
        return self.path_for(key).read_bytes()

    def delete(self, key: str) -> None:
        try:
            self.path_for(key).unlink()
        except FileNotFoundError:
            pass
