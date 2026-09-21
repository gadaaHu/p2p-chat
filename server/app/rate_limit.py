import logging
import time

from fastapi import HTTPException, status
from sqlalchemy import select

from .config import settings
from .models import RateBucket

log = logging.getLogger("rate_limit")


def _window() -> int:
    return int(time.time()) // 60 * 60


def _limit_for(kind: str) -> int:
    if kind == "chat":
        return settings.rate_limit_chat_per_min
    if kind == "ice":
        return settings.rate_limit_ice_per_min
    return settings.rate_limit_sdp_per_min


def check_and_increment(db, device_id: str, kind: str) -> None:
    limit = _limit_for(kind)
    win = _window()

    row = db.execute(
        select(RateBucket).where(
            RateBucket.device_id == device_id,
            RateBucket.kind == kind,
            RateBucket.window_start == win,
        )
    ).scalar_one_or_none()

    if row is None:
        row = RateBucket(
            device_id=device_id, kind=kind, window_start=win, count=1
        )
        db.add(row)
        db.flush()
        return

    if row.count >= limit:
        log.warning(
            "rate_limit_exceeded device=%s kind=%s count=%d",
            device_id, kind, row.count,
        )
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            f"rate limit exceeded for {kind}",
        )
    row.count += 1
    db.flush()