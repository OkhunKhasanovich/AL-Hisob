"""Логика входа: запрос → подтверждение номера ботом → токены → обновление → выход."""
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import asyncpg

from app.config import Settings
from app.security import (
    create_access_token,
    hash_token,
    new_secret,
    normalize_phone,
    safe_equal,
)


class AuthError(Exception):
    """Ошибка входа с кодом для клиента."""

    def __init__(self, code: str, status: int = 401) -> None:
        super().__init__(code)
        self.code = code
        self.status = status


@dataclass
class StartedLogin:
    request_id: UUID
    poll_secret: str
    start_token: str
    expires_in: int


@dataclass
class TokenPair:
    access_token: str
    refresh_token: str
    expires_in: int
    user: dict[str, Any]


def _user_json(row: asyncpg.Record) -> dict[str, Any]:
    return {"id": str(row["id"]), "phone": row["phone"], "name": row["name"]}


async def start_login(pool: asyncpg.Pool, settings: Settings, *, device_name: str | None) -> StartedLogin:
    start_token = new_secret(24)
    poll_secret = new_secret(32)
    ttl = settings.login_request_ttl_minutes
    async with pool.acquire() as conn:
        # Старые неиспользованные запросы чистим по ходу дела.
        await conn.execute("delete from login_requests where expires_at < now() - interval '1 day'")
        request_id = await conn.fetchval(
            """
            insert into login_requests (start_token_hash, poll_secret_hash, device_name, expires_at)
            values ($1, $2, $3, now() + make_interval(mins => $4))
            returning id
            """,
            hash_token(start_token),
            hash_token(poll_secret),
            (device_name or "")[:80] or None,
            ttl,
        )
    return StartedLogin(request_id, poll_secret, start_token, ttl * 60)


# ---------- сторона бота ----------

async def bot_attach_telegram(pool: asyncpg.Pool, *, start_token: str, telegram_id: int) -> bool:
    """Бот получил `/start <токен>`: привязываем запрос к пользователю Telegram.

    `False`, если запрос не найден или устарел.
    """
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            update login_requests set telegram_id = $2
            where start_token_hash = $1 and status = 'pending' and expires_at > now()
            returning id
            """,
            hash_token(start_token),
            telegram_id,
        )
    return row is not None


class ContactRejected(Exception):
    """Контакт не подходит: это чужой номер или он не распознан."""


async def bot_approve_contact(
    pool: asyncpg.Pool,
    *,
    telegram_id: int,
    contact_user_id: int | None,
    phone_raw: str,
    telegram_name: str | None,
) -> bool:
    """Пользователь поделился номером. Подтверждаем последний ожидающий запрос.

    Номер принимается, только если контакт принадлежит самому отправителю
    (`contact.user_id == from.id`): иначе можно было бы войти по чужому номеру.
    Возвращает `False`, если ожидающего запроса нет (или он устарел).
    """
    if contact_user_id is None or contact_user_id != telegram_id:
        raise ContactRejected("not own contact")
    phone = normalize_phone(phone_raw)
    if phone is None:
        raise ContactRejected("bad phone")

    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            update login_requests set status = 'approved', phone = $2, telegram_name = $3, approved_at = now()
            where id = (
                select id from login_requests
                where telegram_id = $1 and status = 'pending' and expires_at > now()
                order by created_at desc limit 1
                for update skip locked
            )
            returning id
            """,
            telegram_id,
            phone,
            (telegram_name or "")[:120] or None,
        )
    return row is not None


# ---------- сторона приложения ----------

async def poll_login(
    pool: asyncpg.Pool, settings: Settings, *, request_id: UUID, poll_secret: str
) -> TokenPair | None:
    """`None` — ещё ждём подтверждения. Токены выдаются ровно один раз."""
    async with pool.acquire() as conn:
        async with conn.transaction():
            row = await conn.fetchrow(
                """
                select *, (expires_at <= now()) as is_expired
                from login_requests where id = $1 for update
                """,
                request_id,
            )
            if row is None or not safe_equal(row["poll_secret_hash"], hash_token(poll_secret)):
                raise AuthError("invalid_request", 404)
            if row["status"] == "consumed":
                raise AuthError("already_used", 410)
            if row["status"] == "pending":
                if row["is_expired"]:
                    raise AuthError("expired", 410)
                return None
            # approved: даже если срок прошёл, пока приложение не опросило, выдаём только в пределах TTL
            if row["is_expired"]:
                raise AuthError("expired", 410)

            user = await conn.fetchrow(
                """
                insert into users (phone, telegram_id, name)
                values ($1, $2, $3)
                on conflict (phone) do update
                   set telegram_id = excluded.telegram_id,
                       name = coalesce(users.name, excluded.name),
                       updated_at = now()
                returning *
                """,
                row["phone"],
                row["telegram_id"],
                row["telegram_name"],
            )
            await conn.execute(
                "update login_requests set status = 'consumed', consumed_at = now() where id = $1", request_id
            )
            return await _open_session(conn, settings, user, device_name=row["device_name"])


