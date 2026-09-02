import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/hunting_record.dart';
import '../providers/seasons_provider.dart';
import '../theme/k_colors.dart';
import '../widgets/dropdown_field.dart';
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
  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _defaults(SeasonsProvider p) {
    final regions = p.regionIds;
    // Регионы приходят с сервера и могут измениться: если текущий выбор
    // исчез из каталога — сбрасываем на первый (DropdownButton не принимает
    // value, отсутствующий в items).
    if (_regionId != null && !regions.contains(_regionId)) {
      _regionId = null;
    }
    if (_regionId != null) return;
    if (regions.isNotEmpty) {
      // M6: _defaults вызывается из build() — setState здесь запрещён
      // («marked as needing to build during build»). Прямая запись уже
      // во время build безопасна: последующие строки build читают новое
      // значение, а пересборка произойдёт при следующем notifyListeners.
      _regionId = regions.first;
    }
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
        primary: true,
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
            sliver: _RecordsGrid(records: filtered),
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
    // Фон панели чуть темнее самих инпутов — 4 поля не сливаются.
    final panelColor = Color.alphaBlend(
      Colors.black.withValues(alpha: 0.07),
      scheme.surfaceContainerHighest,
    );
    return Container(
      width: double.infinity,
      color: panelColor,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Builder(
        builder: (context) {
          final maxW = MediaQuery.sizeOf(context).width;
          // Три выпадающих фильтра.
          final dropdowns = [
            DropdownField(
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
            DropdownField(
              label: 'Сезон охоты',
              value: selectedSeason,
              items: seasons,
              onSelectName: onSeasonChanged,
            ),
            DropdownField(
              label: 'Охотничьи ресурсы',
              value: selectedResource,
              items: resources,
              onSelectName: onResourceChanged,
            ),
          ];
          // Поиск (+кнопка «Сброс»). В ряду с дропдаунами выравнивается
          // с их полями (alignWithDropdown), в столбике — без смещения.
          // <468 — столбик; 468–820 — компактная сетка 2×2 (гориз. телефон);
          // >=820 — все четыре в одну строку (планшет).
          if (maxW >= 820) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: dropdowns[0],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: dropdowns[1],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: dropdowns[2],
                  ),
                ),
                Expanded(
                  child: _buildSearchRow(context, hasActiveFilters,
                      alignWithDropdown: true),
                ),
              ],
            );
          }
          if (maxW >= 468) {
            // 2×2: Регион|Сезон сверху, Ресурс|Поиск снизу.
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: dropdowns[0],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: dropdowns[1],
                      ),
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: dropdowns[2],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _buildSearchRow(context, hasActiveFilters,
                            alignWithDropdown: true),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }
          return Column(
            children: [
              dropdowns[0],
              dropdowns[1],
              dropdowns[2],
              const SizedBox(height: 8),
              _buildSearchRow(context, hasActiveFilters),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchRow(BuildContext context, bool hasActiveFilters,
      {bool alignWithDropdown = false}) {
    final scheme = Theme.of(context).colorScheme;
    final field = Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: TextField(
              controller: searchController,
              textCapitalization: TextCapitalization.sentences,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(color: scheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Поиск вида (заяц, кабан…)',
                hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                filled: true,
                // Один-в-один как поиск в Дневнике — адаптивный, виден в обеих темах.
                fillColor: scheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: onSearchChanged,
            ),
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
    );
    // В ряду с дропдаунами у тех сверху метка (~24px), поэтому поиск
    // опускаем на ту же высоту — его поле встаёт на уровень их полей.
    if (alignWithDropdown) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: field,
      );
    }
    return field;
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
      child: Material(
        color: Colors.transparent,
        // Вся строка (значок + текст) кликабельна — открывает страницу с примечанием.
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const _DisclaimerScreen(),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.info_outline, size: 16, color: kRestrictions),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Информация справочная. Сверяйтесь с официальными приказами.',
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

/// Адаптивная сетка записей: одна колонка на телефоне, несколько на планшете.
class _RecordsGrid extends StatelessWidget {
  final List<HuntingRecord> records;
  const _RecordsGrid({required this.records});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const SliverToBoxAdapter(child: _EmptyResult());
    }
    // SliverLayoutBuilder адаптирует число колонок к доступной ширине.
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        // Ширина ячейки ~ 360; на широких экранах поместится несколько.
        final extent = constraints.crossAxisExtent;
        if (extent < 720) {
          // Одна колонка — плавный авто-список (карточки разной высоты).
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _RecordTile(record: records[i], detailExpanded: false),
              childCount: records.length,
            ),
          );
        }
        // Несколько колонок — ровно 2: длинные названия не режутся до «…»,
        // карточки прямоугольные (mainAxisExtent < ширины ряда).
        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 205,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _RecordTile(
              record: records[i],
              detailExpanded: true,
            ),
            childCount: records.length,
          ),
        );
      },
    );
  }
}

/// Карточка записи срока (выразительная).
class _RecordTile extends StatelessWidget {
  final HuntingRecord record;
  final bool detailExpanded;
  const _RecordTile({
    required this.record,
    this.detailExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final seasonColor = _seasonColor(scheme, record.season);
    final hasNewInfo = _hasNewInfo(record);

    final detailsBtn = _DetailButton(
      hasNewInfo: hasNewInfo,
      onPressed:       hasNewInfo
          ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _DetailScreen(record: record),
                ),
              )
          : null,
    );

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
                  child: SizedBox(
                    // Фикс-высота на 2 строки: у длинных и коротких названий
                    // последующие строки (дата/ресурс/кнопка) выравниваются.
                    height: 41,
                    child: Text(
                      record.species,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16, height: 1.2),
                    ),
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
            // Ресурс — фикс-высота на 2 строки, чтобы кнопка была на одном уровне
            // с кнопкой соседней карточки (симметрия в ряду).
            if (record.resource.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: Text(
                  record.resource,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: scheme.onSurfaceVariant, height: 1.3),
                ),
              ),
            ],
            // Компактный отступ до кнопки (не растягиваем карточку по высоте).
            const SizedBox(height: 6),
            // Кнопка «Подробности»: при широкой карточке (планшет/сетка) —
            // слева растянутая, при узкой (телефон, 1 колонка) — справа.
            if (detailExpanded)
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: double.infinity,
                  child: detailsBtn,
                ),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: detailsBtn,
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
          ? FilledButton.tonal(
              onPressed: onPressed,
              child: const Text('Подробности'),
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
        tint: kRestrictionsBg,
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