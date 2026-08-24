import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
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
                MaterialPageRoute(
                    builder: (_) => const ResponsivePage(child: MoreScreen())),
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
                    icon: const Icon(Icons.logout),
                    label: const Text('Выйти'),
                    onPressed: () => auth.signOut(),
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
            icon: Icons.verified_user_outlined,
            title: 'Документы',
            onTap: () => _open(context, const DocumentsScreen()),
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
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ResponsivePage(child: screen)),
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
  bool _notificationsEnabled = true;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Уведомления'),
            subtitle: const Text('Напоминания о сезонах и документах'),
            value: _notificationsEnabled,
            onChanged: (value) =>
                setState(() => _notificationsEnabled = value),
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

/// Dev-кнопка переключения тарифа с индикатором вкл/выкл и описанием фич.
