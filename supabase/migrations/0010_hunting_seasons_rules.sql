-- ============================================================================
-- 0010 — Плавающие даты сезонов: колонки date_rule / close_rule.
-- Добавляет отсутствующие колонки в уже созданную таблицу hunting_seasons.
-- Выполняйте в Supabase → SQL Editor ОДИН раз (перед заливкой скриптов
-- с плавающими датами, например hunting_seasons_stavropol.sql).
-- ============================================================================

alter table public.hunting_seasons add column if not exists date_rule text;
alter table public.hunting_seasons add column if not exists close_rule text;