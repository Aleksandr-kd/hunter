-- ============================================================
-- Помощник охотника — LWW: клиент управляет updated_at
-- Выполнить в Supabase SQL Editor
-- ============================================================
--
-- Before: триггер перезаписывал updated_at на now() при каждом UPDATE,
-- из-за чего клиентский updated_at (LWW-вектор) терялся в ветке
-- ON CONFLICT (uuid) DO UPDATE при upsert. Клиент не мог явно
-- сообщить серверу «эта версия новее».
--
-- After: триггер переопределяет updated_at ТОЛЬКО если клиент его
-- явно не задал (значение не менялось или NULL). Если upsert присылает
-- своё updated_at — сервер сохраняет клиентское.

create or replace function public.set_diary_updated_at()
returns trigger
language plpgsql
as $$
begin
  if new.updated_at is null or new.updated_at = old.updated_at then
    new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_diary_entries_updated_at on public.diary_entries;
create trigger trg_diary_entries_updated_at
  before update on public.diary_entries
  for each row
  execute function public.set_diary_updated_at();