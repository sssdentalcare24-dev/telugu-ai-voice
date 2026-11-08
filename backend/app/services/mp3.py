"""WAV -> MP3 for downloads (LAME via the lameenc wheel; no ffmpeg needed)."""

from __future__ import annotations

import io
import wave

from ..core.errors import ApiError


def wav_to_mp3(data: bytes, bitrate_kbps: int = 128) -> bytes:
    try:
        import lameenc
    except ImportError as exc:  # pragma: no cover - lameenc is in requirements.txt
        raise ApiError(501, "MP3_UNAVAILABLE", "MP3 download is not installed on this server.") from exc
    try:
        with wave.open(io.BytesIO(data)) as w:
            channels, width, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
            frames = w.readframes(w.getnframes())
    except (wave.Error, EOFError) as exc:
        raise ApiError(415, "MP3_UNSUPPORTED", "Only WAV audio can be converted to MP3.") from exc
    if width != 2 or channels not in (1, 2):
        raise ApiError(415, "MP3_UNSUPPORTED", "Only 16-bit mono or stereo WAV can be converted to MP3.")
    encoder = lameenc.Encoder()
    encoder.set_bit_rate(bitrate_kbps)
    encoder.set_in_sample_rate(rate)
    encoder.set_channels(channels)
    encoder.set_quality(2)
    return bytes(encoder.encode(frames) + encoder.flush())
