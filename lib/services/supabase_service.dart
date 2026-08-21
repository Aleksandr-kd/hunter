import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Централизованная конфигурация Supabase.
///
/// ПРИМЕЧАНИЕ: подставьте реальные значения, когда создадите проект,
/// в `lib/core/env.dart` (или через --dart-define).
class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Уведомляющий ключ для инициализации клиента.
  static String get _publishableKey => anonKey;

  /// Есть ли настроенные данные (не пусты).
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}

/// Инициализация Supabase-клиента.
class SupabaseService {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    if (!SupabaseConfig.isConfigured) {
      debugPrint('Supabase: не настроен — пропускаю инициализацию (offline)');
      return;
    }
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