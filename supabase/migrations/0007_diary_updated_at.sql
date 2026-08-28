-- ============================================================
-- Помощник охотника — last-write-wins для дневника
-- Выполнить в Supabase SQL Editor
-- ============================================================

-- Колонка updated_at для разрешения конфликтов между устройствами.
alter table public.diary_entries
  add column if not exists updated_at timestamptz;

-- Заполняем историю значением created_at (там, где no updated_at).
update public.diary_entries
  set updated_at = created_at
  where updated_at is null;

-- Автообновление updated_at при любом изменении строки.
create or replace function public.set_diary_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_diary_entries_updated_at on public.diary_entries;
create trigger trg_diary_entries_updated_at
  before update on public.diary_entries
  for each row
  execute function public.set_diary_updated_at();
