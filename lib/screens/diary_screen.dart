import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../models/diary_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/diary_provider.dart';
import '../widgets/glass_card.dart';
import 'auth_gate.dart';

/// Экран «Дневник» — учёт добычи и наблюдений.
class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  String _filter = 'все'; // все | добыто | наблюдение
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Следим и за тарифом, чтобы лимит записей обновлялся реактивно.
    context.watch<AuthProvider>();
    final diary = context.watch<DiaryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Дневник')),
      floatingActionButton: GestureDetector(
        onLongPress: _chooseResult,
        child: FloatingActionButton(
          onPressed: () => _openAdd(context),
          child: const Icon(Icons.add),
        ),
      ),
      body: !diary.loaded
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _DiarySummary(entries: diary.entries)),
                if (diary.freeRemaining >= 0)
                  SliverToBoxAdapter(child: _FreeLimitBanner(diary: diary)),
                SliverToBoxAdapter(
                  child: _DiaryFilter(
                    selected: _filter,
                    query: _query,
                    searchController: _searchCtrl,
                    onFilterChanged: (v) => setState(() => _filter = v),
                    onQueryChanged: (v) => setState(() => _query = v),
                  ),
                ),
                SliverToBoxAdapter(child: _buildGroupedList(diary)),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
    );
  }

  Future<void> _openAdd(BuildContext context, {String? result}) async {
    final ok = await requireAuth(context);
    if (!ok || !context.mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => _AddEntryScreen(initialResult: result)),
    );
  }

  /// Долгое нажатие на «+» — выбор Наблюдение/Добыто.
  Future<void> _chooseResult() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.remove_red_eye_outlined),
              title: const Text('Наблюдение'),
              onTap: () => Navigator.pop(ctx, 'наблюдение'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Добыто'),
              onTap: () => Navigator.pop(ctx, 'добыто'),
            ),
          ],
        ),
      ),
    );
    if (v == null || !mounted) return;
    await _openAdd(context, result: v);
  }

  void _openDetail(BuildContext context, DiaryEntry e, VoidCallback onDelete) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EntryDetailScreen(entry: e, onDelete: onDelete),
      ),
    );
  }

  /// Список записей, сгруппированный по годам и месяцам с заголовками,
  /// с применением фильтра (все/добыто/наблюдение) и поиска.
  Widget _buildGroupedList(DiaryProvider diary) {
    var entries = diary.entries;
    if (_filter == 'добыто') {
      entries = entries.where((e) => e.result == 'добыто').toList();
    } else if (_filter == 'наблюдение') {
      entries = entries.where((e) => e.result != 'добыто').toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      entries = entries
          .where((e) =>
              e.species.toLowerCase().contains(q) ||
              (e.location?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    if (entries.isEmpty) {
      return _EmptyDiary(onAdd: () => _openAdd(context));
    }

    final sorted = List.of(entries)..sort((a, b) => b.date.compareTo(a.date));
    const months = [
      '', 'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
      'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
    ];
    // Группировка по месяцам (ключ ГГГГ-ММ).
    final groups = <String, List<DiaryEntry>>{};
    for (final e in sorted) {
      final key = '${e.date.year}-${e.date.month}';
      groups.putIfAbsent(key, () => []).add(e);
    }
    final items = <Widget>[];
    for (final entry in groups.entries) {
      final date = entry.value.first.date;
      items.add(_CollapsibleMonth(
        label: '${months[date.month]} ${date.year}',
        count: entry.value.length,
        child: Column(
          children: [
            for (final e in entry.value)
              Dismissible(
                key: ValueKey(e.id ?? e.uuid ?? DateTime.now().microsecondsSinceEpoch),
                direction: DismissDirection.horizontal,
                background: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF43A047),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.edit_outlined, color: Colors.white),
                ),
                secondaryBackground: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.endToStart) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Удалить запись?'),
                        content: const Text('Это действие нельзя отменить.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Отмена')),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Удалить')),
                        ],
                      ),
                    );
                    if (confirmed == true) diary.deleteEntry(e.id!);
                    return confirmed ?? false;
                  }
                  _openDetail(context, e, () => diary.deleteEntry(e.id!));
                  return false;
                },
                child: _EntryCard(
                  entry: e,
                  onTap: () => _openDetail(context, e, () => diary.deleteEntry(e.id!)),
                ),
              ),
          ],
        ),
      ));
    }
    return Column(
      children: items,
    );
  }
}

