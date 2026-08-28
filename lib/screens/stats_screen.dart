import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/diary_provider.dart';
import '../services/analytics_service.dart';
import '../services/export_service.dart';
import '../services/tier_manager.dart';
import '../widgets/glass_card.dart';
import '../widgets/stats_widgets.dart';
import 'auth_gate.dart';

/// Экран «Статистика и данные»: графики, экспорт PDF/CSV, резервная копия.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  @override
  Widget build(BuildContext context) {
    final diary = context.watch<DiaryProvider>();
    context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Статистика и данные')),
      body: !diary.loaded
          ? const SkeletonStatsScreen()
          : RefreshIndicator(
              onRefresh: () => diary.load(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _summaryCards(context, diary),
                  const SizedBox(height: 16),
                  SmartInsightsCard(
                    insights: AnalyticsService.generateInsights(diary.entries),
                  ),
                  const SizedBox(height: 16),
                  ..._analyticsSection(context, diary),
                  const SizedBox(height: 16),
                  ..._toolsSection(context),
                  const SizedBox(height: 16),
                  _exportCard(context, diary),
                ],
              ),
            ),
    );
  }

  Widget _summaryCards(BuildContext context, DiaryProvider diary) {
    final entries = diary.entries;
    final species =
        entries.map((e) => e.species).where((s) => s.isNotEmpty).toSet();
    final withLocation = entries.where((e) => e.location != null).length;
    final withPhoto = entries.where((e) => e.photoPath != null).length;
    final trend = AnalyticsService.calculateTrend(entries);

    return GlassCard(
      tint: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ваша статистика',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                AnimatedStatCard(
                  icon: Icons.menu_book,
                  label: 'записей',
                  endValue: entries.length,
                  trend: trend,
                ),
                AnimatedStatCard(
                  icon: Icons.pets,
                  label: 'видов',
                  endValue: species.length,
                ),
                AnimatedStatCard(
                  icon: Icons.place,
                  label: 'с гео',
                  endValue: withLocation,
                ),
                AnimatedStatCard(
                  icon: Icons.photo,
                  label: 'с фото',
                  endValue: withPhoto,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _analyticsSection(BuildContext context, DiaryProvider diary) {
    final entries = diary.entries;
    if (entries.isEmpty) {
      return [
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Добавьте первую запись, чтобы увидеть аналитику',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      ActivityLineChart(
          data: AnalyticsService.monthDistribution(entries)),
      const SizedBox(height: 16),
      SpeciesPieChart(
          data: AnalyticsService.speciesDistribution(entries)),
      const SizedBox(height: 16),
      TopSpeciesList(
          species: AnalyticsService.getTopSpecies(entries)),
      const SizedBox(height: 16),
      SeasonComparisonCard(
          seasons: AnalyticsService.seasonDistribution(entries)),
    ];
  }

  List<Widget> _toolsSection(BuildContext context) {
    return [
      const Text('Инструменты',
          style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      _FeatureCard(
        icon: Icons.verified_user,
        title: 'Калькулятор законности',
        subtitle: 'Проверка добычи по срокам охоты',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LegalityScreen()),
        ),
      ),
    ];
  }

  Widget _exportCard(BuildContext context, DiaryProvider diary) {
    return GlassCard(
      tint: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Экспорт и резервная копия (Premium+)',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Экспорт в PDF'),
            subtitle: const Text('Красивый отчёт со всеми записями'),
            onTap: () => _doExport(context, diary, isPdf: true),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Экспорт в CSV'),
            subtitle: const Text('Откроется в таблицах (Excel)'),
            onTap: () => _doExport(context, diary, isPdf: false),
          ),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Резервная копия'),
            subtitle: const Text('Сохранить дневник в файл (JSON)'),
            onTap: () => _doBackup(context, diary, saveDialog: true),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Сохранить копию в документы'),
            subtitle: const Text('Без диалога — сразу в папку приложения'),
            onTap: () => _doBackup(context, diary, saveDialog: false),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Восстановить из резервной копии'),
            subtitle: const Text('Выбрать JSON-файл и восстановить записи'),
            onTap: () => _doRestore(context, diary),
          ),
        ],
      ),
    );
  }

  Future<void> _doExport(BuildContext context, DiaryProvider diary,
      {required bool isPdf}) async {
    final ok = await _ensurePremium(context);
    if (!ok || !context.mounted) return;
    if (diary.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет записей для экспорта')),
      );
      return;
    }
    try {
      final file = isPdf
          ? await ExportService.exportPdf(diary.entries)
          : await ExportService.exportCsv(diary.entries);
      if (file == null || !context.mounted) return;
      await ExportService.share(file);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }

  Future<void> _doBackup(BuildContext context, DiaryProvider diary,
      {required bool saveDialog}) async {
    final ok = await _ensurePremium(context);
    if (!ok || !context.mounted) return;
    try {
      final file = await ExportService.backupDiary(diary.entries,
          saveDialog: saveDialog);
      if (file == null) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Резервная копия сохранена')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка резервной копии: $e')),
        );
      }
    }
  }

  /// Восстановление дневника из выбранного JSON-файла резервной копии.
  Future<void> _doRestore(BuildContext context, DiaryProvider diary) async {
    final ok = await _ensurePremium(context);
    if (!ok || !context.mounted) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Восстановить дневник?'),
            content: const Text(
                'Будут добавлены записи из файла. Существующие записи с\n' 
                'такими же ID не дублируются. Продолжить?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Выбрать файл'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    final json = await ExportService.readBackupFile();
    if (json == null || !context.mounted) return;
    final entries = ExportService.parseBackup(json);
    if (entries == null || entries.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Файл не содержит записей или повреждён')),
        );
      }
      return;
    }
    final added = await diary.restoreFromBackup(entries);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Восстановлено записей: $added')),
      );
    }
  }

  /// Проверяет, что пользователь вошёл и у него активен платный тариф.
  Future<bool> _ensurePremium(BuildContext context) async {
    if (TierManager.isPremium) return true;
    final authed = await requireAuth(context);
    if (!authed || TierManager.isPremium) return true;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Функция доступна на тарифах Premium и Max')),
      );
    }
    return false;
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      tint: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading:
            Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Упрощённый калькулятор законности добычи.
