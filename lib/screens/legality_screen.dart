import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/hunting_record.dart';
import '../providers/seasons_provider.dart';
import '../services/legality_service.dart';
import '../widgets/glass_card.dart';

/// Калькулятор законности охоты.
///
/// Виды, сроки и ограничения приходят с сервера (таблица `hunting_seasons`
/// через [SeasonsProvider]) — никакого хардкода правил. Если на сервере
/// изменят сроки, калькулятор начнёт считать по новым данным автоматически.
class LegalityScreen extends StatefulWidget {
  const LegalityScreen({super.key});

  @override
  State<LegalityScreen> createState() => _LegalityScreenState();
}

class _LegalityScreenState extends State<LegalityScreen> {
  final _speciesCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  String _regionId = 'krasnodar';
  LegalityVerdict? _verdict;
  List<String> _suggestions = const [];

  @override
  void dispose() {
    _speciesCtrl.dispose();
    super.dispose();
  }

  List<HuntingRecord> _recordsFor(SeasonsProvider seasons) =>
      seasons.records.where((r) => r.regionId == _regionId).toList();

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(now.year - 1);
    final last = DateTime(now.year + 2, 12, 31);
    final initial = _date.isBefore(first) || _date.isAfter(last)
        ? today
        : _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _onQueryChanged(String text) {
    final seasons = context.read<SeasonsProvider>();
    setState(() {
      _suggestions = LegalityService.suggestions(_recordsFor(seasons), text);
      _verdict = null;
    });
  }

  void _pickSpecies(String species) {
    setState(() {
      _speciesCtrl.text = species;
      _suggestions = const [];
      _verdict = null;
    });
  }

  void _check() {
    final seasons = context.read<SeasonsProvider>();
    setState(() {
      _verdict = LegalityService.check(
        regionRecords: seasons.records
            .where((r) => r.regionId == _regionId)
            .toList(),
        query: _speciesCtrl.text,
        date: _date,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    const months = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Калькулятор законности')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _regionId,
            decoration: const InputDecoration(
              labelText: 'Регион',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final r in context.read<SeasonsProvider>().regions)
                DropdownMenuItem(value: r.id, child: Text(r.name)),
            ],
            onChanged: (v) => setState(() {
              _regionId = v ?? _regionId;
              _suggestions = const [];
              _verdict = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _speciesCtrl,
            textCapitalization: TextCapitalization.sentences,
            onChanged: _onQueryChanged,
            decoration: const InputDecoration(
              labelText: 'Вид (например, кабан)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _suggestions)
                  ActionChip(
                    label: Text(s),
                    onPressed: () => _pickSpecies(s),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _LegalityDisclaimer(),
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
          if (_verdict != null) ...[
            const SizedBox(height: 16),
            _VerdictCard(verdict: _verdict!),
          ],
        ],
      ),
    );
  }
}

/// Карточка результата проверки.
class _VerdictCard extends StatelessWidget {
  final LegalityVerdict verdict;

  const _VerdictCard({required this.verdict});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final IconData icon;
    final String headline;

    if (!verdict.speciesFound) {
      bg = scheme.surfaceContainerHighest;
      icon = Icons.help_outline;
      headline = 'Вид не найден в перечне охотничьих ресурсов региона.';
    } else if (!verdict.allowed && verdict.forbidden != null) {
      bg = scheme.errorContainer;
      icon = Icons.cancel;
      headline = 'Охота запрещена на этот срок.';
    } else if (!verdict.allowed) {
      bg = scheme.errorContainer;
      icon = Icons.event_busy;
      headline = 'В этот срок охота не предусмотрена.';
    } else {
      bg = scheme.primaryContainer;
      icon = Icons.check_circle;
      headline = 'По данным справочника охота допустима.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          tint: bg,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    headline,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (verdict.forbidden?.restrictions != null &&
            verdict.forbidden!.restrictions!.isNotEmpty) ...[
          const SizedBox(height: 8),
          GlassCard(
            tint: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                verdict.forbidden!.restrictions!,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
        if (verdict.allowed && _hasConditions(verdict.active)) ...[
          const SizedBox(height: 8),
          GlassCard(
            tint: scheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Действуют ограничения: '
                '${_conditionsText(verdict.active)}',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
        ],
        if (verdict.matches.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final r in verdict.matches) _PeriodTile(record: r, scheme: scheme),
        ],
      ],
    );
  }

  static bool _hasConditions(List<HuntingRecord> records) =>
      records.any((r) =>
          r.restrictions != null && r.restrictions!.isNotEmpty);

  static String _conditionsText(List<HuntingRecord> records) =>
      records
          .map((r) => r.restrictions)
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' ');
}

/// Строка записи справочника: вид, сроки, зона, ограничения.
class _PeriodTile extends StatelessWidget {
  final HuntingRecord record;
  final ColorScheme scheme;

  const _PeriodTile({required this.record, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      tint: scheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.species,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${record.season} · ${record.datesLabel}'
              '${record.zone != null && record.zone!.isNotEmpty ? ' · зона: ${record.zone}' : ''}',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            if (record.restrictions != null &&
                record.restrictions!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                record.restrictions!,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Кликабельное предупреждение о справочном характере (вся строка кликабельна).
class _LegalityDisclaimer extends StatelessWidget {
  const _LegalityDisclaimer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const _LegalityDisclaimerScreen(),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.info_outline, size: 16, color: scheme.error),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Информация справочная. Сверяйтесь с официальными '
                    'документами перед охотой.',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Страница с примечанием о справочном характере.
class _LegalityDisclaimerScreen extends StatelessWidget {
  const _LegalityDisclaimerScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('О данных')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            tint: scheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Информация носит справочный характер',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  SizedBox(height: 12),
                  _P(text:
                      'Проверка законности выполняется по срокам охоты из '
                      'справочника. Данные обновляются с сервера и '
                      'сформированы на основе официальных нормативных '
                      'правовых актов и открытых источников государственных '
                      'органов, регулирующих охотничье хозяйство.'),
                  _P(text:
                      'Сроки охоты могут изменяться ежегодно решениями '
                      'уполномоченных органов, отдельными приказами и '
                      'региональными особенностями. Приведённые данные могут '
                      'отставать или отличаться от действующих правил.'),
                  _P(text:
                      'Перед выездом на охоту, оформлением разрешения на '
                      'добычу или планированием охоты обязательно сверяйте '
                      'актуальные сроки и ограничения с официальными '
                      'источниками: нормативными приказами региона и '
                      'разъяснениями уполномоченного органа субъекта '
                      'Российской Федерации.'),
                  _P(text:
                      'Приложение не является официальным источником права и '
                      'не заменяет консультацию специалиста или ознакомление '
                      'с действующим законодательством. Пользователь '
                      'использует информацию на свой риск и несёт '
                      'ответственность за соблюдение правил охоты.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _P extends StatelessWidget {
  final String text;
  const _P({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: const TextStyle(height: 1.4)),
    );
  }
}
