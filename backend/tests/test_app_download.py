import httpx

from app.telegram.client import HttpTelegramClient, TelegramError
from app.telegram.releases import GithubReleases, parse_release

from .conftest import bot_update, post_update

REPO = "OkhunKhasanovich/AL-Hisob"
BASE = f"https://github.com/{REPO}/releases/download/build-54/"


def release_json(**over):
    data = {
        "tag_name": "build-54",
        "name": "Al-Hisob 0.1.0 (54)",
        "body": "feat: something\n\nCo-Authored-By: x",
        "assets": [
            {"name": f"al-hisob-{abi}.apk", "browser_download_url": BASE + f"al-hisob-{abi}.apk",
             "size": 1000, "state": "uploaded"}
            for abi in ("arm64-v8a", "armeabi-v7a", "x86_64")
        ],
    }
    data.update(over)
    return data


async def ask(client, text="/app", *, user=111, lang="ru"):
    return await post_update(client, bot_update(user_id=user, text=text, lang=lang))


class TestAppCommand:
    async def test_sends_the_latest_arm64_file_with_a_caption_and_other_versions(self, client, telegram, releases):
        r = await ask(client)
        assert r.status_code == 200

        assert "Отправляю" in telegram.sent[0]["text"]
        [doc] = telegram.documents
        assert doc["document"] == ("al-hisob-arm64-v8a.apk", b"APK-BYTES-arm64-v8a")
        assert "сборка 54" in doc["caption"] and "something new" in doc["caption"]
        buttons = [b for row in doc["reply_markup"]["inline_keyboard"] for b in row]
        assert [b["text"] for b in buttons] == ["ARMv7 (32-bit)", "x86_64"]
        assert all(b["url"].startswith("https://github.com/") for b in buttons)

    async def test_works_for_all_command_forms(self, client, telegram, settings):
        for text in ["/app", "/APP", "/apk", "/app@AlHisobot", "app", "/download please"]:
            telegram.documents.clear()
            await ask(client, text, user=hash(text) % 10000 + 1)
            assert len(telegram.documents) == 1, text

    async def test_second_request_uses_the_cached_file_id_without_downloading(self, client, telegram, releases, app):
        app.state.delivery._cooldown = 0
        await ask(client)
        await ask(client, user=222)
        assert releases.downloads == 1, "файл скачан с GitHub один раз"
        assert telegram.documents[1]["document"] == "file-id-1", "второй раз — по file_id"

    async def test_new_build_is_downloaded_again(self, client, telegram, releases, app):
        app.state.delivery._cooldown = 0
        await ask(client)
        releases.release = releases.release.__class__(
            build=55, version="0.1.0", notes="n", assets=releases.release.assets
        )
        await ask(client, user=222)
        assert releases.downloads == 2
        assert telegram.documents[1]["document"][0] == "al-hisob-arm64-v8a.apk"

    async def test_answers_in_the_users_language(self, client, telegram):
        await ask(client, lang="uz")
        assert "yuborayapman" in telegram.sent[0]["text"] or "yuboryapman" in telegram.sent[0]["text"]
        assert "build 54" in telegram.documents[0]["caption"]

    async def test_cooldown_blocks_spam_per_person(self, client, telegram, releases):
        await ask(client)
        await ask(client)
        assert len(telegram.documents) == 1
        assert "подождите" in telegram.sent[-1]["text"]
        await ask(client, user=999)
        assert len(telegram.documents) == 2, "другой человек не блокируется"

    async def test_failure_sends_a_manual_link_and_does_not_cache_broken_state(self, client, telegram, releases, app):
        app.state.delivery._cooldown = 0
        releases.fail_download = True
        r = await ask(client)
        assert r.status_code == 200
        assert not telegram.documents
        assert "Скачайте вручную" in telegram.sent[-1]["text"]
        assert BASE + "al-hisob-arm64-v8a.apk" in telegram.sent[-1]["text"]

        releases.fail_download = False
        await ask(client, user=222)
        assert len(telegram.documents) == 1, "после сбоя следующая попытка работает"

    async def test_telegram_upload_error_also_falls_back_to_a_link(self, client, telegram):
        telegram.document_error = RuntimeError("boom")
        await ask(client)
        assert "Скачайте вручную" in telegram.sent[-1]["text"]

    async def test_no_published_version(self, client, telegram, releases):
        releases.has_release = False
        await ask(client)
        assert "нет опубликованных" in telegram.sent[-1]["text"]
        assert not telegram.documents

    async def test_other_text_still_gets_help_that_mentions_the_command(self, client, telegram):
        await post_update(client, bot_update(text="hello"))
        assert "/app" in telegram.last["text"]


