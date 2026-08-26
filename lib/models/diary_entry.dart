/// Запись в дневнике наблюдений охотника.
class DiaryEntry {
  final int? id;
  final String? uuid;
  final DateTime date;
  final String? location;
  final String? weather;
  final String species;
  final double? latitude;
  final double? longitude;
  final String? photoPath;
  final String? notes;
  final String result; // 'добыто' | 'наблюдение' | ''
  final double? weight; // вес (кг) — для добычи
  final int? count; // количество
  final String? method; // способ охоты

  DiaryEntry({
    this.id,
    this.uuid,
    required this.date,
    this.location,
    this.weather,
    this.species = '',
    this.latitude,
    this.longitude,
    this.photoPath,
    this.notes,
    this.result = '',
    this.weight,
    this.count,
    this.method,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'date': date.toIso8601String(),
      'location': location,
      'weather': weather,
      'species': species,
      'latitude': latitude,
      'longitude': longitude,
      'photo_path': photoPath,
      'notes': notes,
      'result': result,
      'weight': weight,
      'count': count,
      'method': method,
    };
  }

  factory DiaryEntry.fromMap(Map<String, dynamic> map) {
    return DiaryEntry(
      id: map['id'] as int?,
      uuid: map['uuid'] as String?,
      date: DateTime.parse(map['date'] as String),
      location: map['location'] as String?,
      weather: map['weather'] as String?,
      species: map['species'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      photoPath: map['photo_path'] as String?,
      notes: map['notes'] as String?,
      result: map['result'] as String? ?? '',
      weight: (map['weight'] as num?)?.toDouble(),
      count: (map['count'] as num?)?.toInt(),
      method: map['method'] as String?,
    );
  }
}