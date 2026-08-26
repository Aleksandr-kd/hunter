import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../models/diary_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/diary_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/responsive_page.dart';
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAdd(context),
        child: const Icon(Icons.add),
      ),
      body: !diary.loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _DiarySummary(entries: diary.entries),
                if (diary.freeRemaining >= 0) _FreeLimitBanner(diary: diary),
                _DiaryFilter(
                  selected: _filter,
                  query: _query,
                  searchController: _searchCtrl,
                  onFilterChanged: (v) => setState(() => _filter = v),
                  onQueryChanged: (v) => setState(() => _query = v),
                ),
                Expanded(
                  child: _buildGroupedList(diary),
                ),
              ],
            ),
    );
  }

  Future<void> _openAdd(BuildContext context) async {
    final ok = await requireAuth(context);
    if (!ok || !context.mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => const ResponsivePage(child: _AddEntryScreen())),
    );
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
    final scheme = Theme.of(context).colorScheme;
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
    final items = <Widget>[];
    DateTime? currentMonth;
    const months = [
      '', 'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
      'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
    ];
    for (final e in sorted) {
      final monthKey = DateTime(e.date.year, e.date.month);
      if (currentMonth == null || monthKey != currentMonth) {
        currentMonth = monthKey;
        items.add(_MonthHeader(label: '${months[e.date.month]} ${e.date.year}'));
      }
      items.add(Dismissible(
        key: ValueKey(e.id ?? e.uuid ?? items.length),
        direction: DismissDirection.horizontal,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.edit_outlined),
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
          // startToEnd — изменить.
          _openDetail(context, e, () {});
          return false;
        },
        child: _EntryCard(
          entry: e,
          onDelete: () => diary.deleteEntry(e.id!),
          onTap: () => _openDetail(context, e, () {}),
        ),
      ));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: items,
    );
  }
}

/// Заголовок месяца в списке дневника.
class _MonthHeader extends StatelessWidget {
  final String label;
  const _MonthHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: scheme.onSurfaceVariant,
        ),
      ),
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
            decoration: InputDecoration(
              hintText: 'Поиск по виду или месту…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: scheme.surface.withValues(alpha: 0.5),
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
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _EntryCard({
    required this.entry,
    required this.onDelete,
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
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
            child: Row(
              children: [
                Icon(isResult ? Icons.check_circle : Icons.remove_red_eye_outlined,
                    color: accent),
                const SizedBox(width: 8),
                Expanded(child: Text(_title(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
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
                _Badge(icon: Icons.label_outlined,
                    text: isResult ? 'добыто' : 'наблюдение',
                    color: accent,
                    filled: true),
              ],
            ),
          ),
          if (entry.notes != null && entry.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Text(
                entry.notes!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.3),
              ),
            ),
          if (hasPhoto)
            Padding(
              padding: const EdgeInsets.only(top: 10),
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
    return '${d.day} ${months[d.month]} ${d.year}';
  }

  static String _fmtNum(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }
}

/// Компактный бейдж (иконка + текст) в карточке записи.
class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final bool filled;

  const _Badge({
    required this.icon,
    required this.text,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: filled ? color : color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

/// Компактная метка (чип) для даты/места/погоды в карточке записи.
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
    final dateStr = '${entry.date.day} ${months[entry.date.month]} ${entry.date.year}';

    return Scaffold(
      appBar: AppBar(title: const Text('Запись')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                  height: 260, width: double.infinity, fit: BoxFit.cover),
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
  const _AddEntryScreen({this.initial});

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
    if (picked != null) setState(() => _date = picked);
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Раздел «Результат».
            GlassCard(
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
                    if (_result == 'добыто') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _field(_weightCtrl,
                                label: 'Вес, кг',
                                keyboardType: TextInputType.number),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _field(_countCtrl,
                                label: 'Кол-во',
                                keyboardType: TextInputType.number),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _field(_methodCtrl, label: 'Способ охоты'),
                    ],
                  ],
                ),
              ),
            ),
            // Дата — крупной кнопкой.
            GlassCard(
              radius: 16,
              margin: const EdgeInsets.only(bottom: 12),
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.event, color: scheme.primary),
                    const SizedBox(width: 12),
                    Text('Дата', style: TextStyle(color: scheme.onSurfaceVariant)),
                    const Spacer(),
                    Text(_formatDate(_date),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            // Раздел «Что».
            GlassCard(
              radius: 16,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(scheme, 'Что'),
                    _field(_speciesCtrl, label: 'Вид (лось, кабан, утка…)', validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Укажите вид' : null),
                  ],
                ),
              ),
            ),
            // Раздел «Где».
            GlassCard(
              radius: 16,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(scheme, 'Где'),
                    _field(_locationCtrl, label: 'Место'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _getLocation,
                      icon: const Icon(Icons.my_location),
                      label: _latitude != null
                          ? const Text('Метка ✓')
                          : const Text('Гео'),
                    ),
                  ],
                ),
              ),
            ),
            // Раздел «Доп».
            GlassCard(
              radius: 16,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(scheme, 'Дополнительно'),
                    _field(_weatherCtrl, label: 'Погода'),
                    const SizedBox(height: 8),
                    _field(_notesCtrl, label: 'Заметки', maxLines: 3),
                  ],
                ),
              ),
            ),
            // Фото.
            OutlinedButton.icon(
              onPressed: _showPhotoSource,
              icon: const Icon(Icons.photo_camera_outlined),
              label: _photoPath == null ? const Text('Добавить фото') : const Text('Фото ✓'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Сохранить'),
              ),
            ),
          ],
        ),
      ),
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

  static Widget _field(TextEditingController c,
      {required String label, int maxLines = 1, TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.3),
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
}