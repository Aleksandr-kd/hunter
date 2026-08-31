import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../services/tier_manager.dart';

/// Статус авторизации.
enum AuthStatus { unknown, guest, signedIn }

/// Управляет входом/регистрацией через Supabase Auth.
class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;
  bool get isSignedIn => _status == AuthStatus.signedIn;
  bool get initialized => _status != AuthStatus.unknown;

  String _tier = 'none'; // none | premium | max
  String get tier => _tier;
  bool get isPremium => _tier == 'premium' || _tier == 'max';
  bool get isMax => _tier == 'max';

  /// Email текущего пользователя (dev-проверка).
  String? get userEmail =>
      SupabaseService.isReady ? SupabaseService.client?.auth.currentUser?.email : null;

  /// Имя пользователя из metadata (указывается при регистрации).
  String? get userName {
    if (!SupabaseService.isReady) return null;
    final meta = SupabaseService.client?.auth.currentUser?.userMetadata;
    if (meta == null) return null;
    final n = meta['name'];
    return n is String && n.trim().isNotEmpty ? n.trim() : null;
  }

  /// Dev-доступ к переключению тарифов (только для автора).
  bool get isDev {
    final e = userEmail?.toLowerCase();
    return e == 'als.d@mail.ru' || e == 'aleks@example.com';
  }

  AuthProvider() {
    _listen();
  }

  void _listen() {
    if (!SupabaseService.isReady) {
      // Supabase не настроен — считаем гостем (offline).
      _status = AuthStatus.guest;
      notifyListeners();
      return;
    }
    final session = SupabaseService.client?.auth.currentSession;
    _status = session != null ? AuthStatus.signedIn : AuthStatus.guest;
    if (session != null) loadSubscription();
    notifyListeners();
    _authSubscription = SupabaseService.client?.auth.onAuthStateChange.listen((data) {
      _status = data.session != null ? AuthStatus.signedIn : AuthStatus.guest;
      if (data.session != null) {
        loadSubscription();
        _listenSubscription();
      } else {
        _tier = 'none';
        // БАГ #2: сбрасываем статический тариф, чтобы не "утекли" лимиты
        // (например все регионы) от предыдущего Premium/Max аккаунта
        // новому пользователю/гостю на этом устройстве.
        TierManager.tier = 'none';
        _subChannel?.unsubscribe();
        _subChannel = null;
      }
      notifyListeners();
    });
    if (SupabaseService.client?.auth.currentUser != null) {
      _listenSubscription();
    }
  }

  RealtimeChannel? _subChannel;
  StreamSubscription<AuthState>? _authSubscription;

  /// Реальное время: смена тарифа на сервере мгновенно подхватывается.
  void _listenSubscription() {
    final client = SupabaseService.client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    _subChannel?.unsubscribe();
    _subChannel = client
        .channel('public:subscriptions')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'subscriptions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (_) => loadSubscription(),
        )
        .subscribe();
  }

  /// Загружает статус подписки из таблицы subscriptions.
  Future<void> loadSubscription() async {
    final client = SupabaseService.client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      final res = await client
          .from('subscriptions')
          .select('tier,expires_at')
          .eq('user_id', user.id)
          .maybeSingle();
      if (res != null) {
        final rawTier = res['tier'] as String? ?? 'none';
        final expiresRaw = res['expires_at'] as String?;
        // Если подписка есть, но срок истёк — возвращаемся к «none».
        final expired = expiresRaw != null &&
            DateTime.tryParse(expiresRaw)?.isBefore(DateTime.now()) == true;
        _tier = expired ? 'none' : rawTier;
        TierManager.tier = _tier;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('loadSubscription error: $e');
    }
  }

  /// Dev-инструмент: задаёт уровень подписки текущего пользователя напрямую.
  /// Используется для тестирования, пока нет покупок через RuStore.
  Future<void> setTier(String tier) async {
    // Сначала мгновенно обновляем локальный статус (для отклика UI).
    _tier = tier;
    TierManager.tier = tier;
    notifyListeners();
    final client = SupabaseService.client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      final expires = DateTime.now().add(const Duration(days: 365)).toIso8601String();
      await client.from('subscriptions').upsert({
        'user_id': user.id,
        'tier': tier,
        'expires_at': expires,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('setTier error: $e');
    }
  }

  /// Регистрация по email + паролю.
  Future<String?> signUp(String email, String password, {String? name}) async {
    try {
      final res = await SupabaseService.client!.auth.signUp(
        email: email,
        password: password,
        data: name != null && name.trim().isNotEmpty
            ? {'name': name.trim()}
            : null,
      );
      // Если требуется подтверждение почты — суze останутся гостем, но вернём флаг.
      return res.session != null ? null : 'confirm';
    } catch (e) {
      debugPrint('signUp error: $e');
      return _friendly(e);
    }
  }

  /// Вход.
  Future<String?> signIn(String email, String password) async {
    try {
      debugPrint('signIn: email=$email, password.length=${password.length}');
      await SupabaseService.client!.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return null;
    } catch (e) {
      debugPrint('signIn error: $e');
      return _friendly(e);
    }
  }

  Future<void> signOut() async {
    await SupabaseService.client?.auth.signOut();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
    _subChannel?.unsubscribe();
    _subChannel = null;
    super.dispose();
  }

  static String _friendly(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('invalid login')) return 'Неверный email или пароль';
    if (s.contains('already registered') || s.contains('already')) {
      return 'Такой email уже зарегистрирован';
    }
    if (s.contains('rate limit') || s.contains('429')) {
      return 'Превышен лимит писем подтверждения. Подождите немного и попробуйте ещё раз';
    }
    if (s.contains('signup_disabled') || s.contains('signups not allowed')) {
      return 'Регистрация отключена на сервере (Allow new users to sign up). '
          'Включите её в Supabase Dashboard → Auth → Sign In / Up';
    }
    if (s.contains('password')) {
      // Извлекаем точное сообщение от Supabase о требованиях к паролю
      final msg = e.toString();
      if (msg.contains('minimum')) {
        return 'Пароль слишком короткий (требуется минимум 8 символов)';
      }
      if (msg.contains('special') || msg.contains('symbol')) {
        return 'Пароль должен содержать спецсимвол';
      }
      if (msg.contains('uppercase') || msg.contains('capital')) {
        return 'Пароль должен содержать заглавную букву';
      }
      if (msg.contains('lowercase') || msg.contains('digit')) {
        return 'Пароль должен содержать цифру или строчную букву';
      }
      return 'Пароль не соответствует требованиям (8+ символов, буквы, цифры, спецсимволы)';
    }
    return 'Ошибка. Попробуйте ещё раз';
  }
}