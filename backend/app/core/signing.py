"""Short-lived signed download URLs (HMAC-SHA256).

Audio files are never public. The API hands out URLs like
/api/audio/<id>/file?exp=<unix>&sig=<hmac>, valid for a few minutes, so the
browser <audio> element, Android players and download managers can fetch the
file without carrying the user's auth header.
"""

from __future__ import annotations

import hashlib
import hmac
import time


def _mac(secret: str, audio_id: str, exp: int) -> str:
    msg = f"{audio_id}:{exp}".encode()
    return hmac.new(secret.encode(), msg, hashlib.sha256).hexdigest()


def sign(secret: str, audio_id: str, ttl_seconds: int, now: float | None = None) -> tuple[int, str]:
    exp = int((now if now is not None else time.time()) + ttl_seconds)
    return exp, _mac(secret, audio_id, exp)


def verify(secret: str, audio_id: str, exp: int, sig: str, now: float | None = None) -> bool:
    if exp < int(now if now is not None else time.time()):
        return False
    return hmac.compare_digest(_mac(secret, audio_id, exp), sig or "")


def signed_path(secret: str, audio_id: str, ttl_seconds: int) -> tuple[str, int]:
    exp, sig = sign(secret, audio_id, ttl_seconds)
    return f"/api/audio/{audio_id}/file?exp={exp}&sig={sig}", exp
