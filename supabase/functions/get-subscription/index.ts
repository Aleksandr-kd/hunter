// Traceable edge function: get-subscription
// Возвращает актуальный статус подписки текущего пользователя (из JWT).
//
// Вызывается приложением после логина.
// Проверяет expires_at и возвращает tier + валидность.
//
// NOTE: до запуска RuStore статус пишется dev-переключателем тарифа;
// реальные покупки будут подтверждаться webhook-ом RuStore.

import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

Deno.serve(async (req) => {
  const authHeader = req.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }
  const token = authHeader.replace("Bearer ", "");

  // Клиент от имени пользователя (RLS отфильтрует только его подписку).
  const supabase: SupabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  // Проверяем валидность JWT и достаём user id.
  const { data: userData, error: userErr } = await supabase.auth.getUser(token);
  if (userErr || !userData?.user) {
    return new Response(JSON.stringify({ error: "invalid token" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }
  const userId = userData.user.id;

  const { data, error } = await supabase
    .from("subscriptions")
    .select("tier, expires_at")
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    return new Response(JSON.stringify({ error }), { status: 500 });
  }

  const tier = data?.tier ?? "none";
  const expiresAt = data?.expires_at ?? null;
  const expired = expiresAt != null && new Date(expiresAt) <= new Date();
  const valid = expiresAt == null || !expired;

  return new Response(
    JSON.stringify({
      tier: valid ? tier : "none",
      expiresAt,
      valid,
    }),
    { headers: { "content-type": "application/json" } }
  );
});