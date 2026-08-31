/// Запись в дневнике наблюдений охотника.
class DiaryEntry {
  final int? id;
  final String? uuid;
  final DateTime? updatedAt;
  final DateTime date;
  final String? location;
  final String? weather;
  final String species;
  final double? latitude;
  final double? longitude;
  final String? photoPath;
  final String? photoUrl; // путь фото на сервере (для синхронизации/статуса)
  final String? notes;
  final String result; // 'добыто' | 'наблюдение' | ''
  final double? weight; // вес (кг) — для добычи
  final int? count; // количество
  final String? method; // способ охоты

  DiaryEntry({
    this.id,
    this.uuid,
    this.updatedAt,
    required this.date,
    this.location,
    this.weather,
    this.species = '',
    this.latitude,
    this.longitude,
    this.photoPath,
    this.photoUrl,
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
      'updated_at': updatedAt?.toIso8601String(),
      'date': date.toIso8601String(),
      'location': location,
      'weather': weather,
      'species': species,
      'latitude': latitude,
      'longitude': longitude,
      'photo_path': photoPath,
      'photo_url': photoUrl,
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
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) : null,
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      location: map['location'] as String?,
      weather: map['weather'] as String?,
      species: map['species'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      photoPath: map['photo_path'] as String?,
      photoUrl: map['photo_url'] as String?,
      notes: map['notes'] as String?,
      result: map['result'] as String? ?? '',
      weight: (map['weight'] as num?)?.toDouble(),
      count: (map['count'] as num?)?.toInt(),
      method: map['method'] as String?,
    );
  }

  /// Копия с возможностью замены отдельных полей.
  DiaryEntry copyWith({
    int? id,
    String? uuid,
    DateTime? updatedAt,
    DateTime? date,
    String? location,
    String? weather,
    String? species,
    double? latitude,
    double? longitude,
    String? photoPath,
    String? photoUrl,
    String? notes,
    String? result,
    double? weight,
    int? count,
    String? method,
  }) {
    return DiaryEntry(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      updatedAt: updatedAt ?? this.updatedAt,
      date: date ?? this.date,
      location: location ?? this.location,
      weather: weather ?? this.weather,
      species: species ?? this.species,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      photoPath: photoPath ?? this.photoPath,
      photoUrl: photoUrl ?? this.photoUrl,
      notes: notes ?? this.notes,
      result: result ?? this.result,
      weight: weight ?? this.weight,
      count: count ?? this.count,
      method: method ?? this.method,
    );
  }
}