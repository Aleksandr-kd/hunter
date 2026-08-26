#!/usr/bin/env bash
# Собирает и запускает приложение «Охотник» на физическом iPhone (только iOS).
#
# Ключи Supabase читаются из .env (не коммитятся в git).
# Требуется: iPhone в той же Wi-Fi сети что Mac (или по кабелю), разблокирован.
#
# Порядок: сборка iOS release → установка через devicectl → запуск.

set -e

cd "$(dirname "$0")/.."

# --- Ключи Supabase из .env ---
URL=$(grep SUPABASE_URL .env | cut -d= -f2-)
KEY=$(grep SUPABASE_ANON_KEY .env | cut -d= -f2-)
if [ -z "$URL" ] || [ -z "$KEY" ]; then
  echo "ОШИБКА: нет SUPABASE_URL / SUPABASE_ANON_KEY в .env"
  exit 1
fi

# --- Устройство и Bundle ID ---
IPHONE_ID="${IPHONE_ID:-$(xcrun devicectl list devices 2>/dev/null | grep -i iphone | head -1 | awk '{print $1}')}"
IPHONE_ID="${IPHONE_ID:-00008140-00144D9E0290801C}"
BUNDLE_ID="ru.hunterapp.pomoshchnikOkhotnika"

if [ -z "$IPHONE_ID" ] || [ "$IPHONE_ID" = "iPhone" ]; then
  echo "ОШИБКА: iPhone не найден. Разблокируйте телефон и подключите к сети/кабелю."
  exit 1
fi

echo "=== iOS: сборка RELEASE с ключами и подписью ==="
flutter build ios --release \
  --dart-define=SUPABASE_URL="$URL" \
  --dart-define=SUPABASE_ANON_KEY="$KEY"

echo "=== iOS: установка на iPhone ($IPHONE_ID) ==="
xcrun devicectl device install app --device "$IPHONE_ID" build/ios/iphoneos/Runner.app

echo "=== iOS: запуск ==="
if xcrun devicectl device process launch --device "$IPHONE_ID" "$BUNDLE_ID"; then
  echo "iOS: OK"
else
  echo "iOS: установлено, но запуск не подтверждён (проверьте телефон)."
fi

echo "Готово!"