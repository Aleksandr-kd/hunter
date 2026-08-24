import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/hunting_record.dart';
import '../providers/seasons_provider.dart';
import '../widgets/glass_card.dart';

/// Экран «Сроки охоты» — справочник сроков охоты.
///
/// Вверху фильтры: регион, сезон охоты, ресурс (выпадающие списки) и поиск.
/// Ниже — таблица найденных видов со сроками и кнопкой «Подробности».
/// При прокрутке списка панель фильтров сворачивается вверх.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  String? _regionId;
  String? _season;
  String? _resource;
  final _searchCtrl = TextEditingController();
  String _query = '';
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _defaults(SeasonsProvider p) {
    if (_regionId != null) return;
    final regions = p.regionIds;
    if (regions.isNotEmpty) _regionId = regions.first;
  }

  void _resetFilters() {
    setState(() {
      _season = null;
      _resource = null;
      _query = '';
      _searchCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SeasonsProvider>();
    _defaults(provider);
    final resources = provider.resourcesFor(_regionId ?? '');

    final filtered = provider.filter(
      regionId: _regionId,
      season: _season,
      resource: _resource,
      query: _query,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Сроки охоты')),
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: _FilterPanel(
              regions: provider.regionIds,
              selectedRegion: _regionId,
              regionNameOf: provider.regionName,
              seasons: SeasonsProvider.seasons,
              selectedSeason: _season,
              resources: resources,
              selectedResource: _resource,
              searchController: _searchCtrl,
              onRegionChanged: (v) => setState(() {
                _regionId = v;
                _resource = null;
              }),
              onSeasonChanged: (v) => setState(() => _season = v),
              onResourceChanged: (v) => setState(() => _resource = v),
              onSearchChanged: (v) => setState(() => _query = v),
              onReset: _resetFilters,
              hasActiveFilters: _season != null ||
                  _resource != null ||
                  _query.isNotEmpty,
            ),
          ),
          const SliverToBoxAdapter(child: _Disclaimer()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => filtered.isEmpty
                    ? const _EmptyResult()
                    : _RecordTile(record: filtered[i]),
                childCount: filtered.isEmpty ? 1 : filtered.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Панель фильтров: регион, сезон охоты, ресурс + поиск + кнопка сброса.
class _FilterPanel extends StatelessWidget {
  final List<String> regions;
  final String? selectedRegion;
  final String Function(String) regionNameOf;
  final List<String> seasons;
  final String? selectedSeason;
  final List<String> resources;
  final String? selectedResource;
  final TextEditingController searchController;
  final ValueChanged<String?> onRegionChanged;
  final ValueChanged<String?> onSeasonChanged;
  final ValueChanged<String?> onResourceChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onReset;
  final bool hasActiveFilters;

  const _FilterPanel({
    required this.regions,
    required this.selectedRegion,
    required this.regionNameOf,
    required this.seasons,
    required this.selectedSeason,
    required this.resources,
    required this.selectedResource,
    required this.searchController,
    required this.onRegionChanged,
    required this.onSeasonChanged,
    required this.onResourceChanged,
    required this.onSearchChanged,
    required this.onReset,
    required this.hasActiveFilters,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Сплошной тёмный фон на всю ширину — плашка фильтров.
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.95),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        children: [
          // Регион.
          _DropdownField(
            label: 'Регион',
            value: selectedRegion == null
                ? null
                : regionNameOf(selectedRegion!),
            items: regions.map((r) => regionNameOf(r)).toList(),
            onSelectName: (name) {
              final idx = regions.indexWhere((r) => regionNameOf(r) == name);
              if (idx >= 0) onRegionChanged(regions[idx]);
            },
          ),
          // Сезон охоты.
          _DropdownField(
            label: 'Сезон охоты',
            value: selectedSeason,
            items: seasons,
            onSelectName: onSeasonChanged,
          ),
          // Ресурс.
          _DropdownField(
            label: 'Охотничьи ресурсы',
            value: selectedResource,
            items: resources,
            onSelectName: onResourceChanged,
          ),
          // Поиск по названию дичи + сброс.
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Поиск вида (заяц, кабан…)',
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surface.withValues(alpha: 0.55),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: onSearchChanged,
                ),
              ),
              if (hasActiveFilters) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Сброс'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Выпадающее поле (без иконок).
class _DropdownField extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String> onSelectName;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onSelectName,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Название фильтра — своим рядком сверху, один цвет для всех.
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          // Пилюля с выбором.
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                hint: Text('Выберите',
                    style:
                        TextStyle(color: scheme.onSurfaceVariant, fontSize: 15)),
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 15,
                ),
                icon: Icon(Icons.arrow_drop_down,
                    color: scheme.onSurfaceVariant),
                items: items
                    .map((item) => DropdownMenuItem(
                          value: item,
                          child: Text(item,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onSelectName(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Предупреждение о справочном характере.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // Сдвиг на 2px вниз, чтобы текст не прилипал к верхнему фону фильтров.
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Кликабельный значок «i» — открывает страницу с примечанием.
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const _DisclaimerScreen(),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.info_outline,
                    size: 16, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Информация справочная. Сверяйтесь с официальными приказами.',
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Страница с юридически корректным примечанием к данным о сроках охоты.
class _DisclaimerScreen extends StatelessWidget {
  const _DisclaimerScreen();

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
                      'Данные о сроках и правилах охоты сформированы на основе '
                      'официальных нормативных правовых актов и открытых '
                      'источников государственных органов, регулирующих охотничье '
                      'хозяйство.'),
                  _P(text:
                      'При подготовке информации мы стремились к её '
                      'достоверности, однако не гарантируем полноту, '
                      'актуальность и безошибочность представленных сведений.'),
                  _P(text:
                      'Сроки охоты могут изменяться ежегодно решениями '
                      'уполномоченных органов, отдельными приказами и '
                      'региональными особенностями. Приведённые данные могут '
                      'отставать или отличаться от действующих правил.'),
                  _P(text:
                      'Перед выездом на охоту, оформлением разрешения на добычу '
                      'или планированием охоты обязательно сверяйте актуальные '
                      'сроки и ограничения с официальными источниками: '
                      'нормативными приказами региона и разъяснениями '
                      'уполномоченного органа субъекта Российской Федерации.'),
                  _P(text:
                      'Приложение не является официальным источником права и '
                      'не заменяет консультацию специалиста или ознакомление '
                      'с действующим законодательством. Пользователь использует '
                      'информацию на свой риск и несёт ответственность за '
                      'соблюдение правил охоты.'),
                  _P(text:
                      'Администрация приложения не несёт ответственности за '
                      'любые последствия, включая убытки, возникшие при '
                      'использовании или невозможности использования данной '
                      'информации.'),
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

class _EmptyResult extends StatelessWidget {
  const _EmptyResult();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          const Text('Ничего не найдено'),
          const SizedBox(height: 4),
          Text(
            'Попробуйте изменить фильтры или поиск',
            style:
                TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Карточка записи срока (выразительная).
class _RecordTile extends StatelessWidget {
  final HuntingRecord record;
  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final seasonColor = _seasonColor(scheme, record.season);
    final hasNewInfo = _hasNewInfo(record);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      radius: 16,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Вид дичи + цветная метка сезона.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    record.species,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16, height: 1.2),
                  ),
                ),
                if (record.season.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: seasonColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      record.season,
                      style: TextStyle(
                          color: seasonColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Сроки — крупно и выразительно.
            Row(
              children: [
                Icon(Icons.event, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  record.datesLabel,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Футер карточки: ресурс слева + кнопка «Подробности» справа.
            // Всегда один ряд — карточки одинаковой высоты независимо от кнопки.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: record.resource.isNotEmpty
                      ? Text(
                          record.resource,
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        )
                      : const SizedBox.shrink(),
                ),
                _DetailButton(
                  hasNewInfo: hasNewInfo,
                  onPressed: hasNewInfo
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _DetailScreen(record: record),
                            ),
                          )
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _seasonColor(ColorScheme scheme, String season) {
    switch (season) {
      case 'Весна':
        return const Color(0xFF43A047);
      case 'Лето':
        return const Color(0xFFF9A825);
      case 'Осень':
        return const Color(0xFFEF6C00);
      case 'Зима':
        return const Color(0xFF3949AB);
      default:
        return scheme.primary;
    }
  }
}

/// Кнопка «Подробности» в футере карточки. Занимает фиксированное место,
/// чтобы карточки были одинаковой высоты независимо от наличия кнопки.
class _DetailButton extends StatelessWidget {
  final bool hasNewInfo;
  final VoidCallback? onPressed;
  const _DetailButton({required this.hasNewInfo, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    const height = 38.0;
    return SizedBox(
      height: height,
      child: hasNewInfo
          ? FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: const Icon(Icons.info_outline, size: 18),
              label: const Text('Подробности'),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Есть ли в записи информация, которую ещё нет на карточке
/// (зона охоты или ограничения).
bool _hasNewInfo(HuntingRecord r) {
  final zone = r.zone;
  final restr = r.restrictions;
  final hasZone = zone != null && zone.isNotEmpty && zone.trim() != '';
  final hasRestr = restr != null && restr.isNotEmpty && restr.trim() != '';
  return hasRestr || hasZone;
}

/// Страница подробностей: только новая информация (зона охоты и ограничения).
class _DetailScreen extends StatelessWidget {
  final HuntingRecord record;
  const _DetailScreen({required this.record});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <Widget>[];

    final zone = record.zone;
    if (zone != null && zone.isNotEmpty) {
      items.add(GlassCard(
        tint: scheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Зоны охоты',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(zone, style: const TextStyle(height: 1.4)),
            ],
          ),
        ),
      ));
    }

    final restr = record.restrictions;
    if (restr != null && restr.isNotEmpty) {
      if (items.isNotEmpty) items.add(const SizedBox(height: 12));
      items.add(GlassCard(
        tint: scheme.errorContainer.withValues(alpha: 0.6),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ограничения',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(restr, style: const TextStyle(height: 1.4)),
            ],
          ),
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Подробности')),
      body: items.isEmpty
          ? const Center(child: Text('Нет дополнительной информации'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Полное название вида — переносится полностью, без многоточия.
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    record.species,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
                  ),
                ),
                ...items,
              ],
            ),
    );
  }
}