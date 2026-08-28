-- ============================================================
-- Помощник охотника — unique (user_id, uuid) для diary_entries
-- Выполнить в Supabase SQL Editor
-- ============================================================
--
-- Проблема: клиент делает upsert по onConflict на ключ, но у таблицы
-- diary_entries нет уникального constraint на uuid. В результате upsert
-- превращался в безусловный INSERT и плодил дубликаты строк с одним uuid.
--
-- Исправление: чистим существующие дубли и вводим уникальный индекс
-- (user_id, uuid) — теперь клиент может конфликтовать по нему.

-- 1) Убираем дубли: для каждого (user_id, uuid) оставляем самую новую строку
--    (по updated_at, потом по id), остальные — удаляем.
delete from public.diary_entries d
using (
  select
    user_id,
    uuid,
    row_number() over (
      partition by user_id, uuid
      order by coalesce(updated_at, created_at) desc, id desc
    ) as rn
  from public.diary_entries
  where uuid is not null and uuid <> ''
) dup
where d.user_id = dup.user_id
  and d.uuid = dup.uuid
  and dup.rn > 1;

-- 2) Уникальный индекс (user_id, uuid) для конфликтов upsert.
--    Partial: только для записей с непустым uuid (старые строки без uuid
--    не индексируются, чтобы не конфликтовать с NULL).
create unique index if not exists idx_diary_entries_user_uuid
  on public.diary_entries (user_id, uuid)
  where uuid is not null and uuid <> '';
