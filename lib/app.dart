import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/diary_provider.dart';
import 'providers/document_provider.dart';
import 'providers/regions_provider.dart';
import 'providers/seasons_provider.dart';
import 'providers/settings_sync_provider.dart';
import 'theme/theme_provider.dart';
import 'screens/home_shell.dart';

/// Корневой виджет приложения.
class HunterApp extends StatelessWidget {
  const HunterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    // Тему можно менять всем пользователям (пока монетизация выключена).
    return MaterialApp(
      title: 'Охотник',
      theme: themeProvider.light,
      darkTheme: themeProvider.dark,
      themeMode: themeProvider.mode,
      debugShowCheckedModeBanner: false,
      home: const HomeShell(),
    );
  }
}

/// Корневое дерево провайдеров + синхронизация настроек.
class HunterAppRoot extends StatefulWidget {
  const HunterAppRoot({super.key});

  @override
  State<HunterAppRoot> createState() => _HunterAppRootState();
}

class _HunterAppRootState extends State<HunterAppRoot> {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => RegionsProvider()),
        ChangeNotifierProvider(create: (_) => DiaryProvider()),
        ChangeNotifierProvider(create: (_) => DocumentProvider()),
        ChangeNotifierProvider(create: (_) => SeasonsProvider()),
      ],
      child: const _SyncHunterApp(),
    );
  }
}

/// Подключает синхронизацию настроек под дерево провайдеров.
class _SyncHunterApp extends StatefulWidget {
  const _SyncHunterApp();

  @override
  State<_SyncHunterApp> createState() => _SyncHunterAppState();
}

class _SyncHunterAppState extends State<_SyncHunterApp> {
  SettingsSyncProvider? _sync;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync ??= SettingsSyncProvider(
      theme: context.read<ThemeProvider>(),
      regions: context.read<RegionsProvider>(),
      auth: context.read<AuthProvider>(),
    );
  }

  @override
  void dispose() {
    _sync?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const HunterApp();
  }
}