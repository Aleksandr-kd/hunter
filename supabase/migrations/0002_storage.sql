-- ============================================================
-- Supabase Storage: bucket для фото дневника
-- Выполнить в SQL Editor после 0001_init.sql
-- ============================================================

-- Бакет для фото записей (приватный — доступ только авторизованным)
insert into storage.buckets (id, name, public)
values ('diary-photos', 'diary-photos', false)
on conflict (id) do nothing;

-- RLS: загрузка/чтение своих фото (по user_id из пути: diary-photos/<user_id>/...)
create policy "users can upload own photos" on storage.objects
  for insert
  to authenticated
  with check (bucket_id = 'diary-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "users can view own photos" on storage.objects
  for select
  to authenticated
  using (bucket_id = 'diary-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "users can delete own photos" on storage.objects
  for delete
  to authenticated
  using (bucket_id = 'diary-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "users can update own photos" on storage.objects
  for update
  to authenticated
  using (bucket_id = 'diary-photos' and (storage.foldername(name))[1] = auth.uid()::text);