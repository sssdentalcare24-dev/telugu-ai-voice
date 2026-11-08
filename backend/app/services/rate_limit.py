"""Simple per-user sliding-window rate limiter (in memory, per server process).

Enough for one server instance; a multi-instance deployment would back this
with Redis or the API gateway's limiter instead.
"""

from __future__ import annotations

import math
import threading
import time
from collections import defaultdict, deque
from typing import Callable

from ..core.errors import ApiError


class RateLimiter:
    def __init__(self, clock: Callable[[], float] = time.monotonic):
        self._clock = clock
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def check(self, key: str, limit: int, window_seconds: float = 3600) -> None:
        """Records one event for [key], or raises 429 if [limit] is reached."""
        now = self._clock()
        with self._lock:
            events = self._events[key]
            while events and now - events[0] >= window_seconds:
                events.popleft()
            if len(events) >= limit:
                wait = max(1, math.ceil(window_seconds - (now - events[0])))
                minutes = math.ceil(wait / 60)
                raise ApiError(
                    429,
                    "RATE_LIMITED",
                    f"Too many requests. Please try again in about {minutes} minute{'s' if minutes != 1 else ''}.",
                    {"retry_after_seconds": wait},
                )
            events.append(now)
