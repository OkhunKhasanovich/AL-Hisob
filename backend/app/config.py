from functools import lru_cache

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Настройки из переменных окружения (в Docker — из файла .env на сервере).

    Секреты (токен бота, ключ JWT, пароль БД) в репозиторий не попадают.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    env: str = "development"  # production отключает /docs и включает проверки секретов
    database_url: str = "postgresql://postgres@localhost/alhisob"
    public_base_url: str = "http://localhost:8000"

    jwt_secret: str = "dev-secret-change-me-please-0123456789abcdef"
    access_token_ttl_minutes: int = 15
    refresh_token_ttl_days: int = 90
    # Повтор обновления со старым refresh-токеном в течение этого окна не считается кражей
    # (ответ мог потеряться по дороге).
    refresh_reuse_grace_seconds: int = 60

    login_request_ttl_minutes: int = 10

    telegram_bot_token: str = ""
    telegram_bot_username: str = ""
    telegram_webhook_secret: str = ""

    # Доверять заголовку X-Forwarded-For (за nginx — да).
    trust_proxy: bool = False

    rate_limit_start_per_minute: int = Field(default=10, ge=1)
    rate_limit_poll_per_minute: int = Field(default=90, ge=1)
    rate_limit_refresh_per_minute: int = Field(default=30, ge=1)
    rate_limit_sync_per_minute: int = Field(default=120, ge=1)

    @property
    def is_production(self) -> bool:
        return self.env == "production"

    @model_validator(mode="after")
    def _check_production_secrets(self) -> "Settings":
        if self.is_production:
            problems = []
            if len(self.jwt_secret) < 32 or self.jwt_secret.startswith("dev-secret"):
                problems.append("JWT_SECRET must be a random string of at least 32 characters")
            if not self.telegram_bot_token:
                problems.append("TELEGRAM_BOT_TOKEN is required")
            if not self.telegram_bot_username:
                problems.append("TELEGRAM_BOT_USERNAME is required")
            if len(self.telegram_webhook_secret) < 16:
                problems.append("TELEGRAM_WEBHOOK_SECRET must be at least 16 characters")
            if problems:
                raise ValueError("; ".join(problems))
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
