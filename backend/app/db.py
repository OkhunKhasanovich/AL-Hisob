import logging
from pathlib import Path

import asyncpg

log = logging.getLogger("app.db")

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "migrations"


async def create_pool(dsn: str) -> asyncpg.Pool:
    return await asyncpg.create_pool(dsn, min_size=1, max_size=10)


async def run_migrations(pool: asyncpg.Pool, directory: Path = MIGRATIONS_DIR) -> list[str]:
    """Применяет по порядку ещё не применённые `NNNN_*.sql`; возвращает их имена.

    Каждая миграция выполняется в транзакции вместе с записью в `schema_migrations`,
    поэтому после сбоя остаётся целая схема. Параллельный запуск (несколько
    контейнеров) защищён advisory-блокировкой.
    """
    applied_now: list[str] = []
    async with pool.acquire() as conn:
        await conn.execute("select pg_advisory_lock(727001)")
        try:
            await conn.execute(
                """
                create table if not exists schema_migrations (
                    name       text primary key,
                    applied_at timestamptz not null default now()
                )
                """
            )
            done = {r["name"] for r in await conn.fetch("select name from schema_migrations")}
            for path in sorted(directory.glob("[0-9][0-9][0-9][0-9]_*.sql")):
                if path.name in done:
                    continue
                sql = path.read_text(encoding="utf-8")
                async with conn.transaction():
                    await conn.execute(sql)
                    await conn.execute("insert into schema_migrations (name) values ($1)", path.name)
                applied_now.append(path.name)
                log.info("applied migration %s", path.name)
        finally:
            await conn.execute("select pg_advisory_unlock(727001)")
    return applied_now
