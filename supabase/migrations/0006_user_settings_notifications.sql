-- ============================================================
-- Помощник охотника — добавление синхронизации уведомлений
-- Выполнить в Supabase SQL Editor
-- ============================================================

alter table public.user_settings
  add column if not exists notifications_seasons boolean not null default true;

alter table public.user_settings
  add column if not exists notifications_documents boolean not null default true;
