import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/biometric_service.dart';

/// Блокировка приложения по биометрии (Face ID / Touch ID / отпечаток).
///
/// Включение — из Настроек, тут же просит подтвердить вход. После этого при
/// сворачивании приложение блокируется, лок-экран показывается при возврате
/// или холодном запуске. Выключение — только из Настроек (внутри приложения).
class LockProvider extends ChangeNotifier {
  static const _key = 'app_lock_enabled';

  bool _enabled = false;
  bool get enabled => _enabled;

  bool _locked = false;
  bool get locked => _locked;

  LockProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_key) ?? false;
      // Если блокировка включена — холодный запуск начинается с лок-экрана.
      _locked = _enabled;
      notifyListeners();
    } catch (_) {}
  }

  /// Включает блокировку (с подтверждением входа).
  /// Возвращает false, если устройство не поддерживает биометрию
  /// или пользователь не подтвердил вход.
  Future<bool> enable() async {
    if (!await BiometricService.instance.isDeviceSupported()) return false;
    final ok = await BiometricService.instance.authenticate();
    if (!ok) return false;
    _enabled = true;
    _locked = false; // пользователь только что подтвердил вход
    await _save();
    notifyListeners();
    return true;
  }

  /// Выключает блокировку (вызов из Настроек, внутри приложения).
  Future<void> disable() async {
    _enabled = false;
    _locked = false;
    await _save();
    notifyListeners();
  }

  /// Блокирует при сворачивании.
  void lock() {
    if (!_enabled || _locked) return;
    _locked = true;
    notifyListeners();
  }

  /// Снимает лок-экран после успешного входа.
  void unlock() {
    if (!_locked) return;
    _locked = false;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, _enabled);
    } catch (_) {}
  }
}