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
}