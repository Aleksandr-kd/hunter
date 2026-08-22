-- ============================================================
-- Помощник охотника — user_settings (синхронизация настроек)
-- Выполнить в Supabase SQL Editor
-- ============================================================

create table if not exists public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  theme_mode text not null default 'system',
  enabled_regions jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.user_settings enable row level security;

create policy "own settings select" on public.user_settings
  for select using (auth.uid() = user_id);
create policy "own settings insert" on public.user_settings
  for insert with check (auth.uid() = user_id);
create policy "own settings update" on public.user_settings
  for update using (auth.uid() = user_id);