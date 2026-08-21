-- ============================================================
-- Помощник охотника — Supabase SQL schema
-- Выполнить в Supabase Dashboard → SQL Editor → New query
-- ============================================================

-- Пользователи (профиль, привязан к auth.users)
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- Подписки пользователя и их статус
-- Используем единственную запись с активной подпиской:
--   tier: none | premium | max
--   expires_at: дата окончания
--   ru_store_purchase_token: токен покупки RuStore для верификации
create table if not exists public.subscriptions (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  tier text not null default 'none',
  expires_at timestamptz,
  ru_store_purchase_token text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id)
);
alter table public.subscriptions enable row level security;

-- Записи дневника (миграция из локальной БД; синхронизируются)
create table if not exists public.diary_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  local_id integer,            -- старый локальный id (для сопоставления)
  species text not null default '',
  location text,
  weather text,
  notes text,
  entry_date timestamptz not null default now(),
  photo_url text,
  latitude double precision,
  longitude double precision,
  created_at timestamptz not null default now()
);
alter table public.diary_entries enable row level security;

-- Индексы
create index if not exists idx_subscriptions_user on public.subscriptions (user_id);
create index if not exists idx_diary_user on public.diary_entries (user_id, entry_date desc);

-- ============================================================
-- Политики RLS
-- ============================================================

-- Пользователь читает/правит только свой профиль
create policy "own profile select" on public.profiles
  for select using (auth.uid() = id);
create policy "own profile update" on public.profiles
  for update using (auth.uid() = id);

-- Подписка: пользователь видит свою
create policy "own subscription select" on public.subscriptions
  for select using (auth.uid() = user_id);
-- Сервисная роль (edge-функции) управляет подписками через service_role key.

-- Дневник: пользователь читает/пишет только свои записи
create policy "own diary select" on public.diary_entries
  for select using (auth.uid() = user_id);
create policy "own diary insert" on public.diary_entries
  for insert with check (auth.uid() = user_id);
create policy "own diary update" on public.diary_entries
  for update using (auth.uid() = user_id);
create policy "own diary delete" on public.diary_entries
  for delete using (auth.uid() = user_id);

-- Триггер: автосоздание профиля при регистрации
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  insert into public.subscriptions (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Апдейт updated_at у подписки
create or replace function public.touch_subscription()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger on_subscription_update
  before update on public.subscriptions
  for each row execute procedure public.touch_subscription();