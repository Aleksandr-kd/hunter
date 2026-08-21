// Traceable edge function: webhook-ru-store
// Приём вебхуков RuStore о покупках/подписках, верификация и автоповышение 150→300.
//
// RuStore отправляет события (например PURCHASE.CONFIRMED, SUBSCRIPTION.EXPIRED,
// SUBSCRIPTION.CANCELLED) на URL этой функции.
//
// ВАЖНО: точные имена событий и формат payload зависят от актуальной документации
// RuStore OpenAPI. Ниже — заготовка, адаптируйте под реальную схему вебхука,
// конфигурацию доступа и секреты (RU_STORE_WEBHOOK_SECRET, RU_STORE_API).
//
// Для автоповышения: при активации tier=max отменяем активную tier=premium
// через RuStore API отмены подписки.

import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, supabaseServiceKey);

const WEBHOOK_SECRET = Deno.env.get("RU_STORE_WEBHOOK_SECRET") ?? "";

// Сопоставление подписочных ID (PKG_ID + SKU) → tier приложения
const TIERS = new Map<string, string>([
  ["premium_150", "premium"],
  ["max_300", "max"],
]);

interface RuStoreEvent {
  eventType?: string;
  purchase?: {
    userId?: string;
    productId?: string;
    purchaseToken?: string;
    productType?: string;
  };
  // Реальный формат может отличаться.
  [key: string]: unknown;
}

async function handle(event: RuStoreEvent) {
  const type = event.eventType ?? "";
  const purchase = event.purchase;
  if (!purchase?.userId) {
    return new Response("missing userId", { status: 400 });
  }
  const productId = purchase.productId ?? "";
  const tier = TIERS.get(productId) ?? null;

  const { data: sub, error } = await supabase
    .from("subscriptions")
    .select("*")
    .eq("user_id", purchase.userId)
    .maybeSingle();
  if (error) throw error;
  if (!sub) {
    return new Response("user has no subscription row", { status: 404 });
  }

  if (type.includes("CONFIRMED") || type.includes("ACTIVATED")) {
    if (tier) {
      // Сброс текущей подписки при пакете (событие может приходить повторно).
      // Если приходит max, отменяем premium ниже.
      const expiresAt = new Date(Date.now() + 365 * 86400 * 1000).toISOString();
      await supabase
        .from("subscriptions")
        .update({
          tier,
          expires_at: expiresAt,
          ru_store_purchase_token: purchase.purchaseToken,
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", purchase.userId);

      // Автоповышение: если стал max и у пользователя была premium — отмена premium.
      if (tier === "max") {
        // Здесь вызываем RuStore API отмены подписки premium_150
        // через RU_STORE_API + токен. Реализация зависит от RuStore OpenAPI.
        await cancelRuStoreSubscription(sub, purchase.purchaseToken);
      }
    }
  } else if (type.includes("EXPIRED") || type.includes("CANCELLED") || type.includes("REVOKED")) {
    // Погашение — переводим в none (если истёк). Упрощённо:
    await supabase
      .from("subscriptions")
      .update({ tier: "none", expires_at: new Date().toISOString() })
      .eq("user_id", purchase.userId);
  }

  return new Response(JSON.stringify({ ok: true }), {
    headers: { "content-type": "application/json" },
  });
}

// Заглушка отмены premium в RuStore. Адаптировать под актуальный API.
async function cancelRuStoreSubscription(
  sub: { [key: string]: unknown },
  token?: string
) {
  if (!token) return;
  // Пример: POST https://public-api.rustore.ru/.../subscription/revoke  (уточнить)
  // const res = await fetch(RU_STORE_API, {
  //   method: "POST",
  //   headers: { "Content-Type": "application/json" },
  //   body: JSON.stringify({ purchaseToken: token }),
  // });
  console.log("Would cancel premium for token", token);
}

Deno.serve(async (req) => {
  if (req.method === "POST") {
    const signature = req.headers.get("X-Signature") ?? req.headers.get("authorization") ?? "";
    // Проверка подписи вебхука (секрет). Упрощённо:
    if (WEBHOOK_SECRET && signature !== WEBHOOK_SECRET) {
      return new Response("unauthorized", { status: 401 });
    }
    try {
      const event = await req.json();
      return await handle(event);
    } catch (err) {
      console.error(err);
      return new Response("error", { status: 500 });
    }
  }
  return new Response("method not allowed", { status: 405 });
});