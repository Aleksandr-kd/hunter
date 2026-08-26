-- Миграция: доп. колонки для дневника охотника.
-- Добавляет к таблице diary_entries поля result, weight, count, method.
-- Выполнить в Supabase → SQL Editor.

alter table public.diary_entries
  add column if not exists result text default '',
  add column if not exists weight double precision,
  add column if not exists count integer,
  add column if not exists method text;