"""Тексты бота на языке пользователя Telegram (uz, ru, en; по умолчанию русский)."""

_TEXTS: dict[str, dict[str, str]] = {
    "ru": {
        "share_prompt": "Чтобы войти в Al-Hisob, поделитесь номером телефона кнопкой ниже.",
        "share_button": "📱 Поделиться номером",
        "done": "Готово! Вернитесь в приложение — вход выполнен.",
        "not_own": "Отправьте, пожалуйста, свой собственный номер кнопкой ниже.",
        "expired": "Ссылка для входа устарела. Нажмите «Войти» в приложении ещё раз.",
        "no_request": "Нет ожидающего входа. Нажмите «Войти» в приложении Al-Hisob.",
        "help": "Это бот для входа в Al-Hisob. Нажмите «Войти через Telegram» в приложении.",
    },
    "uz": {
        "share_prompt": "Al-Hisob’ga kirish uchun quyidagi tugma orqali telefon raqamingizni ulashing.",
        "share_button": "📱 Raqamni ulashish",
        "done": "Tayyor! Ilovaga qayting — kirish bajarildi.",
        "not_own": "Iltimos, quyidagi tugma orqali o‘zingizning raqamingizni yuboring.",
        "expired": "Kirish havolasi eskirgan. Ilovada «Kirish» tugmasini qayta bosing.",
        "no_request": "Kutilayotgan kirish yo‘q. Al-Hisob ilovasida «Kirish» tugmasini bosing.",
        "help": "Bu Al-Hisob’ga kirish uchun bot. Ilovada «Telegram orqali kirish»ni bosing.",
    },
    "en": {
        "share_prompt": "To sign in to Al-Hisob, share your phone number with the button below.",
        "share_button": "📱 Share phone number",
        "done": "Done! Go back to the app — you are signed in.",
        "not_own": "Please send your own number with the button below.",
        "expired": "The sign-in link has expired. Tap “Sign in” in the app again.",
        "no_request": "No pending sign-in. Tap “Sign in” in the Al-Hisob app.",
        "help": "This is the Al-Hisob sign-in bot. Tap “Sign in with Telegram” in the app.",
    },
}


def text(language_code: str | None, key: str) -> str:
    lang = (language_code or "").lower().split("-")[0]
    table = _TEXTS.get(lang, _TEXTS["ru"])
    return table[key]
