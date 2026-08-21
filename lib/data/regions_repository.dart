import '../models/region.dart';

/// Встроенные данные о сроках охоты по регионам.
/// Регионы добавляются в обновлениях приложения.
///
/// ВНИМАНИЕ: даты носят справочный характер и могут меняться
/// ежегодно приказами региональных органов власти.
/// Перед каждой охотой сверяйтесь с официальными источниками.
class RegionsRepository {
  static final List<Region> _regions = [
    Region(
      id: 'krasnodar',
      name: 'Краснодарский край',
      species: [
        SeasonPeriod(
          name: 'Водоплавающая дичь (гусь, утка)',
          openDate: DateTime(DateTime.now().year, 9, 14),
          closeDate: DateTime(DateTime.now().year, 12, 31),
          notes: 'Осенний сезон. Весенний — ~апрель.',
        ),
        SeasonPeriod(
          name: 'Болотно-луговая дичь',
          openDate: DateTime(DateTime.now().year, 9, 7),
          closeDate: DateTime(DateTime.now().year, 12, 31),
          notes: 'Бекас, дупель, коростель и др.',
        ),
        SeasonPeriod(
          name: 'Боровая дичь',
          openDate: DateTime(DateTime.now().year, 10, 1),
          closeDate: DateTime(DateTime.now().year, 12, 31),
          notes: '',
        ),
        SeasonPeriod(
          name: 'Заяц-русак',
          openDate: DateTime(DateTime.now().year, 11, 1),
          closeDate: DateTime(DateTime.now().year + 1, 1, 31),
          notes: 'Охота с собакой с 25 октября.',
        ),
        SeasonPeriod(
          name: 'Лисица, шакал',
          openDate: DateTime(DateTime.now().year, 9, 14),
          closeDate: DateTime(DateTime.now().year + 1, 2, 28),
          notes: '',
        ),
        SeasonPeriod(
          name: 'Кабан',
          openDate: DateTime(DateTime.now().year, 6, 1),
          closeDate: DateTime(DateTime.now().year + 1, 2, 28),
          notes: 'Сроки зависят от охотхозяйства и способа охоты.',
        ),
        SeasonPeriod(
          name: 'Олень благородный',
          openDate: DateTime(DateTime.now().year, 6, 1),
          closeDate: DateTime(DateTime.now().year + 1, 1, 15),
          notes: 'Сроки зависят от пола и способа охоты.',
        ),
        SeasonPeriod(
          name: 'Косуля европейская',
          openDate: DateTime(DateTime.now().year, 6, 1),
          closeDate: DateTime(DateTime.now().year, 10, 15),
          notes: 'Сроки зависят от пола и способа охоты.',
        ),
      ],
    ),
  ];

  List<Region> getRegions() => _regions;

  Region? getRegion(String id) {
    for (final r in _regions) {
      if (r.id == id) return r;
    }
    return null;
  }
}