import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.auth.router import build_router
from app.config import Settings, get_settings
from app.db import create_pool, run_migrations
from app.telegram.client import HttpTelegramClient, NullTelegramClient, TelegramClient
from app.telegram.webhook import build_webhook_router

log = logging.getLogger("app")


def create_app(settings: Settings | None = None, telegram: TelegramClient | None = None) -> FastAPI:
    settings = settings or get_settings()
    if telegram is None:
        telegram = HttpTelegramClient(settings.telegram_bot_token) if settings.telegram_bot_token else NullTelegramClient()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.pool = await create_pool(settings.database_url)
        await run_migrations(app.state.pool)
        try:
            yield
        finally:
            await app.state.pool.close()

    app = FastAPI(
        title="Al-Hisob API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None,
        openapi_url=None if settings.is_production else "/openapi.json",
    )
    app.state.settings = settings
    app.state.telegram = telegram

    @app.get("/health")
    async def health() -> dict[str, object]:
        db_ok = False
        try:
            db_ok = await app.state.pool.fetchval("select 1") == 1
        except Exception:  # noqa: BLE001
            log.exception("health check: database unavailable")
        return {"status": "ok" if db_ok else "degraded", "db": db_ok}

    app.include_router(build_router(settings))
    app.include_router(build_webhook_router(settings))
    return app
