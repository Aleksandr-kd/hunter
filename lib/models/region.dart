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