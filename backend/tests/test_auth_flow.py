import asyncio
from datetime import UTC, datetime, timedelta

from app.security import create_access_token, hash_token

from .conftest import (
    WEBHOOK_SECRET,
    approve_via_bot,
    auth,
    bot_update,
    full_login,
    poll,
    post_update,
    start_login,
    token_from,
)


class TestStart:
    async def test_returns_link_to_bot_and_secrets(self, client):
        start = await start_login(client)
        assert start["bot_url"].startswith("https://t.me/TestBot?start=")
        assert len(token_from(start["bot_url"])) >= 30
        assert len(start["poll_secret"]) >= 30
        assert start["expires_in"] == 600
        # request_id — UUID
        assert len(start["request_id"]) == 36

    async def test_secrets_are_stored_only_as_hashes(self, client, pool):
        start = await start_login(client)
        row = await pool.fetchrow("select * from login_requests")
        token = token_from(start["bot_url"])
        assert row["start_token_hash"] == hash_token(token)
        assert row["poll_secret_hash"] == hash_token(start["poll_secret"])
        dump = " ".join(str(v) for v in row.values())
        assert token not in dump and start["poll_secret"] not in dump

    async def test_each_start_is_unique(self, client):
        a, b = await start_login(client), await start_login(client)
        assert a["request_id"] != b["request_id"]
        assert token_from(a["bot_url"]) != token_from(b["bot_url"])

    async def test_bot_not_configured(self, settings, telegram):
        import httpx

        from app.main import create_app

        app = create_app(settings.model_copy(update={"telegram_bot_username": ""}), telegram=telegram)
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
                r = await c.post("/v1/auth/telegram/start", json={})
                assert r.status_code == 503
                assert r.json()["detail"]["code"] == "bot_not_configured"

    async def test_long_device_name_is_cut(self, client, pool):
        r = await client.post("/v1/auth/telegram/start", json={"device_name": "x" * 80})
        assert r.status_code == 200
        r = await client.post("/v1/auth/telegram/start", json={"device_name": "x" * 81})
        assert r.status_code == 422

    async def test_expired_requests_are_cleaned_up(self, client, pool):
        await start_login(client)
        await pool.execute("update login_requests set expires_at = now() - interval '2 days'")
        await start_login(client)
        assert await pool.fetchval("select count(*) from login_requests") == 1


