import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/regions_provider.dart';
import 'theme/theme_provider.dart';
import 'screens/home_shell.dart';

/// Корневой виджет приложения.
class HunterApp extends StatelessWidget {
  const HunterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'Помощник охотника',
      theme: themeProvider.light,
      darkTheme: themeProvider.dark,
      themeMode: themeProvider.mode,
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
        ChangeNotifierProvider(create: (_) => RegionsProvider()),
      ],
      child: const HunterApp(),
    );
  }
}