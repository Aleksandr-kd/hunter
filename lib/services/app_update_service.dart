import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Результат проверки наличия отложенного (FLEXIBLE) обновления через RuStore.
class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.available,
    this.updateAvailability,
    this.installStatus,
    this.errorCode,
    this.errorMessage,
  });

  /// Доступно ли обновление (updateAvailability == UPDATE_AVAILABLE).
  final bool available;

  /// Исходное значение updateAvailability из SDK.
  final int? updateAvailability;

  /// Исходное значение installStatus из SDK.
  final int? installStatus;

  /// Код ошибки (если проверка завершилась ошибкой, иначе null).
  final String? errorCode;

  /// Сообщение об ошибке.
  final String? errorMessage;

  bool get hasError => errorCode != null;
}

/// Обёртка над RuStore In-App Updates SDK (отложенное обновление FLEXIBLE).
///
/// Реализация только для Android: на других платформах канал недоступен,
/// метод безопасно возвращает «обновление недоступно».
class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const MethodChannel _channel =
      MethodChannel('ru.hunterapp/app_update');

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Проверяет наличие обновления и, если оно доступно, запускает
  /// отложенное (FLEXIBLE) обновление: показывает диалог RuStore,
  /// качает в фоне, по завершении скачивания предлагает установить и
  /// перезапускает приложение.
  ///
  /// Возвращает false, если платформа не Android или канал недоступен.
  Future<
      ({
        bool started,
        AppUpdateCheckResult result,
      })> checkForFlexibleUpdate() async {
    if (!_isAndroid) {
      return (
        started: false,
        result: const AppUpdateCheckResult(available: false),
      );
    }

    try {
      final dynamic raw = await _channel.invokeMethod('checkForFlexibleUpdate');
      if (raw is Map) {
        return (
          started: raw['available'] == true,
          result: AppUpdateCheckResult(
            available: raw['available'] == true,
            updateAvailability: raw['updateAvailability'] as int?,
            installStatus: raw['installStatus'] as int?,
          ),
        );
      }
      return (
        started: false,
        result: const AppUpdateCheckResult(available: false),
      );
    } on PlatformException catch (e) {
      return (
        started: false,
        result: AppUpdateCheckResult(
          available: false,
          errorCode: e.code,
          errorMessage: e.message,
        ),
      );
    } catch (e) {
      return (
        started: false,
        result: AppUpdateCheckResult(
          available: false,
          errorCode: 'UNEXPECTED',
          errorMessage: e.toString(),
        ),
      );
    }
  }
}
