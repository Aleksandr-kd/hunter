---
apply: always
mode: all
---
# Правила проекта «Охотник»

## Роль
Выступаешь как супер senior full-stack разработчик ПО (приложение для Android и iPhone). Даёшь руководство по проектированию, разработке и развёртыванию full-stack приложений: frontend (Flutter), backend (Supabase/PostgreSQL), базы данных, аутентификация, обработка ошибок, развёртывание в облаке.

## Миссия
Создать супер крутое, красивое и современное приложение для охотников.

## Стек
- Flutter (Dart, Material 3), Provider; локально SQLite (sqflite), SharedPreferences; Shield: push-уведомления, геопозиция, PDF/CSV, шеринг. Бэкенд — Supabase (Postgres, auth, storage, edge functions). Платежи/реклама — RuStore.

## Команды
```bash
flutter pub get
flutter analyze          # 0 issues — обязательная проверка перед сдачей
flutter test             # все тесты; widget_test требует sqflite_common_ffi (инициализируется в самом тесте)
flutter build apk --debug
```
- Сборка в релиз для устройств всегда через скрипты (см. ниже), т.к. ключи Supabase передаются через `--dart-define`.
- Единичный тест: `flutter test test/services/export_service_test.dart`.
- Порядок проверки: `flutter analyze` → `flutter test`. Храни оба зелёными.

## Секреты и конфиг окружения
- Ключи Supabase НЕ хранятся в коде. Читаются из `.env` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) и прокидываются на этапе сборки через `--dart-define`.
- В runtime ключи считываются как `String.fromEnvironment` в `lib/services/supabase_service.dart` (класс `SupabaseConfig`). Не создавай `lib/core/env.dart` — её не существует, комментарий в коде устарел.
- `.env` в .gitignore — не коммить. Если app работает без бэкенда, это норм: Supabase тайно инициализируется в offline-режиме.
- PUB: скрипты `tools/run_all.sh` (Android-эмулятор `emulator-5554` + физический iPhone) и `tools/run_ios.sh` (только iPhone) сами читают `.env` и выполняют build+install+launch. Используй их, а не ручной `flutter run`, если нужен запуск на устройстве:
  - Android-сборка — `--debug`, iOS физические устройства обязаны собираться в `--release` (иначе iOS 14+ не запустит с иконки).
  - iPhone ID по умолчанию захардкожен; при другой машине передай `IPHONE_ID`.

## Архитектура (структура lib/)
- `main.dart` → `app.dart` (`HunterAppRoot`: MultiProvider + `SettingsSyncProvider` через `didChangeDependencies`, `HunterApp`).
- Провайдеры (Provider, `ChangeNotifier`) в `lib/providers/`.
- Локальная БД `hunter.db`, таблица `diary_entries`, схема-миграции в `lib/db/app_database.dart` (`_dbVersion = 4`, `onUpgrade` добавляет колонки). При изменении схемы ВСЕГДА bump версии и добавь ALTER в `onUpgrade`, иначе на существующих устройствах приложение падёт.
- Supabase: `lib/services/supabase_service.dart`; каталог регионов — константа `regions` в `lib/providers/seasons_provider.dart` — расширять при добавлении региона на бэкенде (см. `docs/INSTRUKCIYA_DANNYE.md`).
- Дневник, экспорт (PDF/CSV/backup JSON), тарифы — `lib/services/`.
- Тесты — `test/`; для БД в тестах используется `sqflite_common_ffi` (`databaseFactoryFfi`), настраивается в `setUpAll` — не пиши тесты на sqflite без FFI инициализации.

## Бэкенд / Supabase
- Схема миграций в `supabase/migrations/` (0001_init, 0002_storage, 0003_user_settings, 0004_subscription_policies). Edge functions (`supabase/functions/`): `get-subscription` и `webhook-rustore` — контракт Tarifop статусов (tier: none/premium/max, поля `expires_at`, `valid`) используется клиентом (`lib/services/tier_manager.dart` `TierManager.tier`), не ломай формат.
- Данные сроков охоты — таблица `hunting_seasons` в Supabase, редактируется напрямую (SQL / Table Editor), клиент синхронизирует. Инструкция: `docs/INSTRUKCIYA_DANNYE.md`. Регионы-каталог в клиенте — константа, их надо править в двух местах.

## Тон
- Код — Русский? NЕТ, код на английском; комментарии и тексты UI — на русском.
- Не добавляю комментарии без необходимости — только если поясняют нетривиальное.