class LegalityScreen extends StatefulWidget {
  const LegalityScreen({super.key});

  @override
  State<LegalityScreen> createState() => _LegalityScreenState();
}

class _LegalityScreenState extends State<LegalityScreen> {
  final _speciesCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool? _result;

  @override
  void dispose() {
    _speciesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _check() {
    final species = _speciesCtrl.text.trim().toLowerCase();
    if (species.isEmpty) {
      setState(() => _result = null);
      return;
    }
    // Упрощённая логика (1 регион — Краснодарский край).
    final month = _date.month;
    // Пермиссивная проверка по усреднённым сезонам.
    bool allowed = true;
    if (species.contains('кабан')) {
      // 1 июня – 28 фев.
      allowed = month >= 6 || month <= 2;
    } else if (species.contains('заяц')) {
      // ноябрь – январь.
      allowed = month == 11 || month == 12 || month == 1;
    } else if (species.contains('утк') || species.contains('гус') ||
        species.contains('водопл')) {
      // сен – дек.
      allowed = month >= 9;
    } else if (species.contains('олен')) {
      // июн – янв.
      allowed = month >= 6 || month == 1;
    } else if (species.contains('косул')) {
      // июн – окт.
      allowed = month >= 6 && month <= 10;
    }
    setState(() => _result = allowed);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const months = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Калькулятор законности')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            tint: scheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Упрощённая проверка по срокам Краснодарского края.\n'
                'Сверяйтесь с официальными документами перед охотой.',
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _speciesCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Вид (кабан, заяц, утка…)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(
                'Дата: ${_date.day} ${months[_date.month]} ${_date.year}'),
            onTap: _pickDate,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _check,
            child: const Text('Проверить'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: _result!
                  ? scheme.primaryContainer
                  : scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _result! ? Icons.check_circle : Icons.cancel,
                      color: _result!
                          ? scheme.onPrimaryContainer
                          : scheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _result!
                            ? 'По упрощённой модели охота допустима.'
                            : 'По упрощённой модели охота не предусмотрена.',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
