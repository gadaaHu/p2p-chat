import asyncio
import logging

from sqlalchemy import delete

from .config import settings
from .database import SessionLocal
from .models import OneTimePreKey, Signal, SignedPreKey
from .security import log_event, now

log = logging.getLogger("cleanup")


async def cleanup_loop() -> None:
    while True:
        try:
            with SessionLocal() as db:
                expired = db.execute(
                    delete(Signal).where(Signal.expires_at <= now())
                ).rowcount

                stale_opks = db.execute(
                    delete(OneTimePreKey).where(
                        OneTimePreKey.consumed_at.is_not(None),
                        OneTimePreKey.consumed_at
                        < now() - settings.opk_consumed_retention_seconds,
                    )
                ).rowcount

                expired_spks = db.execute(
                    delete(SignedPreKey).where(SignedPreKey.expires_at <= now())
                ).rowcount

                db.commit()

                if expired or stale_opks or expired_spks:
                    log_event(
                        log, "cleanup",
                        expired_signals=expired,
                        stale_opks=stale_opks,
                        expired_spks=expired_spks,
                    )
        except Exception:
            log.exception("cleanup failed")
        await asyncio.sleep(settings.cleanup_interval_seconds)