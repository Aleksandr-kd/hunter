---
apply: always
mode: all
---
# Правила проекта «Охотник»

## Роль
Выступаешь как супер senior full-stack разработчик ПО (приложение для Android и iPhone). Даёшь руководство по проектированию, разработке и развёртыванию full-stack приложений: frontend (Flutter), backend (Supabase/PostgreSQL), базы данных, аутентификация, обработка ошибок, развёртывание в облаке.

## Принятие решений
При принятия решения о исправления подумай какие могут быть подводные камни и исходя из этого принимай решение как исправить! Возможно нужно проблему смотреть глубже чтобы учесть все мелкие детали!

## Стек
- Flutter (Dart, Material 3), Provider; локально SQLite (sqflite), SharedPreferences; Shield: push-уведомления, геопозиция. Бэкенд — Supabase (Postgres, auth, storage, edge functions). Платежи/реклама — RuStore.

## Команды
```bash
flutter pub get
flutter analyze          # 0 issues — обязательная проверка перед сдачей
flutter test             # все тесты; widget_test требует sqflite_common_ffi (инициализируется в самом тесте)
flutter build apk --debug
```
- Сборка в релиз для устройств всегда через скрипты (см. ниже), т.к. ключи Supabase передаются через `--dart-define`.
- Единичный тест: `flutter test test/services/legality_service_test.dart`.
- Порядок проверки: `flutter analyze` → `flutter test`. Храни оба зелёными.

## Секреты и конфиг окружения
- Ключи Supabase НЕ хранятся в коде. Читаются из `.env` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) и прокидываются на этапе сборки через `--dart-define`.
- В runtime ключи считываются как `String.fromEnvironment` в `lib/services/supabase_service.dart` (класс `SupabaseConfig`). Не создавай `lib/core/env.dart` — её не существует, комментарий в коде устарел.
- `.env` в .gitignore — не коммить. Если app работает без бэкенда, это норм: Supabase тайно инициализируется в offline-режиме.

## Запуск приложений — КРИТИЧНО ВАЖНО

### Android-эмулятор
**ВСЕГДА запускай через скрипт:** `./tools/run_android.sh`

⚠️ **НЕ запускай `flutter run -d emulator-5554` из IDE (VS Code, Android Studio)!**
При запуске из IDE ключи Supabase НЕ передаются → `SupabaseService.isReady == false` → экран «Вход временно недоступен».

Скрипт автоматически читает ключи из `.env` и передаёт через `--dart-define`.

### iPhone (физический)
Запускай через: `./tools/run_ios.sh` — автоматически передаёт ключи + собирает в `--release` (debug на iOS 14+ не запускается с иконки).

### iOS-симулятор
Аналогично Android — нужен `--dart-define`. Скрипта нет, запускай вручную:
```bash
flutter run -d <simulator_id> --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<key>
```

## Архитектура (структура lib/)
- `main.dart` → `app.dart` (`HunterAppRoot`: MultiProvider + `SettingsSyncProvider` через `didChangeDependencies`, `HunterApp`).
- Провайдеры (Provider, `ChangeNotifier`) в `lib/providers/`.
- Локальная БД `hunter.db`, таблица `diary_entries`, схема-миграции в `lib/db/app_database.dart` (`_dbVersion = 4`, `onUpgrade` добавляет колонки). При изменении схемы ВСЕГДА bump версии и добавь ALTER в `onUpgrade`, иначе на существующих устройствах приложение падёт.
- Supabase: `lib/services/supabase_service.dart`; каталог регионов (`SeasonsProvider.regions`) строится автоматически из записей `hunting_seasons` — новый регион на бэкенде подхватывается без правки кода (resервный список — `_fallbackRegions` в `seasons_provider.dart`, используется только при пустом кэше; см. `docs/INSTRUKCIYA_DANNYE.md`).
- Дневник и тарифы — `lib/services/`.
- Тесты — `test/`; для БД в тестах используется `sqflite_common_ffi` (`databaseFactoryFfi`), настраивается в `setUpAll` — не пиши тесты на sqflite без FFI инициализации.

## Бэкенд / Supabase
- Схема миграций в `supabase/migrations/` (0001_init, 0002_storage, 0003_user_settings, 0004_subscription_policies). Edge functions (`supabase/functions/`): `get-subscription` и `webhook-rustore` — контракт Tarifop статусов (tier: none/premium/max, поля `expires_at`, `valid`) используется клиентом (`lib/services/tier_manager.dart` `TierManager.tier`), не ломай формат.
- Данные сроков охоты — таблица `hunting_seasons` в Supabase, редактируется напрямую (SQL / Table Editor), клиент синхронизирует. Инструкция: `docs/INSTRUKCIYA_DANNYE.md`. Каталог регионов в клиенте строится из записей (`SeasonsProvider.regions`), отдельно «править в двух местах» не нужно.
