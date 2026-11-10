from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.config import Settings
from app.security import (
    InvalidToken,
    create_access_token,
    decode_access_token,
    hash_token,
    new_secret,
    normalize_phone,
    safe_equal,
)

SECRET = "x" * 40


def test_tokens_are_random_and_long():
    tokens = {new_secret() for _ in range(200)}
    assert len(tokens) == 200
    assert all(len(t) >= 40 for t in tokens)


def test_hash_is_deterministic_and_not_the_token():
    assert hash_token("abc") == hash_token("abc")
    assert hash_token("abc") != hash_token("abd")
    assert "abc" not in hash_token("abc")
    assert len(hash_token("abc")) == 64


def test_safe_equal():
    assert safe_equal("a", "a")
    assert not safe_equal("a", "b")
    assert not safe_equal("a", "ab")


class TestAccessToken:
    def test_roundtrip(self):
        uid, sid = uuid4(), uuid4()
        token = create_access_token(secret=SECRET, user_id=uid, session_id=sid, ttl_minutes=5)
        assert decode_access_token(token, secret=SECRET) == (uid, sid)

    def test_expired(self):
        old = datetime.now(UTC) - timedelta(hours=1)
        token = create_access_token(secret=SECRET, user_id=uuid4(), session_id=uuid4(), ttl_minutes=5, now=old)
        with pytest.raises(InvalidToken):
            decode_access_token(token, secret=SECRET)

    def test_wrong_secret(self):
        token = create_access_token(secret=SECRET, user_id=uuid4(), session_id=uuid4(), ttl_minutes=5)
        with pytest.raises(InvalidToken):
            decode_access_token(token, secret="y" * 40)

    def test_tampered(self):
        token = create_access_token(secret=SECRET, user_id=uuid4(), session_id=uuid4(), ttl_minutes=5)
        head, payload, sig = token.split(".")
        with pytest.raises(InvalidToken):
            decode_access_token(f"{head}.{payload}x.{sig}", secret=SECRET)

    @pytest.mark.parametrize("garbage", ["", "abc", "a.b.c", "Bearer x"])
    def test_garbage(self, garbage):
        with pytest.raises(InvalidToken):
            decode_access_token(garbage, secret=SECRET)

    def test_unsigned_token_is_rejected(self):
        import jwt

        forged = jwt.encode({"sub": str(uuid4()), "sid": str(uuid4()), "typ": "access"}, key="", algorithm="none")
        with pytest.raises(InvalidToken):
            decode_access_token(forged, secret=SECRET)

    def test_wrong_type_is_rejected(self):
        import jwt

        payload = {"typ": "refresh", "sub": str(uuid4()), "sid": str(uuid4()),
                   "exp": int((datetime.now(UTC) + timedelta(minutes=5)).timestamp())}
        with pytest.raises(InvalidToken):
            decode_access_token(jwt.encode(payload, SECRET, algorithm="HS256"), secret=SECRET)

    def test_missing_claims(self):
        import jwt

        payload = {"typ": "access", "exp": int((datetime.now(UTC) + timedelta(minutes=5)).timestamp())}
        with pytest.raises(InvalidToken):
            decode_access_token(jwt.encode(payload, SECRET, algorithm="HS256"), secret=SECRET)


class TestNormalizePhone:
    @pytest.mark.parametrize(
        "raw",
        ["901234567", "90 123 45 67", "998901234567", "+998901234567", "+998 (90) 123-45-67", "998 90 123 45 67"],
    )
    def test_uzbek_formats(self, raw):
        assert normalize_phone(raw) == "+998901234567"

    def test_international(self):
        assert normalize_phone("79123456789") == "+79123456789"
        assert normalize_phone("+1 (202) 555-0100") == "+12025550100"

    @pytest.mark.parametrize("raw", ["", "abc", "123", "1234567", "1" * 16])
    def test_rejects_garbage(self, raw):
        assert normalize_phone(raw) is None


class TestSettings:
    def test_development_defaults_are_ok(self):
        assert Settings(env="development").is_production is False

    def test_production_requires_real_secrets(self):
        with pytest.raises(ValueError) as e:
            Settings(env="production")
        message = str(e.value)
        assert "JWT_SECRET" in message and "TELEGRAM_BOT_TOKEN" in message

    def test_production_accepts_proper_config(self):
        s = Settings(
            env="production",
            jwt_secret="a" * 48,
            telegram_bot_token="1:abc",
            telegram_bot_username="Bot",
            telegram_webhook_secret="b" * 20,
        )
        assert s.is_production
