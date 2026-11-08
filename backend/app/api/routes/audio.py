from __future__ import annotations

import re
import unicodedata
from datetime import datetime, timezone
from pathlib import PurePath
from typing import Annotated, Literal
from urllib.parse import quote

from fastapi import APIRouter, File, Form, Query, Response, UploadFile
from fastapi.responses import FileResponse

from ...core.errors import ApiError
from ...core.signing import verify
from ...schemas import AudioItemOut, HistoryOut
from ...services.audio import validate_audio
from ...services.mp3 import wav_to_mp3
from ..deps import Ctx, CurrentUser

router = APIRouter(prefix="/api/audio", tags=["audio"])


def read_upload(file: UploadFile, max_bytes: int) -> bytes:
    data = file.file.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise ApiError(413, "FILE_TOO_LARGE", f"Audio files must be {max_bytes // (1024 * 1024)} MB or smaller.")
    return data


def clean_title(filename: str | None, fallback_prefix: str = "Recording") -> str:
    if filename:
        stem = PurePath(filename.replace("\\", "/")).stem
        stem = "".join(ch for ch in unicodedata.normalize("NFC", stem) if unicodedata.category(ch)[0] != "C")
        stem = re.sub(r"\s+", " ", stem).strip()[:80]
        if stem:
            return stem
    return f"{fallback_prefix} {datetime.now(timezone.utc):%Y-%m-%d %H:%M}"


@router.post("/upload", response_model=AudioItemOut, status_code=201, summary="Upload a recording")
def upload(
    ctx: Ctx,
    user: CurrentUser,
    file: Annotated[UploadFile, File(description="WAV, MP3, OGG, FLAC or M4A")],
    title: Annotated[str | None, Form(max_length=120)] = None,
) -> AudioItemOut:
    s = ctx.settings
    data = read_upload(file, s.max_upload_bytes)
    info = validate_audio(data, max_bytes=s.max_upload_bytes, max_seconds=s.max_audio_seconds)
    record = ctx.store_audio(
        owner_id=user.uid,
        kind="original",
        title=(title.strip() if title and title.strip() else clean_title(file.filename)),
        data=data,
        info=info,
        parameters={"source": "upload"},
    )
    return ctx.to_out(record)


@router.get("/history", response_model=HistoryOut, summary="The signed-in user's audio, newest first")
def history(
    ctx: Ctx,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    before: Annotated[str | None, Query(max_length=40, description="next_cursor from the previous page")] = None,
    kind: Annotated[Literal["tts", "original", "converted"] | None, Query()] = None,
) -> HistoryOut:
    records = ctx.repo.list_for_owner(user.uid, limit=limit, before=before, kind=kind)
    next_cursor = records[-1].created_at if len(records) == limit else None
    return HistoryOut(items=[ctx.to_out(r) for r in records], next_cursor=next_cursor)


@router.get("/{audio_id}", response_model=AudioItemOut, summary="One audio item (with a fresh download URL)")
def get_audio(audio_id: str, ctx: Ctx, user: CurrentUser) -> AudioItemOut:
    return ctx.to_out(ctx.owned_record(audio_id, user))


@router.get("/{audio_id}/file", summary="Stream or download audio via a signed URL", response_class=FileResponse)
def get_audio_file(
    audio_id: str,
    ctx: Ctx,
    exp: Annotated[int, Query()],
    sig: Annotated[str, Query(min_length=64, max_length=64)],
    download: Annotated[bool, Query()] = False,
    format: Annotated[Literal["mp3"] | None, Query(description="mp3: convert WAV audio to MP3")] = None,
) -> Response:
    if not verify(ctx.settings.secret_key, audio_id, exp, sig):
        raise ApiError(403, "LINK_EXPIRED", "This audio link is invalid or has expired. Refresh and try again.")
    record = ctx.repo.get(audio_id)
    if record is None:
        raise ApiError(404, "NOT_FOUND", "Audio not found.")
    path = ctx.storage.path_for(record.storage_key)
    if not path.exists():
        raise ApiError(404, "NOT_FOUND", "Audio file is missing.")
    if format == "mp3" and record.format != "mp3":
        safe = re.sub(r'[\\/:*?"<>|]+', "_", record.title).strip() or "audio"
        mp3 = wav_to_mp3(path.read_bytes())
        disposition = "attachment" if download else "inline"
        return Response(
            mp3,
            media_type="audio/mpeg",
            headers={
                "Content-Disposition": f"{disposition}; filename*=UTF-8''{quote(safe)}.mp3",
                "Cache-Control": "private, max-age=300",
            },
        )
    return FileResponse(
        path,
        media_type=record.mime_type,
        filename=f"{record.title}.{record.format}",
        content_disposition_type="attachment" if download else "inline",
        headers={"Cache-Control": "private, max-age=300"},
    )


@router.delete("/{audio_id}", status_code=204, summary="Delete an audio item")
def delete_audio(audio_id: str, ctx: Ctx, user: CurrentUser) -> Response:
    record = ctx.owned_record(audio_id, user)
    ctx.storage.delete(record.storage_key)
    ctx.repo.delete(record.id)
    return Response(status_code=204)