async def _open_session(
    conn: asyncpg.Connection, settings: Settings, user: asyncpg.Record, *, device_name: str | None
) -> TokenPair:
    refresh = new_secret(48)
    session_id = await conn.fetchval(
        """
        insert into sessions (user_id, refresh_hash, device_name, expires_at)
        values ($1, $2, $3, now() + make_interval(days => $4))
        returning id
        """,
        user["id"],
        hash_token(refresh),
        device_name,
        settings.refresh_token_ttl_days,
    )
    access = create_access_token(
        secret=settings.jwt_secret,
        user_id=user["id"],
        session_id=session_id,
        ttl_minutes=settings.access_token_ttl_minutes,
    )
    return TokenPair(access, refresh, settings.access_token_ttl_minutes * 60, _user_json(user))


async def refresh_session(pool: asyncpg.Pool, settings: Settings, *, refresh_token: str) -> TokenPair:
    """Меняет refresh-токен на новую пару.

    Старый токен после обмена недействителен. Если им воспользуются повторно
    вне короткого окна `refresh_reuse_grace_seconds`, это похоже на кражу —
    сессия закрывается целиком.
    """
    h = hash_token(refresh_token)
    reused = False
    result: TokenPair | None = None
    async with pool.acquire() as conn:
        async with conn.transaction():
            s = await conn.fetchrow(
                """
                select *, (expires_at <= now()) as is_expired,
                       (rotated_at is not null and rotated_at > now() - make_interval(secs => $2)) as in_grace
                from sessions
                where refresh_hash = $1 or prev_refresh_hash = $1
                for update
                """,
                h,
                float(settings.refresh_reuse_grace_seconds),
            )
            if s is None or s["revoked_at"] is not None or s["is_expired"]:
                raise AuthError("invalid_refresh")

            if s["refresh_hash"] != h and not s["in_grace"]:
                # Старый токен предъявлен вне окна повтора: считаем, что он украден.
                await conn.execute("update sessions set revoked_at = now() where id = $1", s["id"])
                reused = True
            else:
                new_refresh = new_secret(48)
                await conn.execute(
                    """
                    update sessions
                       set prev_refresh_hash = refresh_hash, refresh_hash = $2,
                           rotated_at = now(), last_used_at = now()
                     where id = $1
                    """,
                    s["id"],
                    hash_token(new_refresh),
                )
                user = await conn.fetchrow("select * from users where id = $1", s["user_id"])
                access = create_access_token(
                    secret=settings.jwt_secret,
                    user_id=user["id"],
                    session_id=s["id"],
                    ttl_minutes=settings.access_token_ttl_minutes,
                )
                result = TokenPair(access, new_refresh, settings.access_token_ttl_minutes * 60, _user_json(user))

    # Исключение — только после коммита транзакции: иначе отзыв сессии откатился бы.
    if reused:
        raise AuthError("refresh_reused")
    assert result is not None
    return result


async def logout_session(pool: asyncpg.Pool, session_id: UUID) -> None:
    await pool.execute("update sessions set revoked_at = now() where id = $1 and revoked_at is null", session_id)


async def load_active_user(pool: asyncpg.Pool, user_id: UUID, session_id: UUID) -> dict[str, Any] | None:
    """Пользователь, если сессия жива (не отозвана и не истекла)."""
    row = await pool.fetchrow(
        """
        select u.* from sessions s join users u on u.id = s.user_id
        where s.id = $1 and s.user_id = $2 and s.revoked_at is null and s.expires_at > now()
        """,
        session_id,
        user_id,
    )
    return _user_json(row) if row else None


def utcnow() -> datetime:
    return datetime.now(UTC)
