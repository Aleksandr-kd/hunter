import 'package:flutter_test/flutter_test.dart';

import 'package:pomoshchnik_okhotnika/models/diary_entry.dart';
import 'package:pomoshchnik_okhotnika/screens/diary_screen.dart';

// ============================================================
// ТЕСТЫ БАГ #5: ключ кэша изображения зависит от photoUrl
// ============================================================

/// Строит запись дневника с заданными photoPath/photoUrl.
DiaryEntry rec({String? photoPath, String? photoUrl}) {
  return DiaryEntry(
    uuid: 'uuid-photo-cache',
    date: DateTime.utc(2026, 9, 1),
    species: 'Кабан',
    photoPath: photoPath,
    photoUrl: photoUrl,
  );
}

void main() {
  test(
      'БАГ #5: смена photoUrl на том же photoPath меняет ключ кэша '
      '(виджет Image пересоздаётся)', () {
    final samePath = '/app/diary_photos/uuid.jpg';

    final oldPhoto = rec(photoPath: samePath, photoUrl: 'user/old.jpg');
    final newPhoto = rec(photoPath: samePath, photoUrl: 'user/new.jpg');

    final oldKey = photoCacheKey(oldPhoto);
    final newKey = photoCacheKey(newPhoto);

    // Один и тот же файл на диске, разный photoUrl -> разные ключи.
    expect(oldKey, isNot(newKey),
        reason: 'БАГ #5: при смене фото на том же photoPath ключ кэша должен '
            'измениться, иначе Image.file покажет устаревший кадр');
    // Ключи содержат photoUrl (чтобы они были уникальными).
    expect(newKey, contains('user/new.jpg'));
  });

  test(
      'БАГ #5: пока photoUrl неизвестен (null), ключ падает на photoPath — '
      'ключ остаётся стабильным для одного файла', () {
    final a = rec(photoPath: '/app/diary_photos/uuid.jpg', photoUrl: null);
    final b = rec(photoPath: '/app/diary_photos/uuid.jpg', photoUrl: null);

    // До upload (photoUrl=null) и одинаковом пути ключи одинаковы и не пустые.
    expect(photoCacheKey(a), photoCacheKey(b));
    expect(photoCacheKey(a), isNotEmpty);
  });
}
