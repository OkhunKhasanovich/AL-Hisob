from fastapi import APIRouter, Depends, HTTPException, Request

from app.auth import service
from app.deps import CurrentUser, current_user
from app.ratelimit import SlidingWindowLimiter, limit_dependency
from app.schemas import (
    PollRequest,
    PollResponse,
    RefreshRequest,
    StartRequest,
    StartResponse,
    TokenResponse,
    UserOut,
)


def build_router(settings) -> APIRouter:
    router = APIRouter(prefix="/v1")
    trust = settings.trust_proxy
    start_limit = limit_dependency(SlidingWindowLimiter(settings.rate_limit_start_per_minute), trust_proxy=trust)
    poll_limit = limit_dependency(SlidingWindowLimiter(settings.rate_limit_poll_per_minute), trust_proxy=trust)
    refresh_limit = limit_dependency(SlidingWindowLimiter(settings.rate_limit_refresh_per_minute), trust_proxy=trust)

    def raise_auth(e: service.AuthError):
        raise HTTPException(status_code=e.status, detail={"code": e.code}) from None

    @router.post("/auth/telegram/start", response_model=StartResponse, dependencies=[Depends(start_limit)])
    async def start(body: StartRequest, request: Request) -> StartResponse:
        if not settings.telegram_bot_username:
            raise HTTPException(status_code=503, detail={"code": "bot_not_configured"})
        started = await service.start_login(request.app.state.pool, settings, device_name=body.device_name)
        return StartResponse(
            request_id=started.request_id,
            poll_secret=started.poll_secret,
            bot_url=f"https://t.me/{settings.telegram_bot_username}?start={started.start_token}",
            expires_in=started.expires_in,
        )

    @router.post("/auth/telegram/poll", response_model=PollResponse, dependencies=[Depends(poll_limit)])
    async def poll(body: PollRequest, request: Request) -> PollResponse:
        try:
            tokens = await service.poll_login(
                request.app.state.pool, settings, request_id=body.request_id, poll_secret=body.poll_secret
            )
        except service.AuthError as e:
            raise_auth(e)
        if tokens is None:
            return PollResponse(status="pending")
        return PollResponse(
            status="ok",
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            expires_in=tokens.expires_in,
            user=UserOut(**tokens.user),
        )

    @router.post("/auth/refresh", response_model=TokenResponse, dependencies=[Depends(refresh_limit)])
    async def refresh(body: RefreshRequest, request: Request) -> TokenResponse:
        try:
            tokens = await service.refresh_session(
                request.app.state.pool, settings, refresh_token=body.refresh_token
            )
        except service.AuthError as e:
            raise_auth(e)
        return TokenResponse(
            access_token=tokens.access_token,
            refresh_token=tokens.refresh_token,
            expires_in=tokens.expires_in,
            user=UserOut(**tokens.user),
        )

    @router.post("/auth/logout", status_code=204)
    async def logout(request: Request, user: CurrentUser = Depends(current_user)) -> None:
        await service.logout_session(request.app.state.pool, user.session_id)

    @router.get("/me", response_model=UserOut)
    async def me(user: CurrentUser = Depends(current_user)) -> UserOut:
        return UserOut(**user.data)

    return router
