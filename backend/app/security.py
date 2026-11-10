import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt


def new_secret(nbytes: int = 32) -> str:
    """Случайный URL-безопасный токен (≥ 256 бит при значениях по умолчанию)."""
    return secrets.token_urlsafe(nbytes)


def hash_token(token: str) -> str:
    """SHA-256 токена. Токены случайные и длинные, поэтому соль и медленный хэш не нужны."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def safe_equal(a: str, b: str) -> bool:
    return hmac.compare_digest(a.encode("utf-8"), b.encode("utf-8"))


class InvalidToken(Exception):
    """Токен недействителен: подпись, срок или тип не подходят."""


def create_access_token(*, secret: str, user_id: UUID, session_id: UUID, ttl_minutes: int,
                        now: datetime | None = None) -> str:
    now = now or datetime.now(UTC)
    payload = {
        "typ": "access",
        "sub": str(user_id),
        "sid": str(session_id),
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=ttl_minutes)).timestamp()),
    }
    return jwt.encode(payload, secret, algorithm="HS256")


def decode_access_token(token: str, *, secret: str) -> tuple[UUID, UUID]:
    """Возвращает (user_id, session_id) или бросает [InvalidToken]."""
    try:
        data = jwt.decode(token, secret, algorithms=["HS256"], options={"require": ["exp", "sub", "sid"]})
        if data.get("typ") != "access":
            raise InvalidToken("wrong token type")
        return UUID(data["sub"]), UUID(data["sid"])
    except (jwt.PyJWTError, ValueError, KeyError) as e:
        raise InvalidToken(str(e)) from e


def normalize_phone(raw: str) -> str | None:
    """Приводит номер к виду `+998901234567`. `None`, если это не похоже на номер.

    Узбекские номера принимаются с кодом и без него; остальные — в международном
    формате (8–15 цифр), так как Telegram присылает номер любой страны.
    """
    digits = "".join(ch for ch in raw if ch.isdigit())
    if len(digits) == 9:
        return f"+998{digits}"
    if 8 <= len(digits) <= 15:
        return f"+{digits}"
    return None
