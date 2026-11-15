"""Последняя версия приложения из релизов GitHub: для команды бота /app."""
import logging
import re
import time
from dataclasses import dataclass
from typing import Protocol

import httpx

log = logging.getLogger("app.telegram")

# Лимит Telegram на файл от бота — 50 МБ; берём с запасом.
MAX_APK_BYTES = 49 * 1024 * 1024
DEFAULT_ABI = "arm64-v8a"
ABI_ORDER = ("arm64-v8a", "armeabi-v7a", "x86_64")
_ASSET_RE = re.compile(r"^al-hisob-(arm64-v8a|armeabi-v7a|x86_64)\.apk$")


@dataclass(frozen=True)
class ApkAsset:
    abi: str
    name: str
    url: str
    size: int


@dataclass(frozen=True)
class Release:
    build: int
    version: str
    notes: str
    assets: dict[str, ApkAsset]

    @property
    def default(self) -> ApkAsset | None:
        return self.assets.get(DEFAULT_ABI) or next(iter(self.assets.values()), None)


class ReleaseSource(Protocol):
    async def latest(self) -> Release | None: ...

    async def download(self, asset: ApkAsset) -> bytes: ...


def parse_release(data: dict, repo: str) -> Release | None:
    """Разбирает ответ GitHub. Берутся только наши APK из этого репозитория."""
    m = re.fullmatch(r"build-(\d+)", str(data.get("tag_name") or ""))
    if not m:
        return None
    prefix = f"https://github.com/{repo}/releases/download/"
    assets: dict[str, ApkAsset] = {}
    for a in data.get("assets") or []:
        am = _ASSET_RE.match(str(a.get("name") or ""))
        url = str(a.get("browser_download_url") or "")
        if am and url.startswith(prefix) and a.get("state", "uploaded") == "uploaded":
            assets[am.group(1)] = ApkAsset(am.group(1), a["name"], url, int(a.get("size") or 0))
    if not assets:
        return None
    vm = re.search(r"Al-Hisob (\S+) \(", str(data.get("name") or ""))
    notes = " ".join(str(data.get("body") or "").split())[:300]
    return Release(build=int(m.group(1)), version=vm.group(1) if vm else "", notes=notes, assets=assets)


class GithubReleases:
    """Читает `releases/latest` (с кэшем на несколько минут) и скачивает файлы."""

    def __init__(self, repo: str, *, ttl: float = 300.0, transport: httpx.AsyncBaseTransport | None = None) -> None:
        self._repo = repo
        self._ttl = ttl
        self._transport = transport
        self._cached: tuple[float, Release | None] | None = None

    async def latest(self) -> Release | None:
        now = time.monotonic()
        if self._cached and now - self._cached[0] < self._ttl:
            return self._cached[1]
        try:
            async with httpx.AsyncClient(timeout=15.0, transport=self._transport) as client:
                r = await client.get(
                    f"https://api.github.com/repos/{self._repo}/releases/latest",
                    headers={"Accept": "application/vnd.github+json", "User-Agent": "al-hisob-bot"},
                )
            r.raise_for_status()
            release = parse_release(r.json(), self._repo)
        except (httpx.HTTPError, ValueError) as e:
            log.warning("github releases lookup failed: %s", type(e).__name__)
            return self._cached[1] if self._cached else None
        self._cached = (now, release)
        return release

    async def download(self, asset: ApkAsset) -> bytes:
        if not asset.url.startswith(f"https://github.com/{self._repo}/releases/download/"):
            raise ValueError("untrusted asset url")
        chunks: list[bytes] = []
        total = 0
        async with (
            httpx.AsyncClient(timeout=60.0, follow_redirects=True, transport=self._transport) as client,
            client.stream("GET", asset.url, headers={"User-Agent": "al-hisob-bot"}) as r,
        ):
            r.raise_for_status()
            async for chunk in r.aiter_bytes():
                total += len(chunk)
                if total > MAX_APK_BYTES:
                    raise ValueError("apk is too large")
                chunks.append(chunk)
        return b"".join(chunks)


class NullReleases:
    async def latest(self) -> Release | None:
        return None

    async def download(self, asset: ApkAsset) -> bytes:  # pragma: no cover
        raise ValueError("no releases")
