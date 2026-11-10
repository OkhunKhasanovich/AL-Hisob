import logging
from typing import Any, Protocol

import httpx

log = logging.getLogger("app.telegram")


class TelegramClient(Protocol):
    async def send_message(self, chat_id: int, text: str, reply_markup: dict[str, Any] | None = None) -> None: ...

    async def set_webhook(self, url: str, secret_token: str) -> None: ...


class HttpTelegramClient:
    """Минимальный клиент Bot API (только то, что нужно для входа)."""

    def __init__(self, token: str, *, timeout: float = 10.0) -> None:
        self._base = f"https://api.telegram.org/bot{token}"
        self._timeout = timeout

    async def _call(self, method: str, payload: dict[str, Any]) -> None:
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.post(f"{self._base}/{method}", json=payload)
        if response.status_code != 200:
            # Тело ответа не логируем целиком: оно может содержать лишнее; токен в URL не пишем.
            log.warning("telegram %s failed: HTTP %s", method, response.status_code)
            response.raise_for_status()

    async def send_message(self, chat_id: int, text: str, reply_markup: dict[str, Any] | None = None) -> None:
        payload: dict[str, Any] = {"chat_id": chat_id, "text": text}
        if reply_markup is not None:
            payload["reply_markup"] = reply_markup
        await self._call("sendMessage", payload)

    async def set_webhook(self, url: str, secret_token: str) -> None:
        await self._call(
            "setWebhook",
            {"url": url, "secret_token": secret_token, "allowed_updates": ["message"]},
        )


class NullTelegramClient:
    """Заглушка для запуска без бота (разработка): ничего не отправляет."""

    async def send_message(self, chat_id: int, text: str, reply_markup: dict[str, Any] | None = None) -> None:
        log.info("telegram disabled: message to %s dropped", chat_id)

    async def set_webhook(self, url: str, secret_token: str) -> None:
        log.info("telegram disabled: webhook not set")
