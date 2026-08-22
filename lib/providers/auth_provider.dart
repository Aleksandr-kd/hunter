import 'package:flutter/foundation.dart';

import '../services/supabase_service.dart';

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
    SupabaseService.client?.auth.onAuthStateChange.listen((data) {
      _status = data.session != null ? AuthStatus.signedIn : AuthStatus.guest;
      if (data.session != null) {
        loadSubscription();
      } else {
        _tier = 'none';
      }
      notifyListeners();
    });
  }

  /// Загружает статус подписки из таблицы subscriptions.
  Future<void> loadSubscription() async {
    final client = SupabaseService.client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      final res = await client
          .from('subscriptions')
          .select('tier')
          .eq('user_id', user.id)
          .maybeSingle();
      if (res != null) {
        _tier = res['tier'] as String? ?? 'none';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('loadSubscription error: $e');
    }
  }

  /// Dev-инструмент: задаёт уровень подписки текущего пользователя напрямую.
  /// Используется для тестирования, пока нет покупок через RuStore.
  Future<void> setTier(String tier) async {
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
      _tier = tier;
      notifyListeners();
    } catch (e) {
      debugPrint('setTier error: $e');
    }
  }

  /// Регистрация по email + паролю.
  Future<String?> signUp(String email, String password) async {
    try {
      final res = await SupabaseService.client!.auth.signUp(
        email: email,
        password: password,
      );
      // Если требуется подтверждение почты — суze останутся гостем, но вернём флаг.
      return res.session != null ? null : 'confirm';
    } catch (e) {
      return _friendly(e);
    }
  }

  /// Вход.
  Future<String?> signIn(String email, String password) async {
    try {
      await SupabaseService.client!.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  Future<void> signOut() async {
    await SupabaseService.client?.auth.signOut();
  }

  static String _friendly(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('invalid login')) return 'Неверный email или пароль';
    if (s.contains('already registered') || s.contains('already')) {
      return 'Такой email уже зарегистрирован';
    }
    if (s.contains('password')) return 'Пароль не соответствует требованиям';
    return 'Ошибка. Попробуйте ещё раз';
  }
}