import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/diary_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/diary_provider.dart';
import '../services/export_service.dart';
import '../services/tier_manager.dart';
import 'auth_gate.dart';

/// Экран «Статистика и данные»: графики, экспорт PDF/CSV, резервная копия.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final diary = context.watch<DiaryProvider>();
    // Тариф для гейта функций Max.
    context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Статистика и данные')),
      body: !diary.loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summaryCards(context, diary),
                const SizedBox(height: 16),
                if (TierManager.isMax) ..._maxFeatures(context, diary)
                else _premiumUpsell(context),
                const SizedBox(height: 16),
                _exportCard(context, diary),
              ],
            ),
    );
  }

  Widget _summaryCards(BuildContext context, DiaryProvider diary) {
    final entries = diary.entries;
    final species = entries.map((e) => e.species).where((s) => s.isNotEmpty).toSet();
    final withLocation = entries.where((e) => e.location != null).length;
    final withPhoto = entries.where((e) => e.photoPath != null).length;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer,
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
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat(context, Icons.menu_book, '${entries.length}', 'записей'),
                _stat(context, Icons.pets, '${species.length}', 'видов'),
                _stat(context, Icons.place, '$withLocation', 'с гео'),
                _stat(context, Icons.photo, '$withPhoto', 'с фото'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  List<Widget> _maxFeatures(BuildContext context, DiaryProvider diary) {
    return [
      const Text('Фичи тарифа Max',
          style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      _FeatureCard(
        icon: Icons.bar_chart,
        title: 'Аналитика',
        subtitle: 'Распределение записей по месяцам и видам',
        onTap: () => _openAnalytics(context, diary),
      ),
      const SizedBox(height: 8),
      _FeatureCard(
        icon: Icons.verified_user,
        title: 'Калькулятор законности',
        subtitle: 'Проверка добычи по срокам охоты',
        onTap: () => _openLegality(context),
      ),
    ];
  }

  Widget _premiumUpsell(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: Icon(Icons.lock_outline,
            color: Theme.of(context).colorScheme.primary),
        title: const Text('Аналитика и калькулятор'),
        subtitle: const Text('Доступно на тарифе Max'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final ok = await requireAuth(context);
          if (ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Оформите подписку Max — подключение покупок после RuStore')),
            );
          }
        },
      ),
    );
  }

  Widget _exportCard(BuildContext context, DiaryProvider diary) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
          SnackBar(content: Text('Резервная копия сохранена')),
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

  void _openAnalytics(BuildContext context, DiaryProvider diary) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnalyticsScreen(diary: diary)),
    );
  }

  void _openLegality(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LegalityScreen()),
    );
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
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Аналитика: распределение по месяцам и видам (простая визуализация).
class AnalyticsScreen extends StatelessWidget {
  final DiaryProvider diary;

  const AnalyticsScreen({super.key, required this.diary});

  @override
  Widget build(BuildContext context) {
    final entries = diary.entries;
    final months = _monthDistribution(entries);
    final speciesCount = _speciesCount(entries);
    final maxMonth = months.values.fold<int>(0, (m, v) => v > m ? v : m);
    final maxSpecies =
        speciesCount.values.fold<int>(0, (m, v) => v > m ? v : m);

    return Scaffold(
      appBar: AppBar(title: const Text('Аналитика')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Записей по месяцам',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _BarChart(data: months, max: maxMonth),
          const SizedBox(height: 24),
          const Text('Записей по видам',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _BarChart(data: speciesCount, max: maxSpecies),
        ],
      ),
    );
  }

  static Map<String, int> _monthDistribution(List<DiaryEntry> entries) {
    const names = ['', 'Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн',
      'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
    final map = <String, int>{};
    for (final e in entries) {
      final key = names[e.date.month];
      map[key] = (map[key] ?? 0) + 1;
    }
    // Упорядочиваем по месяцу (только заполненные, в хронологическом порядке).
    final ordered = <String, int>{};
    for (final n in names.skip(1)) {
      if (map.containsKey(n)) ordered[n] = map[n]!;
    }
    return ordered;
  }

  static Map<String, int> _speciesCount(List<DiaryEntry> entries) {
    final map = <String, int>{};
    for (final e in entries) {
      if (e.species.isEmpty) continue;
      map[e.species] = (map[e.species] ?? 0) + 1;
    }
    return map;
  }
}

class _BarChart extends StatelessWidget {
  final Map<String, int> data;
  final int max;

  const _BarChart({required this.data, required this.max});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (data.isEmpty) {
      return const Text('Нет данных для отображения');
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final e in data.entries)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${e.value}', style: const TextStyle(fontSize: 11)),
                  const SizedBox(height: 2),
                  Container(
                    height: max == 0
                        ? 4
                        : 60 * (e.value / max),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(e.key, style: const TextStyle(fontSize: 9)),
                ],
              ),
            ),
          ),
      ],
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
    const months = ['', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];

    return Scaffold(
      appBar: AppBar(title: const Text('Калькулятор законности')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Упрощённая проверка по срокам Краснодарского края. '
                'Сверяйтесь с официальными документами перед охотой.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _speciesCtrl,
            decoration: const InputDecoration(
              labelText: 'Вид (кабан, заяц, утка…)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text('Дата: ${_date.day} ${months[_date.month]} ${_date.year}'),
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
              color: _result! ? scheme.primaryContainer : scheme.errorContainer,
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
                        style: const TextStyle(fontWeight: FontWeight.w600),
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