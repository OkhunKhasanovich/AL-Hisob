"""Служебные команды: `python -m app.cli migrate` и `python -m app.cli set-webhook`."""
import asyncio
import sys

from app.config import get_settings
from app.db import create_pool, run_migrations
from app.telegram.client import HttpTelegramClient


async def _migrate() -> None:
    pool = await create_pool(get_settings().database_url)
    try:
        applied = await run_migrations(pool)
        print("applied:", ", ".join(applied) if applied else "nothing to do")
    finally:
        await pool.close()


async def _set_webhook() -> None:
    s = get_settings()
    if not (s.telegram_bot_token and s.telegram_webhook_secret):
        sys.exit("TELEGRAM_BOT_TOKEN and TELEGRAM_WEBHOOK_SECRET must be set")
    url = f"{s.public_base_url.rstrip('/')}/telegram/webhook"
    await HttpTelegramClient(s.telegram_bot_token).set_webhook(url, s.telegram_webhook_secret)
    print("webhook set:", url)


def main() -> None:
    commands = {"migrate": _migrate, "set-webhook": _set_webhook}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        sys.exit(f"usage: python -m app.cli [{'|'.join(commands)}]")
    asyncio.run(commands[sys.argv[1]]())


if __name__ == "__main__":
    main()
