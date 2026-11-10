import time
from collections import defaultdict, deque

from fastapi import HTTPException, Request


class SlidingWindowLimiter:
    """Простое ограничение частоты в памяти процесса: не больше `limit` за `window` секунд на ключ.

    Достаточно для одного экземпляра API за nginx. При нескольких экземплярах лимит
    действует на каждый отдельно — для защиты от перебора этого хватает.
    """

    def __init__(self, limit: int, window: float = 60.0, *, clock=time.monotonic) -> None:
        self.limit = limit
        self.window = window
        self._clock = clock
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    def allow(self, key: str) -> bool:
        now = self._clock()
        hits = self._hits[key]
        while hits and hits[0] <= now - self.window:
            hits.popleft()
        if len(hits) >= self.limit:
            return False
        hits.append(now)
        # Не копим пустые ключи
        if len(self._hits) > 10_000:
            self._hits = defaultdict(deque, {k: v for k, v in self._hits.items() if v})
        return True

    def retry_after(self, key: str) -> int:
        hits = self._hits.get(key)
        if not hits:
            return 0
        return max(1, int(hits[0] + self.window - self._clock()) + 1)


def client_ip(request: Request, *, trust_proxy: bool) -> str:
    if trust_proxy:
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def limit_dependency(limiter: SlidingWindowLimiter, *, trust_proxy: bool):
    async def dependency(request: Request) -> None:
        key = client_ip(request, trust_proxy=trust_proxy)
        if not limiter.allow(key):
            raise HTTPException(
                status_code=429,
                detail={"code": "rate_limited"},
                headers={"Retry-After": str(limiter.retry_after(key))},
            )

    return dependency
