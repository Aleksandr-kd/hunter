#!/usr/bin/env bash
# ============================================================
# Запуск приложения «Охотник» на Android-эмуляторе
# ============================================================
#
# ВАЖНО: Этот скрипт ОБЯЗАТЕЛЕН для запуска на Android-эмуляторе!
# Ключи Supabase НЕ передаются при запуске через `flutter run` из IDE.
# Без --dart-define Supabase не инициализируется → ошибка "Вход временно недоступен".
#
# Использование:
#   ./tools/run_android.sh
#
# Требует:
#   - Эмулятор Android с ID emulator-5554
#   - Файл .env в корне проекта с SUPABASE_URL и SUPABASE_ANON_KEY
#
# НЕ запускай: flutter run -d emulator-5554 из IDE — ключи не передадутся!
# ============================================================

set -e

cd "$(dirname "$0")/.."

# --- Ключи Supabase из .env ---
URL=$(grep SUPABASE_URL .env | cut -d= -f2-)
KEY=$(grep SUPABASE_ANON_KEY .env | cut -d= -f2-)
if [ -z "$URL" ] || [ -z "$KEY" ]; then
  echo "ОШИБКА: нет SUPABASE_URL / SUPABASE_ANON_KEY в .env"
  exit 1
fi

echo "=== Android: запуск с ключами Supabase ==="
flutter run -d emulator-5554 \
  --dart-define=SUPABASE_URL="$URL" \
  --dart-define=SUPABASE_ANON_KEY="$KEY"

echo "Готово!"
