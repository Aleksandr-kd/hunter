import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/regions_provider.dart';
import '../providers/seasons_provider.dart';
import '../providers/settings_sync_provider.dart';
import '../theme/theme_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/responsive_page.dart';
import 'auth_screen.dart';
import 'documents_screen.dart';
import 'subscription_screen.dart';
import 'tier_switch_screen.dart';

/// Экран «Профиль» — подписка, настройки (тёмная тема).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Ещё',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MoreScreen()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            if (!auth.isSignedIn) {
              // Гость — предлагаем войти/зарегистрироваться.
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Войдите, чтобы использовать все функции',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text('Войти или зарегистрироваться'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const ResponsivePage(child: AuthScreen())),
                      );
                    },
                  ),
                ],
              );
            }
            // Авторизован.
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.person, size: 64, color: Colors.blueGrey),
                  const SizedBox(height: 16),
                  const Text(
                    'Вы вошли в аккаунт',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Документы'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DocumentsScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.logout),
                      label: const Text('Выйти'),
                      onPressed: () => auth.signOut(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Полноэкранное меню «Дополнительно» (открывается по трём полоскам).
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Дополнительно')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _MoreTile(
            icon: Icons.settings_outlined,
            title: 'Настройки',
            onTap: () => _open(context, const SettingsScreen()),
          ),
          _MoreTile(
            icon: Icons.workspace_premium_outlined,
            title: 'Подписка',
            onTap: () => _open(context, const SubscriptionScreen()),
          ),
          // Dev-пункт переключения тарифа (только для автора).
          Consumer<AuthProvider>(
            builder: (context, auth, _) => auth.isDev
                ? _MoreTile(
                    icon: Icons.swap_horiz,
                    title: 'Тариф (тест)',
                    onTap: () => _open(context, const TierSwitchScreen()),
                  )
                : const SizedBox.shrink(),
          ),
          _MoreTile(
            icon: Icons.info_outline,
            title: 'О приложении',
            onTap: () => _open(context, const AboutScreen()),
          ),
          // Баннер синхронизации.
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (!auth.isSignedIn) return const SizedBox.shrink();
              return _SyncBannerGlobal();
            },
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _MoreTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: scheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Экран «Настройки».
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsSeasons = true;
  bool _notificationsDocuments = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _notificationsSeasons = prefs.getBool('notifications_seasons') ?? true;
        _notificationsDocuments = prefs.getBool('notifications_documents') ?? true;
      });
    } catch (_) {}
  }

  Future<void> _saveNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_seasons', _notificationsSeasons);
      await prefs.setBool('notifications_documents', _notificationsDocuments);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Уведомления о сезонах'),
            subtitle: const Text('Напоминания за 7 и 3 дня до начала/конца сезона'),
            value: _notificationsSeasons,
            onChanged: (value) {
              setState(() => _notificationsSeasons = value);
              _saveNotifications();
            },
          ),
          SwitchListTile(
            title: const Text('Уведомления о документах'),
            subtitle: const Text('Напоминания за 30, 14 и 3 дня до истечения'),
            value: _notificationsDocuments,
            onChanged: (value) {
              setState(() => _notificationsDocuments = value);
              _saveNotifications();
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Тема оформления',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          _ThemeTile(
            title: 'Светлая',
            active: theme.mode == ThemeMode.light,
            icon: Icons.light_mode_outlined,
            onTap: () => theme.setMode(ThemeMode.light),
          ),
          _ThemeTile(
            title: 'Тёмная',
            active: theme.mode == ThemeMode.dark,
            icon: Icons.dark_mode_outlined,
            onTap: () => theme.setMode(ThemeMode.dark),
          ),
          _ThemeTile(
            title: 'Системная',
            active: theme.mode == ThemeMode.system,
            icon: Icons.settings_brightness_outlined,
            onTap: () => theme.setMode(ThemeMode.system),
          ),
        ],
      ),
    );
  }
}

/// Строка выбора темы.
class _ThemeTile extends StatelessWidget {
  final String title;
  final bool active;
  final IconData icon;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.title,
    required this.active,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: active ? scheme.primary : null),
      title: Text(title),
      trailing: active
          ? Icon(Icons.check_circle, color: scheme.primary)
          : const Icon(Icons.circle_outlined),
      onTap: onTap,
    );
  }
}

/// Экран «О приложении».
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('О приложении')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Охотник\n\n'
            'Справочник сроков охоты, электронный дневник '
            'и напоминания о документах.\n\n'
            'Версия 1.0.0',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Глобальный баннер синхронизации — внизу экрана «Дополнительно».
class _SyncBannerGlobal extends StatefulWidget {
  const _SyncBannerGlobal();

  @override
  State<_SyncBannerGlobal> createState() => _SyncBannerGlobalState();
}

class _SyncBannerGlobalState extends State<_SyncBannerGlobal> {
  bool _syncing = false;
  String? _lastError;
  DateTime? _lastSync;

  @override
  Widget build(BuildContext context) {
    final diary = context.watch<DiaryProvider>();
    final seasons = context.watch<SeasonsProvider>();
    final scheme = Theme.of(context).colorScheme;

    // Если есть изменения на сервере — показываем уведомление.
    if (diary.hasRemoteChange || seasons.hasRemoteChange) {
      return GlassCard(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: scheme.onTertiaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Данные обновлены на сервере',
                      style: TextStyle(
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      diary.consumeRemoteChange();
                      seasons.consumeRemoteChange();
                    },
                    child: const Text('Закрыть'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _doSync(context),
                    child: const Text('Синхронизировать'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Идёт синхронизация.
    if (_syncing) {
      return GlassCard(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              const Text('Синхронизация…'),
            ],
          ),
        ),
      );
    }

    // Ошибка синхронизации.
    if (_lastError != null) {
      return GlassCard(
        margin: const EdgeInsets.only(bottom: 8),
        tint: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ошибка синхронизации',
                  style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: () => _doSync(context),
                child: Text('Повторить', style: TextStyle(color: scheme.onErrorContainer)),
              ),
            ],
          ),
        ),
      );
    }

    // Последняя синхронизация.
    if (_lastSync != null) {
      return GlassCard(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_done_outlined, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Синхронизировано ${_fmt(_lastSync!)}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () => _doSync(context),
                child: Icon(Icons.refresh, size: 16, color: scheme.primary),
              ),
            ],
          ),
        ),
      );
    }

    // Нет данных для синхронизации — показываем кнопку.
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sync_outlined, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              'Нажмите для синхронизации',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: () => _doSync(context),
              child: Icon(Icons.refresh, size: 16, color: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _doSync(BuildContext context) async {
    setState(() => _syncing = true);
    try {
      await SettingsSyncProvider.syncAll(
        diary: context.read<DiaryProvider>(),
        seasons: context.read<SeasonsProvider>(),
        auth: context.read<AuthProvider>(),
        theme: context.read<ThemeProvider>(),
        regions: context.read<RegionsProvider>(),
      );
      setState(() {
        _lastSync = DateTime.now();
        _lastError = null;
      });
    } catch (e) {
      setState(() => _lastError = e.toString());
    } finally {
      setState(() => _syncing = false);
    }
  }
}

/// Dev-кнопка переключения тарифа с индикатором вкл/выкл и описанием фич.
