import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Обёртка над local_auth для входа по биометрии
/// (Face ID / Touch ID / отпечаток пальца с запасным PIN/паролем устройства).
class BiometricService {
  BiometricService._();

  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Может ли устройство показать биометрический диалог
  /// (есть биометрия либо PIN/пароль/графический ключ).
  Future<bool> isDeviceSupported() async {
    if (!isSupportedPlatform) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Запрос входа: биометрия + PIN/пароль устройства как запасной вариант.
  /// Возвращает false при отмене/неудаче/отсутствии поддержки.
  Future<bool> authenticate() async {
    if (!isSupportedPlatform) return false;
    try {
      return await _auth.authenticate(
        localizedReason: 'Разблокируйте приложение',
      );
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }
}