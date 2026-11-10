from pathlib import Path

import pytest

from app.db import run_migrations
from app.ratelimit import SlidingWindowLimiter

from .conftest import TEST_DSN


async def test_health_ok(client):
    r = await client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok", "db": True}


async def test_docs_exist_in_development(client):
    assert (await client.get("/docs")).status_code == 200


async def test_docs_disabled_in_production(telegram):
    from app.config import Settings
    from app.main import create_app

    s = Settings(
        env="production", database_url=TEST_DSN, jwt_secret="a" * 48, telegram_bot_token="1:x",
        telegram_bot_username="Bot", telegram_webhook_secret="b" * 20,
    )
    app = create_app(s, telegram=telegram)
    async with app.router.lifespan_context(app):
        import httpx

        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
            assert (await c.get("/docs")).status_code == 404
            assert (await c.get("/openapi.json")).status_code == 404
            assert (await c.get("/health")).status_code == 200


class TestMigrations:
    async def test_schema_created(self, pool):
        tables = {r["tablename"] for r in await pool.fetch("select tablename from pg_tables where schemaname='public'")}
        assert {"users", "login_requests", "sessions", "schema_migrations"} <= tables

    async def test_rerun_applies_nothing(self, pool):
        assert await run_migrations(pool) == []

    async def test_failing_migration_rolls_back_and_is_not_recorded(self, pool, tmp_path: Path):
        (tmp_path / "0001_good.sql").write_text("create table tmp_good (id int);")
        (tmp_path / "0002_bad.sql").write_text("create table tmp_half (id int); select 1/0;")
        try:
            with pytest.raises(Exception):
                await run_migrations(pool, tmp_path)
            names = {r["name"] for r in await pool.fetch("select name from schema_migrations")}
            assert "0001_good.sql" in names and "0002_bad.sql" not in names
            tables = {r["tablename"] for r in await pool.fetch("select tablename from pg_tables where schemaname='public'")}
            assert "tmp_good" in tables
            assert "tmp_half" not in tables, "неудавшаяся миграция не должна оставлять половину схемы"
        finally:
            await pool.execute("drop table if exists tmp_good")
            await pool.execute("delete from schema_migrations where name like '000%_good.sql' or name like '000%_bad.sql'")

    async def test_migrations_are_applied_in_order(self, pool, tmp_path: Path):
        (tmp_path / "0010_b.sql").write_text("create table tmp_order_b (id int);")
        (tmp_path / "0009_a.sql").write_text("create table tmp_order_a (id int);")
        try:
            assert await run_migrations(pool, tmp_path) == ["0009_a.sql", "0010_b.sql"]
        finally:
            await pool.execute("drop table if exists tmp_order_a, tmp_order_b")
            await pool.execute("delete from schema_migrations where name in ('0009_a.sql','0010_b.sql')")


class TestRateLimiter:
    def test_blocks_after_limit_and_recovers(self):
        now = [0.0]
        limiter = SlidingWindowLimiter(3, 60, clock=lambda: now[0])
        assert [limiter.allow("ip") for _ in range(3)] == [True, True, True]
        assert limiter.allow("ip") is False
        assert 1 <= limiter.retry_after("ip") <= 61
        now[0] = 61.0
        assert limiter.allow("ip") is True

    def test_keys_are_independent(self):
        limiter = SlidingWindowLimiter(1, 60)
        assert limiter.allow("a") and limiter.allow("b")
        assert not limiter.allow("a")

    async def test_start_endpoint_returns_429_with_retry_after(self, settings, telegram):
        import httpx

        from app.main import create_app

        s = settings.model_copy(update={"rate_limit_start_per_minute": 2})
        app = create_app(s, telegram=telegram)
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
                codes = [(await c.post("/v1/auth/telegram/start", json={})).status_code for _ in range(4)]
                assert codes == [200, 200, 429, 429]
                r = await c.post("/v1/auth/telegram/start", json={})
                assert r.headers["retry-after"].isdigit()
                assert r.json()["detail"]["code"] == "rate_limited"

    async def test_forwarded_ip_is_used_only_when_proxy_is_trusted(self, settings, telegram):
        import httpx

        from app.main import create_app

        async def run(trust: bool) -> list[int]:
            s = settings.model_copy(update={"rate_limit_start_per_minute": 1, "trust_proxy": trust})
            app = create_app(s, telegram=telegram)
            async with app.router.lifespan_context(app):
                async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
                    return [
                        (await c.post("/v1/auth/telegram/start", json={}, headers={"X-Forwarded-For": f"1.2.3.{i}"})).status_code
                        for i in range(2)
                    ]

        assert await run(trust=True) == [200, 200], "разные клиенты за прокси не мешают друг другу"
        assert await run(trust=False) == [200, 429], "без доверия подделать заголовок нельзя"
