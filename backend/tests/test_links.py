from .conftest import approve_via_bot, bot_update, post_update, start_login, token_from

FINGERPRINT = "DC:2F:1C:E5:36:E3:9E:F4:20:71:9F:2E:17:C6:35:84:88:74:5E:E2:A9:A6:7E:6D:C8:D0:F3:1D:15:C3:CC:BE"


class TestOpenPage:
    async def test_page_launches_the_app_through_an_intent(self, client):
        r = await client.get("/open")
        assert r.status_code == 200
        assert r.headers["content-type"].startswith("text/html")
        assert r.headers["cache-control"] == "no-store"
        assert "intent://open#Intent;scheme=alhisob;package=uz.alhisob.app;" in r.text
        assert "S.browser_fallback_url=https%3A%2F%2Fgithub.com" in r.text, "без приложения — на скачивание"

    async def test_page_language_follows_the_browser(self, client):
        assert "Ilovani ochish" in (await client.get("/open", headers={"Accept-Language": "uz-UZ,uz;q=0.9"})).text
        assert "Open the app" in (await client.get("/open", headers={"Accept-Language": "en-US"})).text
        assert "Открыть приложение" in (await client.get("/open", headers={"Accept-Language": "de"})).text


class TestAssetLinks:
    async def test_app_links_file_names_the_app_and_its_certificate(self, client):
        r = await client.get("/.well-known/assetlinks.json")
        assert r.status_code == 200
        assert r.headers["content-type"].startswith("application/json")
        [entry] = r.json()
        assert entry["relation"] == ["delegate_permission/common.handle_all_urls"]
        assert entry["target"] == {
            "namespace": "android_app",
            "package_name": "uz.alhisob.app",
            "sha256_cert_fingerprints": [FINGERPRINT],
        }

    async def test_without_a_configured_fingerprint_the_list_is_empty(self, settings):
        import httpx

        from app.main import create_app

        app = create_app(settings.model_copy(update={"android_cert_sha256": ""}))
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as c:
                assert (await c.get("/.well-known/assetlinks.json")).json() == []


class TestBotButton:
    async def test_done_message_has_an_open_button_in_the_users_language(self, client, telegram):
        for lang, label in [("ru", "📲 Открыть Al-Hisob"), ("uz", "📲 Al-Hisob’ni ochish"), ("en", "📲 Open Al-Hisob")]:
            start = await start_login(client)
            await post_update(client, bot_update(text=f"/start {token_from(start['bot_url'])}", lang=lang))
            await post_update(
                client, bot_update(contact={"phone_number": "998901234567", "user_id": 111}, lang=lang)
            )
            assert telegram.last["reply_markup"] == {
                "inline_keyboard": [[{"text": label, "url": "https://api.test/open"}]]
            }

    async def test_no_button_when_the_public_address_is_not_https(self, settings, telegram):
        import httpx

        from app.main import create_app

        app = create_app(settings.model_copy(update={"public_base_url": "http://localhost:8000"}), telegram=telegram)
        async with app.router.lifespan_context(app):
            await app.state.pool.execute("truncate users, login_requests, sessions cascade")
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as c:
                start = await start_login(c)
                await approve_via_bot(c, start)
        # Telegram не принимает такие ссылки в кнопках: остаётся обычное «готово» без кнопки-ссылки.
        assert telegram.last["reply_markup"] == {"remove_keyboard": True}

    async def test_unapproved_contact_gets_no_button(self, client, telegram):
        await post_update(client, bot_update(contact={"phone_number": "998901234567", "user_id": 111}))
        assert telegram.last["reply_markup"] == {"remove_keyboard": True}
