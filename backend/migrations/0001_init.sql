-- Пользователи: идентифицируются подтверждённым номером телефона.
create table users (
    id          uuid primary key default gen_random_uuid(),
    phone       text not null unique,
    telegram_id bigint unique,
    name        text,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

-- Запросы на вход через Telegram-бота. Секреты хранятся только в виде хэшей.
create table login_requests (
    id               uuid primary key default gen_random_uuid(),
    start_token_hash text not null unique,   -- токен из ссылки t.me/<bot>?start=<токен>
    poll_secret_hash text not null,          -- секрет, которым приложение опрашивает статус
    status           text not null default 'pending'
                     check (status in ('pending', 'approved', 'consumed')),
    phone            text,
    telegram_id      bigint,
    telegram_name    text,
    device_name      text,
    created_at       timestamptz not null default now(),
    expires_at       timestamptz not null,
    approved_at      timestamptz,
    consumed_at      timestamptz
);
create index login_requests_telegram_idx on login_requests (telegram_id) where status = 'pending';
create index login_requests_expires_idx on login_requests (expires_at);

-- Сессии: refresh-токен (хэш) с ротацией и защитой от повторного использования.
create table sessions (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid not null references users (id) on delete cascade,
    refresh_hash      text not null unique,
    prev_refresh_hash text,
    rotated_at        timestamptz,
    device_name       text,
    created_at        timestamptz not null default now(),
    last_used_at      timestamptz not null default now(),
    expires_at        timestamptz not null,
    revoked_at        timestamptz
);
create index sessions_user_idx on sessions (user_id);
create index sessions_prev_refresh_idx on sessions (prev_refresh_hash) where prev_refresh_hash is not null;
