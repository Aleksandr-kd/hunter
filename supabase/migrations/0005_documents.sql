-- ============================================================
-- Помощник охотника — documents (синхронизация документов)
-- Выполнить в Supabase SQL Editor
-- ============================================================

create table if not exists public.user_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  expiry_date date,
  updated_at timestamptz not null default now(),
  unique(user_id, title)
);

alter table public.user_documents enable row level security;

create policy "own documents select" on public.user_documents
  for select using (auth.uid() = user_id);
create policy "own documents insert" on public.user_documents
  for insert with check (auth.uid() = user_id);
create policy "own documents update" on public.user_documents
  for update using (auth.uid() = user_id);
create policy "own documents delete" on public.user_documents
  for delete using (auth.uid() = user_id);
