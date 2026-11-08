"""Shared dependencies: the application context and the signed-in user."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Annotated

from fastapi import Depends, Header, Request

from ..core.auth import Authenticator, User
from ..core.config import Settings
from ..core.errors import ApiError
from ..core.signing import signed_path
from ..providers.catalog import VoiceCatalog
from ..providers.registry import ProviderRegistry
from ..schemas import AudioItemOut
from ..services.audio import AudioInfo
from ..services.repository import AudioKind, AudioRecord, AudioRepository
from ..services.storage import AudioStorage, storage_key


@dataclass
class AppContext:
    settings: Settings
    registry: ProviderRegistry
    catalog: VoiceCatalog
    storage: AudioStorage
    repo: AudioRepository
    authenticator: Authenticator

    # -- helpers shared by routes -------------------------------------------------
    def store_audio(
        self,
        *,
        owner_id: str,
        kind: AudioKind,
        title: str,
        data: bytes,
        info: AudioInfo,
        source_audio_id: str | None = None,
        parameters: dict | None = None,
    ) -> AudioRecord:
        audio_id = uuid.uuid4().hex
        key = storage_key(owner_id, audio_id, info.format)
        self.storage.save(key, data)
        record = AudioRecord(
            id=audio_id,
            owner_id=owner_id,
            kind=kind,
            title=title,
            format=info.format,
            mime_type=info.mime_type,
            size_bytes=info.size_bytes,
            duration_seconds=info.duration_seconds,
            created_at=datetime.now(timezone.utc).isoformat(timespec="microseconds"),
            storage_key=key,
            source_audio_id=source_audio_id,
            parameters=parameters or {},
        )
        try:
            self.repo.add(record)
        except Exception:
            self.storage.delete(key)
            raise
        return record

    def to_out(self, record: AudioRecord) -> AudioItemOut:
        url, exp = signed_path(self.settings.secret_key, record.id, self.settings.download_url_ttl_seconds)
        return AudioItemOut(
            id=record.id,
            kind=record.kind,
            title=record.title,
            format=record.format,
            mime_type=record.mime_type,
            size_bytes=record.size_bytes,
            duration_seconds=record.duration_seconds,
            created_at=record.created_at,
            source_audio_id=record.source_audio_id,
            parameters=record.parameters,
            download_url=url,
            download_url_expires_at=exp,
        )

    def owned_record(self, audio_id: str, user: User) -> AudioRecord:
        record = self.repo.get(audio_id)
        # 404 (not 403) for other users' items so ids cannot be probed.
        if record is None or record.owner_id != user.uid:
            raise ApiError(404, "NOT_FOUND", "Audio not found.")
        return record


def get_ctx(request: Request) -> AppContext:
    return request.app.state.ctx


Ctx = Annotated[AppContext, Depends(get_ctx)]


def current_user(
    ctx: Ctx,
    authorization: Annotated[str | None, Header()] = None,
    x_dev_user: Annotated[str | None, Header()] = None,
) -> User:
    return ctx.authenticator.authenticate(authorization, x_dev_user)


CurrentUser = Annotated[User, Depends(current_user)]
