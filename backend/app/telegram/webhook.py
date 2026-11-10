"""Приём обновлений от Telegram: вход по номеру телефона через бота."""
import logging
from typing import Any

import asyncpg
from fastapi import APIRouter, Header, HTTPException, Request

from app.auth import service
from app.security import safe_equal
from app.telegram import messages
from app.telegram.client import TelegramClient

log = logging.getLogger("app.telegram")


def _share_keyboard(lang: str | None) -> dict[str, Any]:
    return {
        "keyboard": [[{"text": messages.text(lang, "share_button"), "request_contact": True}]],
        "resize_keyboard": True,
        "one_time_keyboard": True,
    }


async def handle_update(pool: asyncpg.Pool, telegram: TelegramClient, update: dict[str, Any]) -> None:
    message = update.get("message")
    if not isinstance(message, dict):
        return
    sender = message.get("from") or {}
    chat = message.get("chat") or {}
    telegram_id = sender.get("id")
    chat_id = chat.get("id")
    if not isinstance(telegram_id, int) or not isinstance(chat_id, int):
        return
    lang = sender.get("language_code")

    contact = message.get("contact")
    if isinstance(contact, dict):
        await _handle_contact(pool, telegram, chat_id, telegram_id, sender, contact, lang)
        return

    text = (message.get("text") or "").strip()
    if text.startswith("/start"):
        payload = text[len("/start"):].strip()
        if not payload:
            await telegram.send_message(chat_id, messages.text(lang, "help"))
            return
        if await service.bot_attach_telegram(pool, start_token=payload, telegram_id=telegram_id):
            await telegram.send_message(chat_id, messages.text(lang, "share_prompt"), _share_keyboard(lang))
        else:
            await telegram.send_message(chat_id, messages.text(lang, "expired"))
        return

    await telegram.send_message(chat_id, messages.text(lang, "help"))


async def _handle_contact(pool, telegram, chat_id, telegram_id, sender, contact, lang) -> None:
    name = " ".join(p for p in (sender.get("first_name"), sender.get("last_name")) if p) or sender.get("username")
    try:
        approved = await service.bot_approve_contact(
            pool,
            telegram_id=telegram_id,
            contact_user_id=contact.get("user_id"),
            phone_raw=str(contact.get("phone_number") or ""),
            telegram_name=name,
        )
    except service.ContactRejected:
        await telegram.send_message(chat_id, messages.text(lang, "not_own"), _share_keyboard(lang))
        return
    key = "done" if approved else "no_request"
    await telegram.send_message(chat_id, messages.text(lang, key), {"remove_keyboard": True})


def build_webhook_router(settings) -> APIRouter:
    router = APIRouter()

    @router.post("/telegram/webhook", include_in_schema=False)
    async def webhook(
        request: Request,
        x_telegram_bot_api_secret_token: str | None = Header(default=None),
    ) -> dict[str, bool]:
        secret = settings.telegram_webhook_secret
        if not secret or not x_telegram_bot_api_secret_token or not safe_equal(
            x_telegram_bot_api_secret_token, secret
        ):
            raise HTTPException(status_code=403, detail={"code": "forbidden"})
        try:
            update = await request.json()
        except ValueError:
            raise HTTPException(status_code=400, detail={"code": "bad_json"}) from None
        try:
            await handle_update(request.app.state.pool, request.app.state.telegram, update)
        except Exception:  # noqa: BLE001 — Telegram не должен повторять запрос из-за нашей ошибки
            log.exception("failed to handle telegram update")
        return {"ok": True}

    return router
