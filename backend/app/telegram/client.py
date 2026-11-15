import json
import logging
from typing import Any, Protocol

import httpx

log = logging.getLogger("app.telegram")

APK_MIME = "application/vnd.android.package-archive"


class TelegramError(RuntimeError):
    """Ошибка Bot API. В сообщении нет адреса запроса: в нём лежит токен бота."""


class TelegramClient(Protocol):
    async def send_message(self, chat_id: int, text: str, reply_markup: dict[str, Any] | None = None) -> None: ...

    async def send_document(
        self,
        chat_id: int,
        *,
        document: "str | tuple[str, bytes]",
        caption: str | None = None,
        reply_markup: dict[str, Any] | None = None,
    ) -> str | None:
        """Отправляет файл: `str` — уже известный file_id, `(имя, байты)` — загрузка. Возвращает file_id."""
        ...

    async def set_webhook(self, url: str, secret_token: str) -> None: ...

    async def set_commands(self, commands: list[dict[str, str]], language_code: str | None = None) -> None: ...


class HttpTelegramClient:
    """Минимальный клиент Bot API (вход, отправка файла приложения, меню команд)."""

    def __init__(self, token: str, *, timeout: float = 10.0, transport: httpx.AsyncBaseTransport | None = None) -> None:
        self._base = f"https://api.telegram.org/bot{token}"
        self._timeout = timeout
        self._transport = transport

    async def _post(self, method: str, *, timeout: float | None = None, **kwargs: Any) -> dict[str, Any]:
        try:
            async with httpx.AsyncClient(timeout=timeout or self._timeout, transport=self._transport) as client:
                response = await client.post(f"{self._base}/{method}", **kwargs)
        except httpx.HTTPError as e:
            # В тексте httpx-ошибок бывает адрес запроса (а в нём токен): подменяем своим.
            raise TelegramError(f"telegram {method} failed: {type(e).__name__}") from None
        if response.status_code != 200:
            # Тело ответа не логируем целиком: оно может содержать лишнее.
            log.warning("telegram %s failed: HTTP %s", method, response.status_code)
            raise TelegramError(f"telegram {method} failed: HTTP {response.status_code}")
        try:
            return response.json()
        except ValueError:
            return {}

    async def send_message(self, chat_id: int, text: str, reply_markup: dict[str, Any] | None = None) -> None:
        payload: dict[str, Any] = {"chat_id": chat_id, "text": text}
        if reply_markup is not None:
            payload["reply_markup"] = reply_markup
        await self._post("sendMessage", json=payload)

    async def send_document(
        self,
        chat_id: int,
        *,
        document: "str | tuple[str, bytes]",
        caption: str | None = None,
        reply_markup: dict[str, Any] | None = None,
    ) -> str | None:
        data: dict[str, str] = {"chat_id": str(chat_id)}
        if caption:
            data["caption"] = caption
        if reply_markup is not None:
            data["reply_markup"] = json.dumps(reply_markup)
        files = None
        if isinstance(document, str):
            data["document"] = document
        else:
            name, content = document
            files = {"document": (name, content, APK_MIME)}
        # Загрузка 20+ МБ с телефона бота может быть небыстрой.
        body = await self._post("sendDocument", timeout=180.0, data=data, files=files)
        file_id = ((body.get("result") or {}).get("document") or {}).get("file_id")
        return file_id if isinstance(file_id, str) else None

    async def set_webhook(self, url: str, secret_token: str) -> None:
        await self._post("setWebhook", json={"url": url, "secret_token": secret_token, "allowed_updates": ["message"]})

    async def set_commands(self, commands: list[dict[str, str]], language_code: str | None = None) -> None:
        payload: dict[str, Any] = {"commands": commands}
        if language_code:
            payload["language_code"] = language_code
        await self._post("setMyCommands", json=payload)


class NullTelegramClient:
    """Заглушка для запуска без бота (разработка): ничего не отправляет."""

    async def send_message(self, chat_id: int, text: str, reply_markup: dict[str, Any] | None = None) -> None:
        log.info("telegram disabled: message to %s dropped", chat_id)

    async def send_document(self, chat_id: int, *, document: "str | tuple[str, bytes]", caption: str | None = None,
                            reply_markup: dict[str, Any] | None = None) -> str | None:
        log.info("telegram disabled: document to %s dropped", chat_id)
        return None

    async def set_webhook(self, url: str, secret_token: str) -> None:
        log.info("telegram disabled: webhook not set")

    async def set_commands(self, commands: list[dict[str, str]], language_code: str | None = None) -> None:
        log.info("telegram disabled: commands not set")
