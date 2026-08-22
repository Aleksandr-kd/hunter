import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'auth_screen.dart';
import 'subscription_screen.dart';

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
                  // Dev-блок виден только автору.
                  if (auth.isDev) ...[
                    Text(
                      'Тестовое переключение тарифа:',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    _TierButton(
                      label: 'Бесплатная версия',
                      active: auth.tier == 'none',
                      onTap: () => auth.setTier('none'),
                      features: const [
                        'Сроки охоты в 1 регионе',
                        'Дневник: до 10 записей',
                        'Напоминания (базовые)',
                        'Реклама',
                      ],
                    ),
                    const SizedBox(height: 14),
                    _TierButton(
                      label: 'Версия Premium',
                      active: auth.tier == 'premium',
                      onTap: () => auth.setTier('premium'),
                      features: const [
                        'Без рекламы',
                        'Безлимитный дневник',
                        'Экспорт в PDF/CSV',
                        'Резервная копия',
                        'Тёмная тема',
                      ],
                    ),
                    const SizedBox(height: 14),
                    _TierButton(
                      label: 'Версия Premium +',
                      active: auth.tier == 'max',
                      onTap: () => auth.setTier('max'),
                      features: const [
                        'Всё из Premium',
                        'Все регионы сразу',
                        'Калькулятор законности',
                        'Расширенная статистика',
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
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
            icon: Icons.workspace_premium_outlined,
            title: 'Подписка',
            onTap: () => _open(context, const SubscriptionScreen()),
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
class _TierButton extends StatelessWidget {
  final String label;
  final bool active;
  final List<String> features;
  final VoidCallback onTap;

  const _TierButton({
    required this.label,
    required this.active,
    required this.features,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onColor = active ? scheme.onPrimary : null;
    return Material(
      color: active
          ? scheme.primary
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: onColor,
                      ),
                    ),
                  ),
                  Text(
                    active ? 'Вкл' : 'Выкл',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: active ? onColor : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (!active) ...[
                const SizedBox(height: 10),
                ...features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('•  ',
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                          Expanded(
                            child: Text(
                              f,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}