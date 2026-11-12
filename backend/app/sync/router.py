import json
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from app.deps import CurrentUser, current_user
from app.ratelimit import SlidingWindowLimiter, limit_dependency

# Таблицы приложения, которые можно синхронизировать. Остальное сервер не принимает.
ENTITIES = frozenset(
    {
        "shop_profiles",
        "debtors",
        "debtor_phones",
        "debt_transactions",
        "sms_templates",
        "sms_logs",
        "products",
        "product_photos",
        "orders",
        "order_items",
        "order_status_history",
    }
)
MAX_CHANGES_PER_PUSH = 500
MAX_RECORD_BYTES = 64 * 1024
# Часы устройства могут спешить: время правки из будущего ограничиваем, иначе такая запись победит навсегда.
MAX_CLOCK_AHEAD = timedelta(minutes=10)


class Change(BaseModel):
    entity: str
    id: UUID
    data: dict[str, Any]
    updated_at: datetime
    deleted_at: datetime | None = None


class PushRequest(BaseModel):
    changes: list[Change] = Field(max_length=MAX_CHANGES_PER_PUSH)


class PushResponse(BaseModel):
    accepted: list[UUID]  # записи сохранены (или уже были такими же)
    stale: list[UUID]     # на сервере версия новее: клиент получит её при следующем получении изменений


class PulledChange(BaseModel):
    entity: str
    id: UUID
    data: dict[str, Any]
    updated_at: datetime
    deleted_at: datetime | None
    seq: int


class PullResponse(BaseModel):
    changes: list[PulledChange]
    cursor: int
    has_more: bool


def _aware(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=UTC)


_UPSERT = """
insert into sync_records (user_id, entity, id, data, updated_at, deleted_at)
values ($1, $2, $3, $4::jsonb, $5, $6)
on conflict (user_id, entity, id) do update
   set data = excluded.data,
       updated_at = excluded.updated_at,
       deleted_at = excluded.deleted_at,
       seq = nextval('sync_seq')
 where sync_records.updated_at < excluded.updated_at
returning 1
"""


def build_router(settings) -> APIRouter:
    router = APIRouter(prefix="/v1/sync")
    limit = limit_dependency(
        SlidingWindowLimiter(settings.rate_limit_sync_per_minute), trust_proxy=settings.trust_proxy
    )

    @router.post("/push", response_model=PushResponse, dependencies=[Depends(limit)])
    async def push(body: PushRequest, request: Request, user: CurrentUser = Depends(current_user)) -> PushResponse:
        latest_allowed = datetime.now(UTC) + MAX_CLOCK_AHEAD
        prepared: list[tuple[Change, str, datetime, datetime | None]] = []
        for change in body.changes:
            if change.entity not in ENTITIES:
                raise HTTPException(status_code=422, detail={"code": "unknown_entity"})
            payload = json.dumps(change.data, ensure_ascii=False, separators=(",", ":"))
            if len(payload.encode()) > MAX_RECORD_BYTES:
                raise HTTPException(status_code=413, detail={"code": "record_too_large"})
            updated = min(_aware(change.updated_at), latest_allowed)
            deleted = min(_aware(change.deleted_at), latest_allowed) if change.deleted_at else None
            prepared.append((change, payload, updated, deleted))

        accepted: list[UUID] = []
        stale: list[UUID] = []
        async with request.app.state.pool.acquire() as conn, conn.transaction():
            for change, payload, updated, deleted in prepared:
                args = (user.id, change.entity, change.id, payload, updated, deleted)
                if await conn.fetchval(_UPSERT, *args):
                    accepted.append(change.id)
                    continue
                # Версия на сервере не старше. Повтор той же записи (ответ потерялся) — не конфликт.
                same = await conn.fetchval(
                    "select updated_at = $4 and data = $5::jsonb and deleted_at is not distinct from $6 "
                    "from sync_records where user_id = $1 and entity = $2 and id = $3",
                    user.id, change.entity, change.id, updated, payload, deleted,
                )
                (accepted if same else stale).append(change.id)
        return PushResponse(accepted=accepted, stale=stale)

    @router.get("/pull", response_model=PullResponse, dependencies=[Depends(limit)])
    async def pull(
        request: Request,
        since: int = Query(default=0, ge=0),
        limit_: int = Query(default=500, ge=1, le=1000, alias="limit"),
        user: CurrentUser = Depends(current_user),
    ) -> PullResponse:
        rows = await request.app.state.pool.fetch(
            "select entity, id, data, updated_at, deleted_at, seq from sync_records "
            "where user_id = $1 and seq > $2 order by seq limit $3",
            user.id, since, limit_ + 1,
        )
        has_more = len(rows) > limit_
        rows = rows[:limit_]
        changes = [
            PulledChange(
                entity=r["entity"], id=r["id"], data=json.loads(r["data"]),
                updated_at=r["updated_at"], deleted_at=r["deleted_at"], seq=r["seq"],
            )
            for r in rows
        ]
        return PullResponse(changes=changes, cursor=rows[-1]["seq"] if rows else since, has_more=has_more)

    return router
