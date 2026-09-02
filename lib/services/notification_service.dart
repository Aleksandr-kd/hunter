import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Сервис локальных уведомлений (напоминания о документах и сезонах).
class NotificationService {
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _tzReady = false;
  bool _initialized = false;

  NotificationService._() {
    _init();
  }

  Future<void> _init() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();
      _tzReady = true;
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      const settings = InitializationSettings(android: android, iOS: ios);
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (_) {
      // Не инициализирован (например в тестах).
    }
  }

  static bool get isReady => instance._initialized;

  /// Запланировать напоминание.
  /// notifyId — уникальный идентификатор; [title], [body] — текст.
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    if (!_tzReady) {
      tz.initializeTimeZones();
      _tzReady = true;
    }
    final local = tz.TZDateTime.from(scheduledAt, tz.local);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      local,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Напоминания',
          channelDescription: 'Напоминания о документах и сезонах',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancel(int id) => _plugin.cancel(id);

  /// Отменяет запланированные уведомления о сезонах по их id.
  ///
  /// [ids] — список id, которые реально были запланированы (сохраняется в
  /// SharedPreferences при планировании). Используется при смене/сбросе
  /// «Моего региона» и при выключении тумблера уведомлений о сезонах, чтобы
  /// в системе не остались «висячие» уведомления других регионов.
  Future<void> cancelAllSeasonReminders(List<int> ids) async {
    for (final id in ids) {
      await _plugin.cancel(id);
    }
  }

  /// Стабильный id уведомления по названию документа.
  ///
  /// Не зависит от позиции документа в списке. Значения лежат в [1..100] и не
  /// пересекаются с диапазоном id уведомлений сезонов (которые >= 103), что
  /// исключает коллизии между планировщиками.
  static int docNotifId(String title, int days) {
    final base = title.hashCode % 33; // 0..32
    final offset = switch (days) {
      30 => 1,
      14 => 2,
      _ => 3,
    };
    return base * 3 + offset + 1; // 1..100
  }

  /// Отменяет все уведомления-напоминания по документам.
  /// Вызывается при выключении переключателя уведомлений о документах.
  Future<void> cancelAllDocumentReminders() async {
    for (final days in const [30, 14, 3]) {
      // Пробегаемся по всему диапазону id документов [1..100].
      for (var base = 0; base < 33; base++) {
        final offset = switch (days) {
          30 => 1,
          14 => 2,
          _ => 3,
        };
        await _plugin.cancel(base * 3 + offset + 1);
      }
    }
  }
}