/// Заголовок месяца в списке дневника.
class _CollapsibleMonth extends StatefulWidget {
  final String label;
  final int count;
  final Widget child;
  const _CollapsibleMonth({required this.label, required this.count, required this.child});

  @override
  State<_CollapsibleMonth> createState() => _CollapsibleMonthState();
}

class _CollapsibleMonthState extends State<_CollapsibleMonth> {
  static String _plural(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return '$n запись';
    if (m10 >= 2 && m10 <= 4 && (m100 < 10 || m100 >= 20)) return '$n записи';
    return '$n записей';
  }

  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _open ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, size: 20, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _plural(widget.count),
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _open ? widget.child : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Баннер с остатком записей для бесплатной версии.
/// Компактная сводка-статистика дневника.
class _DiarySummary extends StatelessWidget {
  final List<DiaryEntry> entries;
  const _DiarySummary({required this.entries});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = entries.length;
    final species = entries.map((e) => e.species).where((s) => s.isNotEmpty).toSet().length;
    final hunted = entries.where((e) => e.result == 'добыто').length;

    return GlassCard(
      tint: scheme.primaryContainer.withValues(alpha: 0.4),
      radius: 16,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          children: [
            _Stat(label: 'записей', value: '$total'),
            _Stat(label: 'видов', value: '$species'),
            _Stat(label: 'добыто', value: '$hunted'),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: scheme.primary)),
          Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Панель фильтра дневника: сегмент «все/добыто/наблюдение» + поиск.
class _DiaryFilter extends StatelessWidget {
  final String selected;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<String> onQueryChanged;

  const _DiaryFilter({
    required this.selected,
    required this.query,
    required this.searchController,
    required this.onFilterChanged,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'все', label: Text('Все')),
              ButtonSegment(value: 'добыто', label: Text('Добыто')),
              ButtonSegment(value: 'наблюдение', label: Text('Наблюдения')),
            ],
            selected: {selected},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            onSelectionChanged: (s) => onFilterChanged(s.first),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: searchController,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Поиск по виду или месту…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: onQueryChanged,
          ),
        ],
      ),
    );
  }
}

class _FreeLimitBanner extends StatelessWidget {
  final DiaryProvider diary;

