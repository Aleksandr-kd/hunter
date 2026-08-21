import 'package:flutter/material.dart';

import 'app.dart';
import 'services/notification_service.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Инициализация локальных уведомлений.
  NotificationService.instance;
  // Инициализация Supabase (если сконфигурирован).
  await SupabaseService.init();
  runApp(const HunterAppRoot());
}