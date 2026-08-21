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
    notifyListeners();
    SupabaseService.client?.auth.onAuthStateChange.listen((data) {
      _status = data.session != null ? AuthStatus.signedIn : AuthStatus.guest;
      notifyListeners();
    });
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