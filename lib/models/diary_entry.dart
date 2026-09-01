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
  /// Статус загрузки фото (-жа upload). null/отсутствие = успех (тихо),
  /// 'uploading' = в процессе, 'failed' = авто-ретрай исчерпан и фото не уехало.
  final String? photoUploadState;
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
    this.photoUploadState,
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
      'photo_upload_state': photoUploadState,
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
      photoUploadState: map['photo_upload_state'] as String?,
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
    Object? photoPath = _unset,
    Object? photoUrl = _unset,
    Object? photoUploadState = _unset,
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
      photoPath: photoPath == _unset ? this.photoPath : photoPath as String?,
      photoUrl: photoUrl == _unset ? this.photoUrl : photoUrl as String?,
      photoUploadState:
          photoUploadState == _unset ? this.photoUploadState : photoUploadState as String?,
      notes: notes ?? this.notes,
      result: result ?? this.result,
      weight: weight ?? this.weight,
      count: count ?? this.count,
      method: method ?? this.method,
    );
  }
}

/// Сентинел для `copyWith`: отличает «не передано» от «явно null» в
/// [DiaryEntry.copyWith.photoUploadState] (чтобы можно было сбросить статус).
const Object _unset = Object();