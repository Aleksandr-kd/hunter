#!/usr/bin/env bash
# Собирает и запускает приложение «Охотник» одновременно на двух устройствах:
#   1) Android-эмулятор (установка + запуск)
#   2) Физический iPhone (сборка + установка + запуск через devicectl)
#
# Ключи Supabase читаются из .env (не коммитятся в git).
# Для первого запуска на iPhone: Настройки → Основные → VPN и управление
# устройством → доверьте профиль разработчика, иначе iOS заблокирует запуск
# ("profile has not been explicitly trusted").

set -e

cd "$(dirname "$0")/.."

# --- Ключи Supabase из .env ---
URL=$(grep SUPABASE_URL .env | cut -d= -f2-)
KEY=$(grep SUPABASE_ANON_KEY .env | cut -d= -f2-)
if [ -z "$URL" ] || [ -z "$KEY" ]; then
  echo "ОШИБКА: нет SUPABASE_URL / SUPABASE_ANON_KEY в .env"
  exit 1
fi

# --- Устройства ---
ANDROID_ID="${ANDROID_ID:-emulator-5554}"
IPHONE_ID="${IPHONE_ID:-00008140-00144D9E0290801C}"
BUNDLE_ID="ru.hunterapp.pomoshchnikOkhotnika"

# --- 1. Android ---
echo "=== Android: сборка debug с ключами ==="
flutter build apk --debug \
  --dart-define=SUPABASE_URL="$URL" \
  --dart-define=SUPABASE_ANON_KEY="$KEY"

echo "=== Android: установка на эмулятор ($ANDROID_ID) ==="
adb install -r build/app/outputs/flutter-apk/app-debug.apk

echo "=== Android: запуск ==="
adb shell am force-stop "$BUNDLE_ID" || true
adb shell monkey -p "$BUNDLE_ID" -c android.intent.category.LAUNCHER 1
echo "Android: OK"

# --- 2. iOS (физический iPhone) ---
echo "=== iOS: сборка debug с ключами и подписью ==="
flutter build ios --debug \
  --dart-define=SUPABASE_URL="$URL" \
  --dart-define=SUPABASE_ANON_KEY="$KEY"

echo "=== iOS: установка на iPhone ($IPHONE_ID) ==="
xcrun devicectl device install app --device "$IPHONE_ID" build/ios/iphoneos/Runner.app

echo "=== iOS: запуск ==="
if xcrun devicectl device process launch --device "$IPHONE_ID" "$BUNDLE_ID"; then
  echo "iOS: OK"
else
  echo "iOS: установлено, но запуск заблокирован системой до доверия профилю разработчика."
  echo "На iPhone: Настройки → Основные → VPN и управление устройством → доверьте профиль."
fi

echo "Готово!"