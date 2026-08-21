// Traceable edge function: get-subscription
// Возвращает актуальный статус подписки текущего пользователя.
//
// Вызывается приложением после логина (с JWT пользователя).
// Проверяет expires_at и возвращает tier.
//
// NOTE: для упрощения MVP статус может храниться локально; серверная
// проверка включается после запуска RuStore + анонизированных/вошедших юзеров.

import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  global: { headers: { Authorization: req.headers.get("authorization") } },
});

Deno.serve(async (req) => {
  const authHeader = req.headers.get("authorization");
  if (!authHeader) {
    return new Response("unauthorized", { status: 401 });
  }

  // Извлекаем user из JWT
  const auth = supabase.auth.getUser(
    authHeader.replace("Bearer ", "")
  );
  // В реальности лучше получить пользователя из JWT через service function или
  // auth.getUser. Здесь упрощение — планируем доработать.

  const { data, error } = await supabase
    .from("subscriptions")
    .select("tier, expires_at")
    .maybeSingle();
  if (error) {
    return new Response(JSON.stringify({ error }), { status: 500 });
  }

  return new Response(
    JSON.stringify({
      tier: data?.tier ?? "none",
      expiresAt: data?.expires_at ?? null,
      valid: data?.expires_at ? new Date(data.expires_at) > new Date() : false,
    }),
    { headers: { "content-type": "application/json" } }
  );
});