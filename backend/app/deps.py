from dataclasses import dataclass
from typing import Any
from uuid import UUID

from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.auth import service
from app.security import InvalidToken, decode_access_token

_bearer = HTTPBearer(auto_error=False)


@dataclass
class CurrentUser:
    id: UUID
    session_id: UUID
    data: dict[str, Any]


async def current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> CurrentUser:
    unauthorized = HTTPException(status_code=401, detail={"code": "unauthorized"},
                                 headers={"WWW-Authenticate": "Bearer"})
    if credentials is None:
        raise unauthorized
    try:
        user_id, session_id = decode_access_token(
            credentials.credentials, secret=request.app.state.settings.jwt_secret
        )
    except InvalidToken:
        raise unauthorized from None
    data = await service.load_active_user(request.app.state.pool, user_id, session_id)
    if data is None:
        raise unauthorized
    return CurrentUser(user_id, session_id, data)
