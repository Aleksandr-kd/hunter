-- ============================================================
-- Помощник охотника — full_name в profiles
-- Выполнить в Supabase Dashboard → SQL Editor → New query
-- ============================================================

-- 1. Колонка для имени пользователя
alter table public.profiles
  add column if not exists full_name text;

-- 2. Триггер автосоздания профиля берёт имя из auth.users metadata
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, new.raw_user_meta_data ->> 'name')
  on conflict (id) do nothing;
  insert into public.subscriptions (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

-- 3. Бекфилл: копируем имя из metadata для уже существующих пользователей
update public.profiles p
set full_name = (a.raw_user_meta_data ->> 'name')
from auth.users a
where a.id = p.id
  and p.full_name is null
  and a.raw_user_meta_data ->> 'name' is not null;