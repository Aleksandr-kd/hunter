import 'package:flutter/material.dart';

import 'app.dart';
import 'services/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Инициализация локальных уведомлений.
  NotificationService.instance;
  runApp(const HunterAppRoot());
}