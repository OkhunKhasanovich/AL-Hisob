"""Команда бота /app: отправляет последнюю версию приложения файлом."""
import asyncio
import logging
import time
from typing import Any

from app.telegram import messages
from app.telegram.client import TelegramClient
from app.telegram.releases import (
    ABI_ORDER,
    ApkAsset,
    Release,
    ReleaseSource,
)

log = logging.getLogger("app.telegram")

_ABI_LABELS = {"arm64-v8a": "ARM64", "armeabi-v7a": "ARMv7 (32-bit)", "x86_64": "x86_64"}


class AppDelivery:
    """Файл загружается в Telegram один раз на сборку: потом отправляется по file_id, без скачивания."""

    def __init__(self, releases: ReleaseSource, *, cooldown: float = 15.0) -> None:
        self._releases = releases
        self._cooldown = cooldown
        self._file_ids: dict[tuple[int, str], str] = {}
        self._last_request: dict[int, float] = {}
        self._locks: dict[tuple[int, str], asyncio.Lock] = {}

    def too_soon(self, telegram_id: int) -> bool:
        now = time.monotonic()
        last = self._last_request.get(telegram_id)
        if last is not None and now - last < self._cooldown:
            return True
        self._last_request[telegram_id] = now
        if len(self._last_request) > 5000:
            self._last_request = {k: v for k, v in self._last_request.items() if now - v < self._cooldown}
        return False

    async def send_latest(self, telegram: TelegramClient, chat_id: int, lang: str | None) -> None:
        release = await self._releases.latest()
        asset = release.default if release else None
        if release is None or asset is None:
            await telegram.send_message(chat_id, messages.text(lang, "app_none"))
            return
        caption = messages.text(lang, "app_caption").format(
            version=release.version or "", build=release.build, notes=release.notes
        ).replace("\n\n\n", "\n\n").strip()[:1000]
        markup = self._other_versions(release, asset, lang)
        try:
            document: Any = await self._document(release, asset)
            file_id = await telegram.send_document(chat_id, document=document, caption=caption, reply_markup=markup)
            if file_id:
                self._file_ids[(release.build, asset.abi)] = file_id
        except Exception:
            log.exception("failed to send the app file")
            # Закэшированный file_id мог устареть: в следующий раз загрузим заново.
            self._file_ids.pop((release.build, asset.abi), None)
            await telegram.send_message(
                chat_id,
                f"{messages.text(lang, 'app_failed')}\n{asset.url}",
            )

    async def _document(self, release: Release, asset: ApkAsset) -> "str | tuple[str, bytes]":
        key = (release.build, asset.abi)
        async with self._locks.setdefault(key, asyncio.Lock()):
            cached = self._file_ids.get(key)
            if cached:
                return cached
            return (asset.name, await self._releases.download(asset))

    @staticmethod
    def _other_versions(release: Release, sent: ApkAsset, lang: str | None) -> dict[str, Any] | None:
        rows = [
            [{"text": f"{_ABI_LABELS[abi]}", "url": release.assets[abi].url}]
            for abi in ABI_ORDER
            if abi in release.assets and abi != sent.abi
        ]
        return {"inline_keyboard": rows} if rows else None
