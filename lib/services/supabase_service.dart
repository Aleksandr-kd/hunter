import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Централизованная конфигурация Supabase.
///
/// Порядок приоритета ключей:
/// 1. --dart-define (production/скрипты)
/// 2. .env файл (development из IDE)
class SupabaseConfig {
  static const String urlEnv = String.fromEnvironment('SUPABASE_URL');
  static const String anonKeyEnv = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Загружает ключи из .env файла.
  static Map<String, String> _loadEnv() {
    final candidates = [File('..env'), File('.env')];
    for (final envFile in candidates) {
      if (envFile.existsSync()) {
        return envFile
            .readAsLinesSync()
            .where((line) =>
                line.isNotEmpty &&
                !line.startsWith('#') &&
                line.contains('='))
            .fold(<String, String>{}, (map, line) {
          final parts = line.split('=');
          if (parts.length >= 2) {
            map[parts[0].trim()] = parts.skip(1).join('=').trim();
          }
          return map;
        });
      }
    }
    return {};
  }

  /// Ключи: сначала dart-define, потом .env fallback.
  static String get url {
    if (urlEnv.isNotEmpty) return urlEnv;
    final env = _loadEnv();
    return env['SUPABASE_URL'] ?? '';
  }

  static String get anonKey {
    if (anonKeyEnv.isNotEmpty) return anonKeyEnv;
    final env = _loadEnv();
    return env['SUPABASE_ANON_KEY'] ?? '';
  }

  /// Уведомляющий ключ для инициализации клиента.
  static String get _publishableKey => anonKey;

  /// Есть ли настроенные данные (не пусты).
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}

/// Инициализация Supabase-клиента.
class SupabaseService {
  static bool _initialized = false;

  // Идемпотентная инициализация: параллельные вызовы init() разделяют один
  // Future и не запускают дублирующий Supabase.initialize().
  static Future<void>? _initFuture;

  static Future<void> init() {
    if (_initialized) return Future.value();
    return _initFuture ??= _doInit();
  }

  static Future<void> _doInit() async {
    if (!SupabaseConfig.isConfigured) {
      debugPrint('Supabase: не настроен — пропускаю инициализацию (offline)');
      return;
    }
    debugPrint('Supabase: инициализация с url=${SupabaseConfig.url}');
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig._publishableKey,
    );
    _initialized = true;
    debugPrint('Supabase: инициализирован');
  }

  static bool get isReady => _initialized;

  static SupabaseClient? get client =>
      _initialized ? Supabase.instance.client : null;
}
