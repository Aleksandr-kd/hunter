import '../models/region.dart';

/// Встроенные данные о сроках охоты по регионам.
/// Регионы добавляются в обновлениях приложения.
///
/// ВНИМАНИЕ: даты носят справочный характер и могут меняться
/// ежегодно приказами региональных органов власти.
/// Перед каждой охотой сверяйтесь с официальными источниками.
class RegionsRepository {
  /// Внутреннее хранилище: month/day пары. Год вычисляется динамически
  /// при каждом вызове getRegions() — это критично, т.к. сроки охоты
  /// меняются ежегодно. Хардкод DateTime в static final приводит к тому,
  /// что даты «замораживаются» на год компиляции приложения.
  static final List<_RawRegion> _rawRegions = [
    _RawRegion(
      id: 'krasnodar',
      name: 'Краснодарский край',
      species: [
        _RawSeasonPeriod(
          name: 'Водоплавающая дичь (гусь, утка)',
          openMonth: 9, openDay: 14,
          closeMonth: 12, closeDay: 31,
          notes: 'Осенний сезон. Весенний — ~апрель.',
        ),
        _RawSeasonPeriod(
          name: 'Болотно-луговая дичь',
          openMonth: 9, openDay: 7,
          closeMonth: 12, closeDay: 31,
          notes: 'Бекас, дупель, коростель и др.',
        ),
        _RawSeasonPeriod(
          name: 'Боровая дичь',
          openMonth: 10, openDay: 1,
          closeMonth: 12, closeDay: 31,
          notes: '',
        ),
        _RawSeasonPeriod(
          name: 'Заяц-русак',
          openMonth: 11, openDay: 1,
          closeMonth: 1, closeDay: 31, closeNextYear: true,
          notes: 'Охота с собакой с 25 октября.',
        ),
        _RawSeasonPeriod(
          name: 'Лисица, шакал',
          openMonth: 9, openDay: 14,
          closeMonth: 2, closeDay: 28, closeNextYear: true,
          notes: '',
        ),
        _RawSeasonPeriod(
          name: 'Кабан',
          openMonth: 6, openDay: 1,
          closeMonth: 2, closeDay: 28, closeNextYear: true,
          notes: 'Сроки зависят от охотхозяйства и способа охоты.',
        ),
        _RawSeasonPeriod(
          name: 'Олень благородный',
          openMonth: 6, openDay: 1,
          closeMonth: 1, closeDay: 15, closeNextYear: true,
          notes: 'Сроки зависят от пола и способа охоты.',
        ),
        _RawSeasonPeriod(
          name: 'Косуля европейская',
          openMonth: 6, openDay: 1,
          closeMonth: 10, closeDay: 15,
          notes: 'Сроки зависят от пола и способа охоты.',
        ),
      ],
    ),
  ];

  /// Возвращает регионы с датами, вычисленными для текущего года.
  List<Region> getRegions() {
    final now = DateTime.now();
    final year = now.year;
    return _rawRegions.map((raw) {
      final species = raw.species.map((s) {
        final openDate = DateTime(year, s.openMonth, s.openDay);
        final closeDate = s.closeNextYear
            ? DateTime(year + 1, s.closeMonth, s.closeDay)
            : DateTime(year, s.closeMonth, s.closeDay);
        return SeasonPeriod(
          name: s.name,
          openDate: openDate,
          closeDate: closeDate,
          notes: s.notes,
        );
      }).toList();
      return Region(
        id: raw.id,
        name: raw.name,
        species: species,
      );
    }).toList();
  }

  Region? getRegion(String id) {
    for (final r in _rawRegions) {
      if (r.id == id) {
        // Возвращаем с динамическими датами
        return getRegions().firstWhere((region) => region.id == id, orElse: () => Region(id: id, name: r.name));
      }
    }
    return null;
  }
}

/// Внутренний класс для хранения month/day без года.
class _RawRegion {
  final String id;
  final String name;
  final List<_RawSeasonPeriod> species;
  const _RawRegion({required this.id, required this.name, required this.species});
}

class _RawSeasonPeriod {
  final String name;
  final int openMonth, openDay;
  final int closeMonth, closeDay;
  final bool closeNextYear;
  final String? notes;
  const _RawSeasonPeriod({
    required this.name,
    required this.openMonth, required this.openDay,
    required this.closeMonth, required this.closeDay,
    this.closeNextYear = false,
    this.notes,
  });
}
