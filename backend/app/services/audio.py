"""Audio validation: identify the real format from the file's bytes (never the
filename or the client's Content-Type), parse it, and enforce duration limits."""

from __future__ import annotations

import io
from dataclasses import dataclass

import mutagen

from ..core.errors import ApiError

MIME_TYPES = {
    "wav": "audio/wav",
    "mp3": "audio/mpeg",
    "ogg": "audio/ogg",
    "flac": "audio/flac",
    "m4a": "audio/mp4",
}


@dataclass(frozen=True)
class AudioInfo:
    format: str
    mime_type: str
    duration_seconds: float
    size_bytes: int


def sniff_format(data: bytes) -> str | None:
    """Return the audio container from magic bytes, or None if unrecognised."""
    if len(data) < 12:
        return None
    if data[:4] == b"RIFF" and data[8:12] == b"WAVE":
        return "wav"
    if data[:4] == b"OggS":
        return "ogg"
    if data[:4] == b"fLaC":
        return "flac"
    if data[4:8] == b"ftyp" and data[8:12] in (b"M4A ", b"M4B ", b"mp42", b"isom", b"iso2", b"mp41", b"dash"):
        return "m4a"
    if data[:3] == b"ID3":
        return "mp3"
    if data[0] == 0xFF and (data[1] & 0xE0) == 0xE0 and (data[1] & 0x06) != 0:
        return "mp3"  # MPEG audio frame sync, layer != reserved
    return None


def probe_duration(data: bytes) -> float | None:
    try:
        parsed = mutagen.File(io.BytesIO(data))
    except Exception:
        return None
    if parsed is None or getattr(parsed, "info", None) is None:
        return None
    length = getattr(parsed.info, "length", None)
    return float(length) if length else None


def validate_audio(data: bytes, *, max_bytes: int, max_seconds: int) -> AudioInfo:
    if not data:
        raise ApiError(400, "EMPTY_FILE", "The audio file is empty.")
    if len(data) > max_bytes:
        raise ApiError(413, "FILE_TOO_LARGE", f"Audio files must be {max_bytes // (1024 * 1024)} MB or smaller.")
    fmt = sniff_format(data)
    if fmt is None:
        raise ApiError(
            415,
            "UNSUPPORTED_FORMAT",
            "Unsupported or unrecognised audio file. Use WAV, MP3, OGG, FLAC or M4A.",
        )
    duration = probe_duration(data)
    if duration is None:
        raise ApiError(422, "CORRUPT_AUDIO", "The audio file could not be read. It may be damaged.")
    if duration > max_seconds:
        raise ApiError(
            422,
            "AUDIO_TOO_LONG",
            f"Audio must be {max_seconds} seconds or shorter (this file is {duration:.0f} s).",
        )
    return AudioInfo(format=fmt, mime_type=MIME_TYPES[fmt], duration_seconds=round(duration, 2), size_bytes=len(data))
