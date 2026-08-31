import 'package:flutter/material.dart';

import 'app.dart';
import 'services/app_update_service.dart';
import 'services/notification_service.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Инициализация локальных уведомлений.
  NotificationService.instance;
  // Инициализация Supabase (если сконфигурирован).
  await SupabaseService.init();
  runApp(const HunterAppRoot());

  // Отложенное обновление через RuStore (FLEXIBLE): проверяем после
  // первого кадра, чтобы не блокировать старт/биометрию. Только Android.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(milliseconds: 1500), () {
      AppUpdateService.instance.checkForFlexibleUpdate();
    });
  });
}