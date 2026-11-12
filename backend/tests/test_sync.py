from datetime import UTC, datetime, timedelta
from uuid import uuid4

from .conftest import auth, full_login

T0 = datetime(2026, 1, 1, 12, 0, tzinfo=UTC)


def change(*, id=None, entity="debtors", at=T0, data=None, deleted_at=None):
    return {
        "entity": entity,
        "id": str(id or uuid4()),
        "data": data if data is not None else {"name": "Ali"},
        "updated_at": at.isoformat(),
        "deleted_at": deleted_at.isoformat() if deleted_at else None,
    }


async def push(client, tokens, *changes):
    return await client.post("/v1/sync/push", json={"changes": list(changes)}, headers=auth(tokens))


async def pull(client, tokens, since=0, limit=500):
    return await client.get("/v1/sync/pull", params={"since": since, "limit": limit}, headers=auth(tokens))


class TestAuth:
    async def test_push_and_pull_require_login(self, client):
        assert (await client.post("/v1/sync/push", json={"changes": []})).status_code == 401
        assert (await client.get("/v1/sync/pull")).status_code == 401


class TestPushPull:
    async def test_round_trip(self, client):
        tokens = await full_login(client)
        c = change(data={"name": "Ali", "debt": 5})
        r = await push(client, tokens, c)
        assert r.status_code == 200
        assert r.json() == {"accepted": [c["id"]], "stale": []}

        r = await pull(client, tokens)
        body = r.json()
        assert body["has_more"] is False
        [got] = body["changes"]
        assert got["id"] == c["id"] and got["entity"] == "debtors"
        assert got["data"] == {"name": "Ali", "debt": 5}
        assert got["deleted_at"] is None
        assert body["cursor"] == got["seq"]

    async def test_pull_returns_only_what_is_new(self, client):
        tokens = await full_login(client)
        await push(client, tokens, change())
        cursor = (await pull(client, tokens)).json()["cursor"]
        assert (await pull(client, tokens, since=cursor)).json()["changes"] == []
        second = change(data={"name": "Vali"})
        await push(client, tokens, second)
        [got] = (await pull(client, tokens, since=cursor)).json()["changes"]
        assert got["id"] == second["id"]

    async def test_pull_pages(self, client):
        tokens = await full_login(client)
        await push(client, tokens, *[change(data={"n": i}) for i in range(5)])
        first = (await pull(client, tokens, limit=2)).json()
        assert len(first["changes"]) == 2 and first["has_more"] is True
        second = (await pull(client, tokens, since=first["cursor"], limit=2)).json()
        third = (await pull(client, tokens, since=second["cursor"], limit=2)).json()
        assert len(second["changes"]) == 2 and second["has_more"] is True
        assert len(third["changes"]) == 1 and third["has_more"] is False
        seen = [c["data"]["n"] for p in (first, second, third) for c in p["changes"]]
        assert sorted(seen) == [0, 1, 2, 3, 4]


class TestConflicts:
    async def test_newer_edit_wins(self, client):
        tokens = await full_login(client)
        c = change(data={"name": "old"})
        await push(client, tokens, c)
        newer = {**c, "data": {"name": "new"}, "updated_at": (T0 + timedelta(minutes=1)).isoformat()}
        assert (await push(client, tokens, newer)).json()["accepted"] == [c["id"]]
        [got] = (await pull(client, tokens)).json()["changes"]
        assert got["data"] == {"name": "new"}

    async def test_older_edit_is_stale_and_ignored(self, client):
        tokens = await full_login(client)
        c = change(data={"name": "new"}, at=T0 + timedelta(minutes=5))
        await push(client, tokens, c)
        older = {**c, "data": {"name": "old"}, "updated_at": T0.isoformat()}
        r = await push(client, tokens, older)
        assert r.json() == {"accepted": [], "stale": [c["id"]]}
        [got] = (await pull(client, tokens)).json()["changes"]
        assert got["data"] == {"name": "new"}

    async def test_resending_the_same_record_is_accepted_and_does_not_reappear(self, client):
        tokens = await full_login(client)
        c = change()
        await push(client, tokens, c)
        cursor = (await pull(client, tokens)).json()["cursor"]
        assert (await push(client, tokens, c)).json() == {"accepted": [c["id"]], "stale": []}
        assert (await pull(client, tokens, since=cursor)).json()["changes"] == []

    async def test_same_time_different_data_keeps_server_version(self, client):
        tokens = await full_login(client)
        c = change(data={"name": "A"})
        await push(client, tokens, c)
        r = await push(client, tokens, {**c, "data": {"name": "B"}})
        assert r.json()["stale"] == [c["id"]]

    async def test_delete_travels_as_soft_delete(self, client):
        tokens = await full_login(client)
        c = change()
        await push(client, tokens, c)
        gone = {**c, "updated_at": (T0 + timedelta(minutes=1)).isoformat(),
                "deleted_at": (T0 + timedelta(minutes=1)).isoformat()}
        await push(client, tokens, gone)
        [got] = (await pull(client, tokens)).json()["changes"]
        assert got["deleted_at"] is not None

    async def test_future_timestamps_are_clamped(self, client):
        tokens = await full_login(client)
        c = change(at=datetime.now(UTC) + timedelta(days=365))
        await push(client, tokens, c)
        [got] = (await pull(client, tokens)).json()["changes"]
        stored = datetime.fromisoformat(got["updated_at"].replace("Z", "+00:00"))
        assert stored < datetime.now(UTC) + timedelta(minutes=11)
        # настоящая правка позже побеждает «будущую»
        real = {**c, "data": {"name": "real"}, "updated_at": (datetime.now(UTC) + timedelta(minutes=20)).isoformat()}
        assert (await push(client, tokens, real)).json()["accepted"] == [c["id"]]


class TestIsolationAndLimits:
    async def test_users_do_not_see_each_other(self, client):
        a = await full_login(client, user_id=111, phone="998901111111")
        b = await full_login(client, user_id=222, phone="998902222222")
        await push(client, a, change(data={"name": "secret"}))
        assert (await pull(client, b)).json()["changes"] == []
        assert len((await pull(client, a)).json()["changes"]) == 1

    async def test_same_id_for_two_users_does_not_collide(self, client):
        a = await full_login(client, user_id=111, phone="998901111111")
        b = await full_login(client, user_id=222, phone="998902222222")
        shared = str(uuid4())
        await push(client, a, change(id=shared, data={"name": "A"}))
        await push(client, b, change(id=shared, data={"name": "B"}))
        assert (await pull(client, a)).json()["changes"][0]["data"] == {"name": "A"}
        assert (await pull(client, b)).json()["changes"][0]["data"] == {"name": "B"}

    async def test_unknown_entity_is_rejected_entirely(self, client):
        tokens = await full_login(client)
        r = await push(client, tokens, change(), change(entity="users"))
        assert r.status_code == 422
        assert (await pull(client, tokens)).json()["changes"] == []

    async def test_bad_id_and_oversized_record(self, client):
        tokens = await full_login(client)
        bad = {**change(), "id": "not-a-uuid"}
        assert (await push(client, tokens, bad)).status_code == 422
        big = change(data={"note": "x" * 70_000})
        assert (await push(client, tokens, big)).status_code == 413

    async def test_too_many_changes(self, client):
        tokens = await full_login(client)
        r = await push(client, tokens, *[change() for _ in range(501)])
        assert r.status_code == 422

    async def test_removing_the_user_removes_their_records(self, client, pool):
        tokens = await full_login(client)
        await push(client, tokens, change())
        await pool.execute("delete from users")
        assert await pool.fetchval("select count(*) from sync_records") == 0