class TestLoginViaBot:
    async def test_full_flow(self, client, telegram):
        start = await start_login(client)

        r = await poll(client, start)
        assert r.status_code == 200 and r.json() == {
            "status": "pending", "access_token": None, "refresh_token": None, "expires_in": None, "user": None,
        }

        # /start <токен> → бот просит поделиться номером кнопкой
        await post_update(client, bot_update(text=f"/start {token_from(start['bot_url'])}"))
        assert "номер" in telegram.last["text"]
        button = telegram.last["reply_markup"]["keyboard"][0][0]
        assert button["request_contact"] is True

        # номер подтверждён → бот сообщает «готово»
        await post_update(client, bot_update(contact={"phone_number": "998901234567", "user_id": 111}))
        assert "Готово" in telegram.last["text"]
        assert telegram.last["reply_markup"] == {"remove_keyboard": True}

        r = await poll(client, start)
        body = r.json()
        assert body["status"] == "ok"
        assert body["user"]["phone"] == "+998901234567"
        assert body["user"]["name"] == "Ali"
        assert body["expires_in"] == 900
        assert len(body["refresh_token"]) > 40

    async def test_tokens_are_issued_exactly_once(self, client):
        start = await start_login(client)
        await approve_via_bot(client, start)
        first = await poll(client, start)
        assert first.json()["status"] == "ok"
        second = await poll(client, start)
        assert second.status_code == 410
        assert second.json()["detail"]["code"] == "already_used"

    async def test_parallel_polls_issue_tokens_once(self, client, pool):
        start = await start_login(client)
        await approve_via_bot(client, start)
        responses = await asyncio.gather(*[poll(client, start) for _ in range(6)])
        codes = sorted(r.status_code for r in responses)
        assert codes == [200, 410, 410, 410, 410, 410]
        assert await pool.fetchval("select count(*) from sessions") == 1

    async def test_phone_is_normalized_and_user_reused(self, client, pool):
        a = await full_login(client, user_id=111, phone="+998 90 123 45 67")
        b = await full_login(client, user_id=111, phone="998901234567")
        assert a["user"]["id"] == b["user"]["id"]
        assert await pool.fetchval("select count(*) from users") == 1
        assert await pool.fetchval("select count(*) from sessions") == 2, "у каждого входа своя сессия"

    async def test_different_phones_are_different_users(self, client):
        a = await full_login(client, user_id=111, phone="998901111111")
        b = await full_login(client, user_id=222, phone="998902222222")
        assert a["user"]["id"] != b["user"]["id"]

    async def test_someone_elses_contact_is_rejected(self, client, telegram):
        start = await start_login(client)
        await post_update(client, bot_update(user_id=111, text=f"/start {token_from(start['bot_url'])}"))
        # Пользователь 111 пересылает контакт другого человека (user_id другой)
        await post_update(client, bot_update(user_id=111, contact={"phone_number": "998909999999", "user_id": 999}))
        assert "собственный" in telegram.last["text"]
        assert (await poll(client, start)).json()["status"] == "pending"

    async def test_contact_without_user_id_is_rejected(self, client, telegram):
        start = await start_login(client)
        await post_update(client, bot_update(text=f"/start {token_from(start['bot_url'])}"))
        await post_update(client, bot_update(contact={"phone_number": "998901234567"}))
        assert (await poll(client, start)).json()["status"] == "pending"

    async def test_contact_with_garbage_number_is_rejected(self, client):
        start = await start_login(client)
        await post_update(client, bot_update(text=f"/start {token_from(start['bot_url'])}"))
        await post_update(client, bot_update(contact={"phone_number": "12", "user_id": 111}))
        assert (await poll(client, start)).json()["status"] == "pending"

    async def test_contact_without_pending_request(self, client, telegram):
        await post_update(client, bot_update(contact={"phone_number": "998901234567", "user_id": 111}))
        assert "Нет ожидающего входа" in telegram.last["text"]

    async def test_contact_cannot_approve_someone_elses_request(self, client):
        """Запрос привязан к тому, кто нажал /start; другой пользователь его подтвердить не может."""
        start = await start_login(client)
        await post_update(client, bot_update(user_id=111, text=f"/start {token_from(start['bot_url'])}"))
        await post_update(client, bot_update(user_id=222, contact={"phone_number": "998902222222", "user_id": 222}))
        assert (await poll(client, start)).json()["status"] == "pending"

    async def test_unknown_start_token(self, client, telegram):
        await post_update(client, bot_update(text="/start nope-nope-nope"))
        assert "устарела" in telegram.last["text"]

    async def test_start_token_cannot_be_reused_after_login(self, client, telegram):
        start = await start_login(client)
        await approve_via_bot(client, start)
        await poll(client, start)
        await post_update(client, bot_update(user_id=222, text=f"/start {token_from(start['bot_url'])}"))
        assert "устарела" in telegram.last["text"]

    async def test_start_without_payload_shows_help(self, client, telegram):
        await post_update(client, bot_update(text="/start"))
        assert "бот для входа" in telegram.last["text"]

    async def test_other_messages_get_help(self, client, telegram):
        await post_update(client, bot_update(text="привет"))
        assert "бот для входа" in telegram.last["text"]

    async def test_bot_speaks_user_language(self, client, telegram):
        start = await start_login(client)
        await post_update(client, bot_update(text=f"/start {token_from(start['bot_url'])}", lang="uz"))
        assert "telefon raqamingizni" in telegram.last["text"]
        await post_update(client, bot_update(text="x", lang="en-US"))
        assert "sign-in bot" in telegram.last["text"]
        await post_update(client, bot_update(text="x", lang="de"))
        assert "бот для входа" in telegram.last["text"], "неизвестный язык → русский"
        await post_update(client, bot_update(text="x", lang=None))
        assert "бот для входа" in telegram.last["text"]

    async def test_latest_pending_request_of_the_user_is_approved(self, client):
        old = await start_login(client)
        new = await start_login(client)
        await post_update(client, bot_update(text=f"/start {token_from(old['bot_url'])}"))
        await post_update(client, bot_update(text=f"/start {token_from(new['bot_url'])}"))
        await post_update(client, bot_update(contact={"phone_number": "998901234567", "user_id": 111}))
        assert (await poll(client, new)).json()["status"] == "ok"


