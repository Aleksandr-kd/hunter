import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/diary_provider.dart';
import 'providers/regions_provider.dart';
import 'services/tier_manager.dart';
import 'theme/theme_provider.dart';
import 'screens/home_shell.dart';

/// Корневой виджет приложения.
class HunterApp extends StatelessWidget {
  const HunterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    // Тёмная тема доступна только на платных тарифах.
    final darkAllowed = TierManager.isPremium;
    final effectiveMode = darkAllowed ? themeProvider.mode : ThemeMode.light;
    return MaterialApp(
      title: 'Охотник',
      theme: themeProvider.light,
      darkTheme: themeProvider.dark,
      themeMode: effectiveMode,
      debugShowCheckedModeBanner: false,
      home: const HomeShell(),
    );
  }
}

/// Корневое дерево провайдеров.
class HunterAppRoot extends StatelessWidget {
  const HunterAppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => RegionsProvider()),
        ChangeNotifierProvider(create: (_) => DiaryProvider()),
      ],
      child: const HunterApp(),
    );
  }
}