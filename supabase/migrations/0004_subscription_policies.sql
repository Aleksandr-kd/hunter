-- ============================================================
-- Помощник охотника — RLS: разрешить пользователю самому
-- вставлять/обновлять свою подписку (для dev-переключения тарифа
-- и корректной синхронизации tier между устройствами).
-- Выполнить в Supabase SQL Editor
-- ============================================================

-- Разрешить пользователю вставлять/обновлять СВОЮ строку подписки.
-- (Раньше действовала только select-политика, поэтому setTier/sync
--  падали на сервере, и на других устройствах tier оставался "none".)
create policy "own subscription insert" on public.subscriptions
  for insert with check (auth.uid() = user_id);

create policy "own subscription update" on public.subscriptions
  for update using (auth.uid() = user_id);