/// Запись в дневнике наблюдений охотника.
class DiaryEntry {
  final int? id;
  final DateTime date;
  final String? location;
  final String? weather;
  final String species;
  final double? latitude;
  final double? longitude;
  final String? photoPath;
  final String? notes;

  DiaryEntry({
    this.id,
    required this.date,
    this.location,
    this.weather,
    this.species = '',
    this.latitude,
    this.longitude,
    this.photoPath,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'location': location,
      'weather': weather,
      'species': species,
      'latitude': latitude,
      'longitude': longitude,
      'photo_path': photoPath,
      'notes': notes,
    };
  }

  factory DiaryEntry.fromMap(Map<String, dynamic> map) {
    return DiaryEntry(
      id: map['id'] as int?,
      date: DateTime.parse(map['date'] as String),
      location: map['location'] as String?,
      weather: map['weather'] as String?,
      species: map['species'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      photoPath: map['photo_path'] as String?,
      notes: map['notes'] as String?,
    );
  }
}