class TestPollSecurity:
    async def test_wrong_secret(self, client):
        start = await start_login(client)
        await approve_via_bot(client, start)
        r = await client.post("/v1/auth/telegram/poll",
                              json={"request_id": start["request_id"], "poll_secret": "x" * 43})
        assert r.status_code == 404
        # настоящий секрет по-прежнему работает: неверная попытка ничего не сожгла
        assert (await poll(client, start)).json()["status"] == "ok"

    async def test_unknown_request(self, client):
        r = await client.post("/v1/auth/telegram/poll",
                              json={"request_id": "00000000-0000-0000-0000-000000000000", "poll_secret": "x" * 43})
        assert r.status_code == 404

    async def test_start_token_is_not_a_poll_secret(self, client):
        """Тот, кто увидел ссылку на бота, не может забрать токены вместо приложения."""
        start = await start_login(client)
        await approve_via_bot(client, start)
        r = await client.post("/v1/auth/telegram/poll",
                              json={"request_id": start["request_id"], "poll_secret": token_from(start["bot_url"])})
        assert r.status_code == 404

    async def test_malformed_input(self, client):
        for body in [{}, {"request_id": "not-a-uuid", "poll_secret": "x" * 20}, {"request_id": None}]:
            assert (await client.post("/v1/auth/telegram/poll", json=body)).status_code == 422

    async def test_pending_request_expires(self, client, pool):
        start = await start_login(client)
        await pool.execute("update login_requests set expires_at = now() - interval '1 second'")
        r = await poll(client, start)
        assert r.status_code == 410 and r.json()["detail"]["code"] == "expired"

    async def test_expired_request_cannot_be_started_in_bot(self, client, pool, telegram):
        start = await start_login(client)
        await pool.execute("update login_requests set expires_at = now() - interval '1 second'")
        await post_update(client, bot_update(text=f"/start {token_from(start['bot_url'])}"))
        assert "устарела" in telegram.last["text"]

    async def test_approved_but_expired_gives_no_tokens(self, client, pool):
        start = await start_login(client)
        await approve_via_bot(client, start)
        await pool.execute("update login_requests set expires_at = now() - interval '1 second'")
        assert (await poll(client, start)).status_code == 410
        assert await pool.fetchval("select count(*) from sessions") == 0


class TestWebhookSecurity:
    async def test_wrong_secret_is_forbidden(self, client, telegram):
        r = await post_update(client, bot_update(text="/start x"), secret="wrong-secret-wrong-secret")
        assert r.status_code == 403
        assert telegram.sent == []

    async def test_missing_secret_is_forbidden(self, client):
        assert (await post_update(client, bot_update(text="/start x"), secret=None)).status_code == 403

    async def test_not_configured_secret_rejects_everything(self, settings, telegram):
        import httpx

        from app.main import create_app

        app = create_app(settings.model_copy(update={"telegram_webhook_secret": ""}), telegram=telegram)
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
                r = await c.post("/telegram/webhook", json={}, headers={"X-Telegram-Bot-Api-Secret-Token": ""})
                assert r.status_code == 403

    async def test_bad_json(self, client):
        r = await client.post("/telegram/webhook", content=b"{oops",
                              headers={"X-Telegram-Bot-Api-Secret-Token": WEBHOOK_SECRET,
                                       "Content-Type": "application/json"})
        assert r.status_code == 400

    async def test_non_message_updates_are_ignored(self, client, telegram):
        for update in [{"update_id": 1}, {"update_id": 2, "edited_message": {}}, {"message": "str"},
                       {"message": {"from": {"id": "nan"}, "chat": {"id": 1}}}]:
            assert (await post_update(client, update)).status_code == 200
        assert telegram.sent == []

    async def test_telegram_failure_does_not_break_the_webhook(self, client, app):
        class Broken:
            async def send_message(self, *a, **k):
                raise RuntimeError("telegram is down")

        app.state.telegram = Broken()
        r = await post_update(client, bot_update(text="/start"))
        assert r.status_code == 200, "Telegram не должен повторять запрос из-за нашей ошибки"


