from uuid import UUID

from pydantic import BaseModel, Field


class StartRequest(BaseModel):
    device_name: str | None = Field(default=None, max_length=80)


class StartResponse(BaseModel):
    request_id: UUID
    poll_secret: str
    bot_url: str
    expires_in: int


class PollRequest(BaseModel):
    request_id: UUID
    poll_secret: str = Field(min_length=10, max_length=200)


class UserOut(BaseModel):
    id: UUID
    phone: str
    name: str | None = None


class PollResponse(BaseModel):
    status: str  # pending | ok
    access_token: str | None = None
    refresh_token: str | None = None
    expires_in: int | None = None
    user: UserOut | None = None


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=10, max_length=300)


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    expires_in: int
    user: UserOut
