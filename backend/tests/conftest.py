import os
from typing import Any

import httpx
import pytest
import pytest_asyncio

from app.config import Settings
from app.main import create_app

TEST_DSN = os.environ.get(
    "TEST_DATABASE_URL", "postgresql://postgres@/alhisob_test?host=/tmp&port=5433"
)
WEBHOOK_SECRET = "webhook-secret-0123456789"


class FakeTelegram:
    """Запоминает отправленные ботом сообщения вместо запросов в Telegram."""

    def __init__(self) -> None:
        self.sent: list[dict[str, Any]] = []
        self.webhook: tuple[str, str] | None = None

    async def send_message(self, chat_id: int, text: str, reply_markup: dict[str, Any] | None = None) -> None:
        self.sent.append({"chat_id": chat_id, "text": text, "reply_markup": reply_markup})

    async def set_webhook(self, url: str, secret_token: str) -> None:
        self.webhook = (url, secret_token)

    @property
    def last(self) -> dict[str, Any]:
        return self.sent[-1]


@pytest.fixture
def settings() -> Settings:
    return Settings(
        env="development",
        database_url=TEST_DSN,
        jwt_secret="test-secret-0123456789-0123456789-abcdef",
        telegram_bot_token="123:TEST",
        telegram_bot_username="TestBot",
        telegram_webhook_secret=WEBHOOK_SECRET,
        public_base_url="https://api.test",
        rate_limit_start_per_minute=1000,
        rate_limit_poll_per_minute=1000,
        rate_limit_refresh_per_minute=1000,
    )


@pytest.fixture
def telegram() -> FakeTelegram:
    return FakeTelegram()


@pytest_asyncio.fixture
async def app(settings, telegram):
    application = create_app(settings, telegram=telegram)
    async with application.router.lifespan_context(application):
        await application.state.pool.execute("truncate users, login_requests, sessions cascade")
        yield application


@pytest_asyncio.fixture
async def client(app):
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@pytest_asyncio.fixture
async def pool(app):
    return app.state.pool


# ---------- помощники сценариев ----------

def bot_update(*, user_id: int = 111, text: str | None = None, contact: dict | None = None,
               lang: str | None = "ru", first_name: str = "Ali") -> dict[str, Any]:
    message: dict[str, Any] = {
        "message_id": 1,
        "from": {"id": user_id, "first_name": first_name, "language_code": lang},
        "chat": {"id": user_id, "type": "private"},
    }
    if text is not None:
        message["text"] = text
    if contact is not None:
        message["contact"] = contact
    return {"update_id": 1, "message": message}


async def post_update(client: httpx.AsyncClient, update: dict[str, Any], *, secret: str | None = WEBHOOK_SECRET):
    headers = {"X-Telegram-Bot-Api-Secret-Token": secret} if secret is not None else {}
    return await client.post("/telegram/webhook", json=update, headers=headers)


async def start_login(client: httpx.AsyncClient) -> dict[str, Any]:
    r = await client.post("/v1/auth/telegram/start", json={"device_name": "Test phone"})
    assert r.status_code == 200, r.text
    return r.json()


def token_from(bot_url: str) -> str:
    return bot_url.split("start=")[1]


async def approve_via_bot(
    client: httpx.AsyncClient, start: dict[str, Any], *, user_id: int = 111, phone: str = "998901234567",
    lang: str | None = "ru",
) -> None:
    r = await post_update(client, bot_update(user_id=user_id, text=f"/start {token_from(start['bot_url'])}", lang=lang))
    assert r.status_code == 200
    r = await post_update(
        client,
        bot_update(user_id=user_id, contact={"phone_number": phone, "user_id": user_id}, lang=lang),
    )
    assert r.status_code == 200


async def poll(client: httpx.AsyncClient, start: dict[str, Any]) -> httpx.Response:
    return await client.post(
        "/v1/auth/telegram/poll",
        json={"request_id": start["request_id"], "poll_secret": start["poll_secret"]},
    )


async def full_login(client: httpx.AsyncClient, *, user_id: int = 111, phone: str = "998901234567") -> dict[str, Any]:
    start = await start_login(client)
    await approve_via_bot(client, start, user_id=user_id, phone=phone)
    r = await poll(client, start)
    assert r.status_code == 200 and r.json()["status"] == "ok", r.text
    return r.json()


def auth(tokens: dict[str, Any]) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}