class TestReleaseParsing:
    def test_picks_our_apks_and_the_version(self):
        r = parse_release(release_json(), REPO)
        assert r.build == 54 and r.version == "0.1.0"
        assert set(r.assets) == {"arm64-v8a", "armeabi-v7a", "x86_64"}
        assert r.default.abi == "arm64-v8a"
        assert "Co-Authored-By" in r.notes and "\n" not in r.notes

    def test_ignores_foreign_hosts_and_other_files(self):
        data = release_json()
        data["assets"][0]["browser_download_url"] = "https://evil.example/al-hisob-arm64-v8a.apk"
        data["assets"].append({"name": "notes.txt", "browser_download_url": BASE + "notes.txt", "size": 1})
        r = parse_release(data, REPO)
        assert "arm64-v8a" not in r.assets
        assert r.default.abi == "armeabi-v7a", "без arm64 берётся другой"

    def test_rejects_unknown_tags_and_empty_releases(self):
        assert parse_release(release_json(tag_name="v1.0"), REPO) is None
        assert parse_release(release_json(assets=[]), REPO) is None


class TestGithubReleases:
    def make(self, handler):
        return GithubReleases(REPO, transport=httpx.MockTransport(handler))

    async def test_latest_is_cached(self):
        calls = []

        def handler(request):
            calls.append(str(request.url))
            return httpx.Response(200, json=release_json())

        source = self.make(handler)
        assert (await source.latest()).build == 54
        assert (await source.latest()).build == 54
        assert len(calls) == 1
        assert calls[0] == f"https://api.github.com/repos/{REPO}/releases/latest"

    async def test_lookup_failure_returns_none_or_the_previous_value(self):
        source = self.make(lambda request: httpx.Response(500))
        assert await source.latest() is None

    async def test_download_follows_redirects_and_limits_size(self):
        def handler(request):
            if request.url.host == "github.com":
                return httpx.Response(302, headers={"location": "https://release-assets.githubusercontent.com/x"})
            return httpx.Response(200, content=b"x" * 1000)

        source = self.make(handler)
        asset = parse_release(release_json(), REPO).default
        assert await source.download(asset) == b"x" * 1000

        from app.telegram import releases as mod

        old = mod.MAX_APK_BYTES
        mod.MAX_APK_BYTES = 500
        try:
            try:
                await source.download(asset)
                raise AssertionError("must reject a large file")
            except ValueError as e:
                assert "too large" in str(e)
        finally:
            mod.MAX_APK_BYTES = old

    async def test_download_refuses_foreign_urls(self):
        source = self.make(lambda request: httpx.Response(200, content=b"x"))
        from app.telegram.releases import ApkAsset

        try:
            await source.download(ApkAsset("arm64-v8a", "a.apk", "https://evil.example/a.apk", 1))
            raise AssertionError("must refuse")
        except ValueError as e:
            assert "untrusted" in str(e)


class TestTelegramClient:
    async def test_upload_sends_multipart_and_returns_the_file_id(self):
        seen = {}

        def handler(request):
            seen["url"] = str(request.url)
            seen["body"] = request.content
            seen["ctype"] = request.headers["content-type"]
            return httpx.Response(200, json={"ok": True, "result": {"document": {"file_id": "AbC123"}}})

        client = HttpTelegramClient("123:SECRET", transport=httpx.MockTransport(handler))
        file_id = await client.send_document(
            5, document=("a.apk", b"APKDATA"), caption="hi", reply_markup={"inline_keyboard": []}
        )
        assert file_id == "AbC123"
        assert seen["url"].endswith("/sendDocument")
        assert seen["ctype"].startswith("multipart/form-data")
        assert b"APKDATA" in seen["body"] and b'name="chat_id"' in seen["body"] and b"hi" in seen["body"]

    async def test_known_file_id_is_sent_as_text(self):
        seen = {}

        def handler(request):
            seen["body"] = request.content
            return httpx.Response(200, json={"ok": True, "result": {"document": {"file_id": "AbC123"}}})

        client = HttpTelegramClient("123:SECRET", transport=httpx.MockTransport(handler))
        await client.send_document(5, document="AbC123")
        assert b"AbC123" in seen["body"]

    async def test_errors_never_contain_the_bot_token(self):
        client = HttpTelegramClient("123:SECRET", transport=httpx.MockTransport(lambda r: httpx.Response(400, json={})))
        try:
            await client.send_message(5, "hi")
            raise AssertionError("must fail")
        except TelegramError as e:
            assert "SECRET" not in str(e) and "SECRET" not in repr(e)
            assert "400" in str(e)

        def boom(request):
            raise httpx.ConnectError("cannot connect to https://api.telegram.org/bot123:SECRET/sendMessage")

        client = HttpTelegramClient("123:SECRET", transport=httpx.MockTransport(boom))
        try:
            await client.send_message(5, "hi")
            raise AssertionError("must fail")
        except TelegramError as e:
            assert "SECRET" not in str(e)
            assert e.__cause__ is None and e.__suppress_context__

    async def test_commands_menu_per_language(self):
        bodies = []

        def handler(request):
            bodies.append(request.content)
            return httpx.Response(200, json={"ok": True})

        client = HttpTelegramClient("123:SECRET", transport=httpx.MockTransport(handler))
        await client.set_commands([{"command": "app", "description": "d"}], "uz")
        assert b'"language_code":"uz"' in bodies[0].replace(b" ", b"") and b"setMyCommands" not in bodies[0]
