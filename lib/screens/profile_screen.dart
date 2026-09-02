import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/document_provider.dart';
import '../providers/lock_provider.dart';
import '../providers/regions_provider.dart';
import '../providers/seasons_provider.dart';
import '../providers/settings_sync_provider.dart';
import '../services/notification_service.dart';
import '../theme/k_colors.dart';
import '../theme/theme_provider.dart';
import '../widgets/dropdown_field.dart';
import '../widgets/glass_card.dart';
import '../widgets/responsive_page.dart';
import 'app_info_screen.dart';
import 'auth_screen.dart';
import 'documents_screen.dart';
import 'legality_screen.dart';
import 'privacy_policy_screen.dart';
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
            return Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.person,
                            size: 64, color: Colors.blueGrey),
                        const SizedBox(height: 16),
                        Text(
                          auth.userName != null && auth.userName!.isNotEmpty
                              ? 'Вы вошли как ${auth.userName}'
                              : 'Вы вошли в аккаунт',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Документы'),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const DocumentsScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        // Калькулятор доступен только автору; остальным — неактивен.
                        OutlinedButton.icon(
                          icon: const Icon(Icons.verified_user_outlined),
                          label: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Калькулятор законности'),
                              Text(
                                'Скоро появится',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          onPressed:
                              auth.userEmail?.toLowerCase() == 'als.d@mail.ru'
                                  ? () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const LegalityScreen(),
                                        ),
                                      );
                                    }
                                  : null,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Выйти'),
                    onPressed: () => auth.signOut(),
                  ),
                ),
              ],
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
          const _MyRegionCard(),
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

/// Карточка выбора «Моего региона» для уведомлений о сезонах.
///
/// Список регионов — тот же каталог, что в «Сроки охоты» (строится из
/// записей `hunting_seasons`), поэтому новые регионы появляются сами.
/// Первый пункт «Не выбран» сбрасывает выбор — напоминания о сезонах
/// при этом не приходят вовсе.
class _MyRegionCard extends StatelessWidget {
  const _MyRegionCard();

  static const String _noneItem = 'Не выбран';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final seasons = context.watch<SeasonsProvider>();
    final regions = seasons.regions;

    String selectedName;
    final my = seasons.myRegionId;
    final hasRegion =
        my != null && my.isNotEmpty && regions.any((r) => r.id == my);
    if (hasRegion) {
      selectedName =
          regions.firstWhere((r) => r.id == my).name;
    } else {
      selectedName = _noneItem;
    }

