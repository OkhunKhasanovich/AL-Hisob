-- Синхронизация: сервер хранит записи приложения как JSON, по пользователям.
-- Схему клиента (Drift) сервер не знает, поэтому её изменения не требуют миграций здесь.
create sequence sync_seq;

create table sync_records (
    user_id    uuid        not null references users (id) on delete cascade,
    entity     text        not null,
    id         uuid        not null,
    data       jsonb       not null,
    updated_at timestamptz not null,   -- время правки на устройстве: по нему побеждает самая свежая
    deleted_at timestamptz,            -- мягкое удаление: запись остаётся, чтобы удаление дошло до других устройств
    seq        bigint      not null default nextval('sync_seq'),  -- порядок получения для выдачи изменений
    primary key (user_id, entity, id)
);
create index sync_records_user_seq_idx on sync_records (user_id, seq);
