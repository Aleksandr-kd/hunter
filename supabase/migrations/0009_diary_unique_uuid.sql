-- ============================================================
-- Помощник охотника — unique (user_id, uuid) для diary_entries
-- Выполнить в Supabase SQL Editor
-- ============================================================
--
-- Проблема: клиент делает upsert по onConflict: 'user_id,uuid', но PostgREST
-- НЕ поддерживает PARTIAL unique index (с WHERE) в ON CONFLICT. Если создать
-- частичный индекс "where uuid is not null and uuid <> ''", то upsert падает
-- с ошибкой 42P10 "there is no unique or exclusion constraint matching".
--
-- Исправление: создаём НЕ-partial UNIQUE constraint (user_id, uuid).
-- В Postgres NULL != NULL, поэтому строки с NULL-uuid не конфликтуют между
-- собой. Пустые uuid ('') нормализуем в NULL, чтобы constraint не ругался.

-- 1) Нормализуем пустые uuid: '' -> NULL.
update public.diary_entries
  set uuid = null
  where uuid = '';

-- 2) Убираем дубли: для каждого (user_id, uuid) оставляем самую новую строку
--    (по updated_at, потом по id), остальные — удаляем.
delete from public.diary_entries d
using (
  select
    user_id,
    uuid,
    id,
    row_number() over (
      partition by user_id, uuid
      order by coalesce(updated_at, created_at) desc, id desc
    ) as rn
  from public.diary_entries
  where uuid is not null
) dup
where d.user_id = dup.user_id
  and d.uuid = dup.uuid
  and dup.rn > 1;

-- 3) Убираем старый partial index (если был создан из прошлой версии 0009).
drop index if exists idx_diary_entries_user_uuid;

-- 4) Уникальный constraint (user_id, uuid) — его видит PostgREST onConflict.
alter table public.diary_entries
  drop constraint if exists diary_entries_user_uuid_key;
alter table public.diary_entries
  add constraint diary_entries_user_uuid_key unique (user_id, uuid);
