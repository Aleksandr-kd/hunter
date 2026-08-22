import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/tier_manager.dart';
import '../theme/theme_provider.dart';
import 'auth_screen.dart';
import 'stats_screen.dart';
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
                            builder: (_) => const AuthScreen()),
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
            icon: Icons.bar_chart,
            title: 'Статистика и данные',
            onTap: () => _open(context, const StatsScreen()),
          ),
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
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
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
    return Card(
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
    final darkAllowed = TierManager.isPremium;
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
          SwitchListTile(
            title: const Text('Тёмная тема'),
            subtitle: Text(darkAllowed
                ? 'Тёмное оформление приложения'
                : 'Доступно на Premium и Premium+'),
            value: theme.mode == ThemeMode.dark,
            onChanged: darkAllowed
                ? (value) async {
                    await theme.setMode(
                        value ? ThemeMode.dark : ThemeMode.light);
                  }
                : null,
          ),
        ],
      ),
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