    final names = [
      _noneItem,
      for (final r in regions) r.name,
    ];

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок: иконка местоположения стоит напротив текста «Мой регион».
            Row(
              children: [
                Icon(Icons.place_outlined,
                    size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Мой регион',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DropdownField(
              value: selectedName,
              items: names,
              onSelectName: (name) {
                if (name == _noneItem) {
                  seasons.setMyRegion(null);
                  return;
                }
                for (final r in regions) {
                  if (r.name == name) {
                    seasons.setMyRegion(r.id);
                    return;
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Выберите регион для уведомлений.',
              style:
                  TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Экран «Настройки».
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final settings = context.watch<SettingsSyncProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Уведомления о сезонах'),
            subtitle: const Text('Напоминания за 7 и 3 дня до начала/конца сезона'),
            value: settings.notificationsSeasons,
            onChanged: (value) {
              settings.setNotifications(seasons: value);
              final seasonsProvider = context.read<SeasonsProvider>();
              if (value) {
                // Включили — перепланируем по «Моему региону».
                seasonsProvider.reschedule();
              } else {
                // Выключили — снимаем уже запланированные напоминания о сезонах.
                seasonsProvider.clearSeasonNotifications();
              }
            },
          ),
          // Напоминания включены, но «Мой регион» не выбран — такие уведомления
          // не будут планироваться, предупреждаем малиновой плашкой.
          Consumer<SeasonsProvider>(
            builder: (context, seasonsProvider, _) {
              final hasRegion = seasonsProvider.myRegionId != null &&
                  seasonsProvider.myRegionId!.isNotEmpty;
              if (!settings.notificationsSeasons || hasRegion) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kRestrictionsBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(Icons.info_outline,
                            size: 16, color: kRestrictions),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Выберите свой регион на странице «Дополнительно», '
                          'чтобы получать напоминания о сезонах',
                          style: const TextStyle(
                              fontSize: 13,
                              color: kRestrictions,
                              height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          SwitchListTile(
            title: const Text('Уведомления о документах'),
            subtitle: const Text('Напоминания за 30, 14 и 3 дня до истечения'),
            value: settings.notificationsDocuments,
            onChanged: (value) {
              settings.setNotifications(documents: value);
              // При выключении снимаем уже запланированные напоминания.
              if (!value) {
                NotificationService.instance
                    .cancelAllDocumentReminders();
              }
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Безопасность',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Consumer<LockProvider>(
            builder: (context, lock, _) {
              final messenger = ScaffoldMessenger.of(context);
              return SwitchListTile(
                title: const Text('Вход по Face ID / Touch ID'),
                subtitle: const Text(
                    'Блокировка приложения отпечатком пальца, Face ID '
                    'или PIN-кодом устройства'),
                value: lock.enabled,
                onChanged: (value) async {
                  if (value) {
                    final ok = await lock.enable();
                    if (!ok && context.mounted) {
                      messenger.showSnackBar(const SnackBar(
                        content: Text('Не удалось включить блокировку. '
                            'Подтвердите вход отпечатком/лицом или '
                            'PIN-кодом устройства'),
                      ));
                    }
                  } else {
                    await lock.disable();
                    if (context.mounted) {
                      messenger.showSnackBar(const SnackBar(
                        content: Text('Блокировка по биометрии отключена'),
                      ));
                    }
                  }
                },
              );
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
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = info.version);
      }
    } catch (_) {
      if (mounted) setState(() => _version = 'unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('О приложении')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Охотник\n\n'
                  'Справочник сроков охоты, электронный дневник '
                  'и напоминания о документах.\n\n'
                  'Версия $_version',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                GlassCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.info_outline,
                            color: Theme.of(context).colorScheme.primary),
                        title: const Text(
                          'Информация',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                            'Формат фото, хранение и синхронизация данных'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AppInfoScreen(),
                          ),
                        ),
                      ),
                      Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      ListTile(
                        leading: Icon(Icons.privacy_tip_outlined,
                            color: Theme.of(context).colorScheme.primary),
                        title: const Text(
                          'Политика обработки персональных данных',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text('Версия 1.0'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PrivacyPolicyScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
        child: InkWell(
          onTap: () => _doSync(context),
          borderRadius: BorderRadius.circular(24),
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
                Icon(Icons.refresh, size: 16, color: scheme.primary),
              ],
            ),
          ),
        ),
      );
    }

    // Нет данных для синхронизации — показываем кнопку.
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _doSync(context),
        borderRadius: BorderRadius.circular(24),
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
              Icon(Icons.refresh, size: 16, color: scheme.primary),
            ],
          ),
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
    final diary = context.read<DiaryProvider>();
    final documents = context.read<DocumentProvider>();
    final seasons = context.read<SeasonsProvider>();
    final auth = context.read<AuthProvider>();
    final theme = context.read<ThemeProvider>();
    final regions = context.read<RegionsProvider>();
    final settings = context.read<SettingsSyncProvider>();
    setState(() => _syncing = true);
    try {
      await SettingsSyncProvider.syncAll(
        diary: diary,
        documents: documents,
        seasons: seasons,
        auth: auth,
        theme: theme,
        regions: regions,
        settings: settings,
      );
      setState(() {
        _lastSync = DateTime.now();
        _lastError = null;
      });
      // После успешной синхронизации снимаем флаги «данные обновлены»,
      // чтобы баннер перешёл в состояние «Синхронизировано <время>».
      diary.consumeRemoteChange();
      seasons.consumeRemoteChange();
    } catch (e) {
      setState(() => _lastError = e.toString());
    } finally {
      setState(() => _syncing = false);
    }
  }
}

/// Dev-кнопка переключения тарифа с индикатором вкл/выкл и описанием фич.
