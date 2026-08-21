/// Вид дичи и период(ы) охоты на него в конкретном регионе.
class SeasonPeriod {
  final String name;
  final DateTime? openDate;
  final DateTime? closeDate;
  final String? notes;

  const SeasonPeriod({
    required this.name,
    this.openDate,
    this.closeDate,
    this.notes,
  });

  /// Статус сезона на указанную дату: открыт / скоро / закрыт.
  SeasonStatus statusAt(DateTime date) {
    final open = openDate;
    final close = closeDate;
    if (open == null && close == null) return SeasonStatus.unknown;
    final d = DateTime(date.year, date.month, date.day);
    if (open != null) {
      final o = DateTime(open.year, open.month, open.day);
      if (d.isBefore(o)) return SeasonStatus.coming;
    }
    if (close != null) {
      final c = DateTime(close.year, close.month, close.day);
      if (d.isAfter(c)) return SeasonStatus.closed;
    }
    return SeasonStatus.open;
  }
}

/// Статус сезона охоты.
enum SeasonStatus {
  /// Открыт в данный момент.
  open,

  /// Сезон ещё не начался (скоро).
  coming,

  /// Уже закончился.
  closed,

  /// Неизвестно (нет дат).
  unknown,
}

/// Регион с данными о сроках охоты по видам.
class Region {
  final String id;
  final String name;
  final List<SeasonPeriod> species;

  const Region({
    required this.id,
    required this.name,
    this.species = const [],
  });

  factory Region.fromJson(Map<String, dynamic> json) {
    return Region(
      id: json['id'] as String,
      name: json['name'] as String,
      species: (json['species'] as List<dynamic>? ?? [])
          .map((e) => SeasonPeriod(
                name: e['name'] as String,
                openDate: _parseDate(e['open']),
                closeDate: _parseDate(e['close']),
                notes: e['notes'] as String?,
              ))
          .toList(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}