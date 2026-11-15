"""Тексты бота на языке пользователя Telegram (uz, ru, en; по умолчанию русский)."""

_TEXTS: dict[str, dict[str, str]] = {
    "ru": {
        "share_prompt": "Чтобы войти в Al-Hisob, поделитесь номером телефона кнопкой ниже.",
        "share_button": "📱 Поделиться номером",
        "done": "Готово! Вернитесь в приложение — вход выполнен.",
        "open_button": "📲 Открыть Al-Hisob",
        "app_wait": "⏳ Отправляю последнюю версию Al-Hisob…",
        "app_caption": "Al-Hisob {version} (сборка {build})\n{notes}\n\nУстановка: откройте файл и разрешите установку из этого источника. Данные сохранятся.",
        "app_other": "Если не подходит (старый телефон / эмулятор):",
        "app_failed": "Не удалось отправить файл. Скачайте вручную:",
        "app_none": "Пока нет опубликованных версий.",
        "app_cooldown": "Файл уже отправлен, подождите несколько секунд.",
        "app_menu": "Скачать последнюю версию Al-Hisob",
        "not_own": "Отправьте, пожалуйста, свой собственный номер кнопкой ниже.",
        "expired": "Ссылка для входа устарела. Нажмите «Войти» в приложении ещё раз.",
        "no_request": "Нет ожидающего входа. Нажмите «Войти» в приложении Al-Hisob.",
        "help": "Это бот Al-Hisob. Для входа нажмите «Войти через Telegram» в приложении. Команда /app — скачать последнюю версию приложения.",
    },
    "uz": {
        "share_prompt": "Al-Hisob’ga kirish uchun quyidagi tugma orqali telefon raqamingizni ulashing.",
        "share_button": "📱 Raqamni ulashish",
        "done": "Tayyor! Ilovaga qayting — kirish bajarildi.",
        "open_button": "📲 Al-Hisob’ni ochish",
        "app_wait": "⏳ Al-Hisob’ning oxirgi versiyasini yuboryapman…",
        "app_caption": "Al-Hisob {version} (build {build})\n{notes}\n\nO‘rnatish: faylni oching va shu manbadan o‘rnatishga ruxsat bering. Ma’lumotlar saqlanadi.",
        "app_other": "Mos kelmasa (eski telefon / emulyator):",
        "app_failed": "Faylni yuborib bo‘lmadi. Qo‘lda yuklab oling:",
        "app_none": "Hozircha e’lon qilingan versiya yo‘q.",
        "app_cooldown": "Fayl yuborilgan, bir necha soniya kuting.",
        "app_menu": "Al-Hisob’ning oxirgi versiyasini yuklab olish",
        "not_own": "Iltimos, quyidagi tugma orqali o‘zingizning raqamingizni yuboring.",
        "expired": "Kirish havolasi eskirgan. Ilovada «Kirish» tugmasini qayta bosing.",
        "no_request": "Kutilayotgan kirish yo‘q. Al-Hisob ilovasida «Kirish» tugmasini bosing.",
        "help": "Bu Al-Hisob boti. Kirish uchun ilovada «Telegram orqali kirish»ni bosing. /app buyrug‘i — ilovaning oxirgi versiyasini yuklab olish.",
    },
    "en": {
        "share_prompt": "To sign in to Al-Hisob, share your phone number with the button below.",
        "share_button": "📱 Share phone number",
        "done": "Done! Go back to the app — you are signed in.",
        "open_button": "📲 Open Al-Hisob",
        "app_wait": "⏳ Sending the latest Al-Hisob…",
        "app_caption": "Al-Hisob {version} (build {build})\n{notes}\n\nInstall: open the file and allow installs from this source. Your data stays.",
        "app_other": "If it does not fit (old phone / emulator):",
        "app_failed": "Could not send the file. Download it manually:",
        "app_none": "No published versions yet.",
        "app_cooldown": "The file was just sent, please wait a few seconds.",
        "app_menu": "Download the latest Al-Hisob",
        "not_own": "Please send your own number with the button below.",
        "expired": "The sign-in link has expired. Tap “Sign in” in the app again.",
        "no_request": "No pending sign-in. Tap “Sign in” in the Al-Hisob app.",
        "help": "This is the Al-Hisob bot. To sign in, tap “Sign in with Telegram” in the app. Send /app to get the latest version of the app.",
    },
}


def text(language_code: str | None, key: str) -> str:
    lang = (language_code or "").lower().split("-")[0]
    table = _TEXTS.get(lang, _TEXTS["ru"])
    return table[key]