class TestSessions:
    async def test_me_with_access_token(self, client):
        tokens = await full_login(client)
        r = await client.get("/v1/me", headers=auth(tokens))
        assert r.status_code == 200
        assert r.json()["phone"] == "+998901234567"

    async def test_missing_or_bad_token(self, client):
        assert (await client.get("/v1/me")).status_code == 401
        assert (await client.get("/v1/me", headers={"Authorization": "Bearer garbage"})).status_code == 401
        assert (await client.get("/v1/me", headers={"Authorization": "Basic abc"})).status_code == 401

    async def test_expired_access_token(self, client, settings):
        tokens = await full_login(client)
        from app.security import decode_access_token

        uid, sid = decode_access_token(tokens["access_token"], secret=settings.jwt_secret)
        expired = create_access_token(secret=settings.jwt_secret, user_id=uid, session_id=sid, ttl_minutes=1,
                                      now=datetime.now(UTC) - timedelta(hours=1))
        r = await client.get("/v1/me", headers={"Authorization": f"Bearer {expired}"})
        assert r.status_code == 401

    async def test_token_for_unknown_session(self, client, settings):
        from uuid import uuid4

        forged = create_access_token(secret=settings.jwt_secret, user_id=uuid4(), session_id=uuid4(), ttl_minutes=5)
        assert (await client.get("/v1/me", headers={"Authorization": f"Bearer {forged}"})).status_code == 401

    async def test_logout_revokes_the_session(self, client):
        tokens = await full_login(client)
        assert (await client.post("/v1/auth/logout", headers=auth(tokens))).status_code == 204
        assert (await client.get("/v1/me", headers=auth(tokens))).status_code == 401
        r = await client.post("/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
        assert r.status_code == 401

    async def test_logout_requires_auth(self, client):
        assert (await client.post("/v1/auth/logout")).status_code == 401

    async def test_logout_only_affects_own_session(self, client):
        a = await full_login(client, user_id=111, phone="998901111111")
        b = await full_login(client, user_id=111, phone="998901111111")
        await client.post("/v1/auth/logout", headers=auth(a))
        assert (await client.get("/v1/me", headers=auth(a))).status_code == 401
        assert (await client.get("/v1/me", headers=auth(b))).status_code == 200

    async def test_expired_session_is_rejected(self, client, pool):
        tokens = await full_login(client)
        await pool.execute("update sessions set expires_at = now() - interval '1 second'")
        assert (await client.get("/v1/me", headers=auth(tokens))).status_code == 401
        r = await client.post("/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
        assert r.status_code == 401


class TestRefresh:
    async def refresh(self, client, token):
        return await client.post("/v1/auth/refresh", json={"refresh_token": token})

    async def test_rotation_gives_new_working_pair(self, client):
        tokens = await full_login(client)
        r = await self.refresh(client, tokens["refresh_token"])
        assert r.status_code == 200
        new = r.json()
        assert new["refresh_token"] != tokens["refresh_token"]
        assert new["user"]["phone"] == "+998901234567"
        assert (await client.get("/v1/me", headers=auth(new))).status_code == 200

    async def test_chain_of_refreshes(self, client):
        token = (await full_login(client))["refresh_token"]
        for _ in range(4):
            r = await self.refresh(client, token)
            assert r.status_code == 200
            token = r.json()["refresh_token"]

    async def test_unknown_token(self, client):
        assert (await self.refresh(client, "x" * 64)).status_code == 401

    async def test_malformed(self, client):
        assert (await client.post("/v1/auth/refresh", json={})).status_code == 422
        assert (await client.post("/v1/auth/refresh", json={"refresh_token": "short"})).status_code == 422

    async def test_retry_inside_grace_window_succeeds(self, client):
        """Ответ потерялся по дороге: повтор со старым токеном сразу после обмена допустим."""
        tokens = await full_login(client)
        first = await self.refresh(client, tokens["refresh_token"])
        retry = await self.refresh(client, tokens["refresh_token"])
        assert first.status_code == 200 and retry.status_code == 200
        assert retry.json()["refresh_token"] not in (tokens["refresh_token"], first.json()["refresh_token"])

    async def test_reuse_after_grace_revokes_whole_session(self, client, pool):
        tokens = await full_login(client)
        rotated = (await self.refresh(client, tokens["refresh_token"])).json()
        await pool.execute("update sessions set rotated_at = now() - interval '5 minutes'")

        stolen = await self.refresh(client, tokens["refresh_token"])
        assert stolen.status_code == 401
        assert stolen.json()["detail"]["code"] == "refresh_reused"

        # настоящий владелец тоже потерял сессию: безопаснее войти заново
        assert (await self.refresh(client, rotated["refresh_token"])).status_code == 401
        assert (await client.get("/v1/me", headers=auth(rotated))).status_code == 401

    async def test_refresh_does_not_affect_other_sessions(self, client, pool):
        a = await full_login(client, user_id=111)
        b = await full_login(client, user_id=111)
        await self.refresh(client, a["refresh_token"])
        await pool.execute("update sessions set rotated_at = now() - interval '5 minutes' where rotated_at is not null")
        await self.refresh(client, a["refresh_token"])  # кража сессии A
        assert (await client.get("/v1/me", headers=auth(b))).status_code == 200

    async def test_revoked_session_cannot_refresh(self, client, pool):
        tokens = await full_login(client)
        await pool.execute("update sessions set revoked_at = now()")
        assert (await self.refresh(client, tokens["refresh_token"])).status_code == 401

    async def test_refresh_token_is_stored_only_as_hash(self, client, pool):
        tokens = await full_login(client)
        row = await pool.fetchrow("select * from sessions")
        assert row["refresh_hash"] == hash_token(tokens["refresh_token"])
        assert tokens["refresh_token"] not in " ".join(str(v) for v in row.values())

    async def test_access_token_is_not_a_refresh_token(self, client):
        tokens = await full_login(client)
        assert (await self.refresh(client, tokens["access_token"])).status_code == 401
