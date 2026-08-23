/// Одна строка срока охоты на вид дичи в конкретном регионе, ресурсе и сезоне.
///
/// Один вид может иметь несколько записей [HuntingRecord] (например, вальдшнеп:
/// 15.08-16.01 только с собаками и 15.08-31.12 без). Все строки показываются
/// пользователю вместе — каждая со своими сроками и ограничениями.
class HuntingRecord {
  final String regionId;
  final String regionName;
  final String resource; // «Пернатая дичь», «Копытные животные» и т.д.
  final String season; // Весна / Лето / Осень / Зима
  final String species; // «вальдшнеп», «Кабан: все половозрастные группы» и т.д.
  final String? openDate; // "15.08" или null/пусто
  final String? closeDate; // "16.01" или null/пусто
  final String? restrictions; // ограничения / примечания
  final String? zone; // зона охоты ("Все" и т.п.)

  const HuntingRecord({
    required this.regionId,
    required this.regionName,
    required this.resource,
    required this.season,
    required this.species,
    this.openDate,
    this.closeDate,
    this.restrictions,
    this.zone,
  });

  /// Полная строка «сроки» (например "15.08-16.01").
  String get datesLabel {
    if (openDate == null || openDate!.isEmpty) return '—';
    if (closeDate == null || closeDate!.isEmpty) return openDate!;
    return '$openDate-$closeDate';
  }

  /// Отображаемое название при поиске — единый ключ.
  String get searchKey => species.toLowerCase();

  Map<String, dynamic> toJson() => {
        'region_id': regionId,
        'region_name': regionName,
        'resource': resource,
        'season': season,
        'species': species,
        'open_date': openDate,
        'close_date': closeDate,
        'restrictions': restrictions,
        'zone': zone,
      };

  factory HuntingRecord.fromJson(Map<String, dynamic> json) {
    return HuntingRecord(
      regionId: json['region_id'] as String? ?? '',
      regionName: json['region_name'] as String? ?? '',
      resource: json['resource'] as String? ?? '',
      season: json['season'] as String? ?? '',
      species: json['species'] as String? ?? '',
      openDate: json['open_date'] as String?,
      closeDate: json['close_date'] as String?,
      restrictions: json['restrictions'] as String?,
      zone: json['zone'] as String?,
    );
  }
}