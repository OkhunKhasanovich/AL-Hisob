"""Ссылки для открытия приложения: страница /open и подтверждение Android App Links."""
import html
import json
from urllib.parse import quote

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

_PAGES = {
    "ru": ("Открыть Al-Hisob", "Если приложение не открылось само, нажмите кнопку.", "Открыть приложение",
           "Приложение не установлено?", "Скачать"),
    "uz": ("Al-Hisob’ni ochish", "Ilova o‘zi ochilmasa, tugmani bosing.", "Ilovani ochish",
           "Ilova o‘rnatilmaganmi?", "Yuklab olish"),
    "en": ("Open Al-Hisob", "If the app did not open by itself, tap the button.", "Open the app",
           "App not installed?", "Download"),
}

_HEADERS = {"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer"}


def _language(request: Request) -> str:
    header = (request.headers.get("accept-language") or "").lower()
    for part in header.split(","):
        lang = part.strip().split(";")[0].split("-")[0]
        if lang in _PAGES:
            return lang
    return "ru"


def build_router(settings) -> APIRouter:
    router = APIRouter()

    @router.get("/open", response_class=HTMLResponse, include_in_schema=False)
    async def open_app(request: Request) -> HTMLResponse:
        title, hint, button, missing, download = _PAGES[_language(request)]
        # Если Android не открыл приложение по ссылке (например, внутри браузера Telegram),
        # эта страница пробует запустить его через intent; без приложения ведёт на скачивание.
        intent = (
            f"intent://open#Intent;scheme=alhisob;package={settings.android_package};"
            f"S.browser_fallback_url={quote(settings.app_download_url, safe='')};end"
        )
        body = f"""<!doctype html>
<html lang="{_language(request)}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>
body{{font-family:system-ui,sans-serif;margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#10231c;color:#e6f2ec}}
main{{max-width:360px;padding:24px;text-align:center}}
a.b{{display:block;margin:20px 0 12px;padding:16px;border-radius:16px;background:#7fd4a8;color:#06261a;font-weight:700;text-decoration:none}}
p{{opacity:.8;line-height:1.4}} small a{{color:#7fd4a8}}
</style></head>
<body><main>
<h1>{html.escape(title)}</h1><p>{html.escape(hint)}</p>
<a class="b" href="{html.escape(intent)}">{html.escape(button)}</a>
<small>{html.escape(missing)} <a href="{html.escape(settings.app_download_url)}">{html.escape(download)}</a></small>
</main>
<script>setTimeout(function(){{location.href={json.dumps(intent)}}},50)</script>
</body></html>"""
        return HTMLResponse(body, headers=_HEADERS)

    @router.get("/.well-known/assetlinks.json", include_in_schema=False)
    async def assetlinks() -> list[dict]:
        fingerprints = [f.strip().upper() for f in settings.android_cert_sha256.split(",") if f.strip()]
        if not fingerprints:
            return []
        return [
            {
                "relation": ["delegate_permission/common.handle_all_urls"],
                "target": {
                    "namespace": "android_app",
                    "package_name": settings.android_package,
                    "sha256_cert_fingerprints": fingerprints,
                },
            }
        ]

    return router