  const _FreeLimitBanner({required this.diary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final left = diary.freeRemaining;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: scheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                left <= 0
                    ? 'Лимит 10 записей исчерпан. Оформите подписку.'
                    : 'Бесплатная версия: осталось записей $left из 10.',
                style: TextStyle(
                    color: scheme.onTertiaryContainer, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDiary extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyDiary({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 64, color: scheme.primary),
              const SizedBox(height: 16),
              Text('Пока нет записей',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Заведите первую запись о добыче или наблюдении'),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Добавить запись'),
              ),
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback onTap;

  const _EntryCard({
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasPhoto = entry.photoPath != null && File(entry.photoPath!).existsSync();
    final isResult = entry.result == 'добыто';
    final accent = isResult ? scheme.primary : scheme.secondary;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      radius: 16,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Icon(isResult ? Icons.check_circle : Icons.remove_red_eye_outlined,
                    color: accent),
                const SizedBox(width: 8),
                Expanded(child: Text(_title(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _Chip(icon: Icons.event, text: _dateLabel(), color: scheme.onSurfaceVariant),
                if (entry.location != null && entry.location!.isNotEmpty)
                  _Chip(icon: Icons.place_outlined, text: entry.location!, color: scheme.onSurfaceVariant),
                if (entry.weather != null && entry.weather!.isNotEmpty)
                  _Chip(icon: Icons.cloud_outlined, text: entry.weather!, color: scheme.onSurfaceVariant),
                if (entry.weight != null && entry.result == 'добыто')
                  _Chip(icon: Icons.monitor_weight_outlined, text: '${_fmtNum(entry.weight)} кг', color: scheme.onSurfaceVariant),
                if (entry.count != null && entry.count! > 1)
                  _Chip(icon: Icons.numbers, text: '×${entry.count}', color: scheme.onSurfaceVariant),
                if (entry.method != null && entry.method!.isNotEmpty)
                  _Chip(icon: Icons.gps_fixed_outlined, text: entry.method!, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
          if (entry.notes != null && entry.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Text(
                entry.notes!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.3),
              ),
            ),
          if (hasPhoto)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                child: Image.file(
                  File(entry.photoPath!),
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _title() {
    final s = entry.species.isNotEmpty ? entry.species : 'Наблюдение';
    return s;
  }

  String _dateLabel() {
    const months = ['', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    final d = entry.date;
    return '${d.day} ${months[d.month]} ${d.year} • ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _fmtNum(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Chip({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

/// Экран добавления записи в дневник.
/// Детальный экран записи дневника: крупное фото, все поля, действия.
class _EntryDetailScreen extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback onDelete;
  const _EntryDetailScreen({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasPhoto = entry.photoPath != null && File(entry.photoPath!).existsSync();
    final isResult = entry.result == 'добыто';
    const months = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    final dateStr = '${entry.date.day} ${months[entry.date.month]} ${entry.date.year} • ${entry.date.hour.toString().padLeft(2, '0')}:${entry.date.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: const Text('Запись')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Детали всегда в maxWidth-обёртке (управляется ResponsivePage),
              // здесь просто широкий ListView.
              GlassCard(
                radius: 16,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.species.isEmpty ? 'Наблюдение' : entry.species,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      _DetailRow(icon: Icons.check_circle,
                          value: isResult ? 'добыто' : 'наблюдение',
                          color: isResult ? scheme.primary : scheme.secondary),
                      _DetailRow(icon: Icons.event, value: dateStr),
                      if (entry.location != null && entry.location!.isNotEmpty)
                        _DetailRow(icon: Icons.place_outlined, value: entry.location!),
                      if (entry.weather != null && entry.weather!.isNotEmpty)
                        _DetailRow(icon: Icons.cloud_outlined, value: entry.weather!),
                      if (entry.weight != null && entry.result == 'добыто')
                        _DetailRow(icon: Icons.monitor_weight_outlined,
                            value: '${_EntryCard._fmtNum(entry.weight)} кг'),
                      if (entry.count != null && entry.count! > 1)
                        _DetailRow(icon: Icons.numbers, value: '×${entry.count}'),
                      if (entry.method != null && entry.method!.isNotEmpty)
                        _DetailRow(icon: Icons.gps_fixed_outlined, value: entry.method!),
                    ],
                  ),
                ),
              ),
              if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                GlassCard(
                  radius: 16,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Заметки',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 6),
                        Text(entry.notes!, style: const TextStyle(height: 1.4)),
                      ],
                    ),
                  ),
                ),
              ],
              if (hasPhoto) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(File(entry.photoPath!),
                      height: wide ? 320 : 260, width: double.infinity, fit: BoxFit.cover),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _AddEntryScreen(initial: entry),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Изменить'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Удалить запись?'),
                            content: const Text('Это действие нельзя отменить.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Отмена')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Удалить')),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          onDelete();
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Удалить'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Строка с иконкой и значением в деталях записи.
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? color;
  const _DetailRow({required this.icon, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _AddEntryScreen extends StatefulWidget {
  final DiaryEntry? initial;
  final String? initialResult;
  const _AddEntryScreen({this.initial, this.initialResult});

  @override
  State<_AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<_AddEntryScreen> {
  final _form = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  final _speciesCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _weatherCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _result = 'наблюдение'; // добыто / увидено
  final _weightCtrl = TextEditingController();
  final _countCtrl = TextEditingController();
  final _methodCtrl = TextEditingController();
  String? _photoPath;
  double? _latitude;
  double? _longitude;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.initialResult != null) _result = widget.initialResult!;
    final i = widget.initial;
    if (i != null) {
      _date = i.date;
      _speciesCtrl.text = i.species;
      _locationCtrl.text = i.location ?? '';
      _weatherCtrl.text = i.weather ?? '';
      _notesCtrl.text = i.notes ?? '';
      _result = i.result.isEmpty ? 'наблюдение' : i.result;
      _photoPath = i.photoPath;
      _latitude = i.latitude;
      _longitude = i.longitude;
      _weightCtrl.text = i.weight?.toString() ?? '';
      _countCtrl.text = i.count?.toString() ?? '';
      _methodCtrl.text = i.method ?? '';
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _countCtrl.dispose();
    _methodCtrl.dispose();
    _speciesCtrl.dispose();
    _locationCtrl.dispose();
    _weatherCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _date = DateTime(
            picked.year,
            picked.month,
            picked.day,
            _date.hour,
            _date.minute,
          ));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _date = DateTime(
            _date.year,
            _date.month,
            _date.day,
            picked.hour,
            picked.minute,
          ));
    }
  }

  void _save() async {
    if (!_form.currentState!.validate()) return;
    final diary = context.read<DiaryProvider>();
    final entry = DiaryEntry(
      id: widget.initial?.id,
      uuid: widget.initial?.uuid,
      date: _date,
      species: _speciesCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      weather: _weatherCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      photoPath: _photoPath,
      latitude: _latitude,
      longitude: _longitude,
      result: _result,
      weight: double.tryParse(_weightCtrl.text.trim().replaceAll(',', '.')),
      count: int.tryParse(_countCtrl.text.trim()),
      method: _methodCtrl.text.trim().isEmpty ? null : _methodCtrl.text.trim(),
    );
    if (widget.initial != null) {
      await diary.updateEntry(entry);
    } else {
      final ok = await diary.addEntry(entry);
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Достигнут лимит 10 записей. Оформите подписку.'),
            ),
          );
        }
        return;
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, maxWidth: 1200);
    if (picked != null) setState(() => _photoPath = picked.path);
  }

  Future<void> _getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Служба геолокации выключена')),
        );
      }
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к геолокации')),
        );
      }
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
      });
    }
  }

  Future<void> _showPhotoSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Камера'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Галерея'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickPhoto(source);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editing = widget.initial != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Изменить запись' : 'Новая запись')),
      body: Form(
        key: _form,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: wide
                  ? _buildWideForm(context, scheme, editing)
                  : _buildNarrowForm(context, scheme, editing),
            );
          },
        ),
      ),
    );
  }

  /// Широкий (планшет/десктоп): «Что» и «Где» в две колонки, фото+кнопка внизу.
  List<Widget> _buildWideForm(BuildContext context, ColorScheme scheme, bool editing) {
    return [
      // Дата и Результат — ряд.
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _resultCard(context, scheme)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _dateCard(context, scheme)),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _whatCard(context, scheme, editing)),
          const SizedBox(width: 12),
          Expanded(child: _whereCard(context, scheme)),
        ],
      ),
      const SizedBox(height: 12),
      _extrasCards(context, scheme),
      const SizedBox(height: 12),
      _photoAndSave(context, scheme),
    ];
  }

  /// Узкий (телефон): вертикальная последовательность как раньше.
  List<Widget> _buildNarrowForm(BuildContext context, ColorScheme scheme, bool editing) {
    return [
      _resultCard(context, scheme),
      _dateCard(context, scheme),
      _whatCard(context, scheme, editing),
      _whereCard(context, scheme),
      _extrasCards(context, scheme),
      _photoAndSave(context, scheme),
    ];
  }

  Widget _resultCard(BuildContext context, ColorScheme scheme) {
    return GlassCard(
      radius: 16,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Результат',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'наблюдение', label: Text('Наблюдение')),
                ButtonSegment(value: 'добыто', label: Text('Добыто')),
              ],
              selected: {_result},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _result = s.first),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateCard(BuildContext context, ColorScheme scheme) {
    return GlassCard(
      radius: 16,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 360;
            final dateChip = InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_formatDate(_date), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            );
            final timeChip = InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time, size: 16, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text(_formatTime(_date), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            );
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text('Дата и время', style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: dateChip),
                      Container(width: 1, height: 24, color: scheme.outlineVariant, margin: const EdgeInsets.symmetric(horizontal: 4)),
                      Expanded(child: timeChip),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Icon(Icons.event, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Дата и время', style: TextStyle(color: scheme.onSurfaceVariant)),
                const Spacer(),
                dateChip,
                Container(width: 1, height: 24, color: scheme.outlineVariant, margin: const EdgeInsets.symmetric(horizontal: 4)),
                timeChip,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _whatCard(BuildContext context, ColorScheme scheme, bool editing) {
    return GlassCard(
      radius: 16,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(scheme, 'Что'),
            _field(_speciesCtrl, scheme,
                label: 'Вид (лось, кабан, утка…)',
                maxLength: 50,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Укажите вид' : null),
          ],
        ),
      ),
    );
  }

  Widget _whereCard(BuildContext context, ColorScheme scheme) {
    return GlassCard(
      radius: 16,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(scheme, 'Где'),
            _field(_locationCtrl, scheme, label: 'Место', maxLength: 50),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _getLocation,
              icon: const Icon(Icons.my_location),
              label: _latitude != null
                  ? const Text('Метка ✓')
                  : const Text('Гео'),
            ),
            if (_result == 'добыто') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _field(_weightCtrl, scheme,
                        label: 'Вес, кг',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_WeightFormatter(maxDigits: 3)]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _field(_countCtrl, scheme,
                        label: 'Кол-во',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _field(_methodCtrl, scheme, label: 'Способ охоты', maxLength: 50),
            ],
          ],
        ),
      ),
    );
  }

  Widget _extrasCards(BuildContext context, ColorScheme scheme) {
    return _CollapsibleFormSection(
      title: 'Дополнительно',
      child: GlassCard(
        radius: 16,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(_weatherCtrl, scheme, label: 'Погода', maxLength: 50),
              const SizedBox(height: 8),
              _field(_notesCtrl, scheme,
                  label: 'Заметки',
                  maxLines: 3,
                  maxLength: 200),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoAndSave(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _showPhotoSource,
          icon: const Icon(Icons.photo_camera_outlined),
          label: _photoPath == null ? const Text('Добавить фото') : const Text('Фото ✓'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _save,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Сохранить'),
          ),
        ),
      ],
    );
  }

  static Widget _sectionTitle(ColorScheme scheme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title,
          style:
              TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
    );
  }

  static Widget _field(TextEditingController c, ColorScheme scheme,
      {required String label,
      int maxLines = 1,
      int? maxLength,
      TextInputType? keyboardType,
      List<TextInputFormatter>? inputFormatters,
      String? Function(String?)? validator}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(color: scheme.onSurface),
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        filled: true,
        // Как у инпута «Поиск по виду или месту» — адаптивный серый фон.
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      '', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }

  static String _formatTime(DateTime d) {
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

/// Форматтер веса: максимум [maxDigits] целых цифр, опционально запятая/точка
/// и до 2 знаков после (например «123,45»). Принимает и запятую, и точку.
class _WeightFormatter extends TextInputFormatter {
  final int maxDigits;
  const _WeightFormatter({this.maxDigits = 3});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.replaceAll(',', '.');
    // Разрешаем: до maxDigits цифр целых + (опц.) разделитель + до 2 дробных.
    final allowed = RegExp('^(\\d{0,$maxDigits})(\\.\\d{0,2})?')
        .firstMatch(text)
        ?.group(0) ??
        '';
    // Возвращаем как введено, но с пониманием точки.
    final out = allowed.replaceAll('.', ',');
    if (newValue.text == out) return newValue;
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

/// Сворачиваемый раздел формы (по умолчанию закрыт).
class _CollapsibleFormSection extends StatefulWidget {
  final String title;
  final Widget child;
  const _CollapsibleFormSection({required this.title, required this.child});

  @override
  State<_CollapsibleFormSection> createState() => _CollapsibleFormSectionState();
}

class _CollapsibleFormSectionState extends State<_CollapsibleFormSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _open ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more,
                      size: 20, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 4),
                Text(widget.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _open ? widget.child : const SizedBox.shrink(),
        ),
      ],
    );
  }
}