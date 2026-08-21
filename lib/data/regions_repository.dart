import '../models/region.dart';

/// Встроенные данные о сроках охоты по регионам.
/// Регионы добавляются в обновлениях приложения.
class RegionsRepository {
  static const List<Region> _regions = [
    Region(
      id: 'krasnodar',
      name: 'Краснодарский край',
      species: [
        SeasonPeriod(name: 'Лось', notes: 'Сроки уточняются'),
        SeasonPeriod(name: 'Кабан', notes: 'Сроки уточняются'),
        SeasonPeriod(name: 'Заяц', notes: 'Сроки уточняются'),
        SeasonPeriod(name: 'Водоплавающая дичь', notes: 'Сроки уточняются'),
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