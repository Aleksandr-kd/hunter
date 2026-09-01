import 'package:flutter_test/flutter_test.dart';

import 'package:pomoshchnik_okhotnika/models/diary_entry.dart';
import 'package:pomoshchnik_okhotnika/screens/diary_screen.dart';

// ============================================================
// ТЕСТЫ БАГ #7: ключ кэша изображения зависит от пути файла, который
// несёт версию содержимого (мс от updated_at). URL фото ФИКСИРОВАН и не
// меняется при перезаписи, поэтому по нему нельзя обнаружить смену фото.
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
      'БАГ #7: смена версии фото на том же фиксированном URL меняет путь и '
      'ключ кэша (Image.file пересоздаётся)', () {
    final fixedUrl = 'user/uuid.jpg';

    // Старая версия файла (uuid.<oldMs>.jpg) и новая (uuid.<newMs>.jpg).
    final oldPhoto = rec(
      photoPath: '/app/diary_photos/uuid.1699990000000.jpg',
      photoUrl: fixedUrl,
    );
    final newPhoto = rec(
      photoPath: '/app/diary_photos/uuid.1699999000000.jpg',
      photoUrl: fixedUrl,
    );

    final oldKey = photoCacheKey(oldPhoto);
    final newKey = photoCacheKey(newPhoto);

    // Один и тот же URL, но разные файлы (версии) -> разные ключи.
    expect(oldKey, isNot(newKey),
        reason: 'БАГ #7: при смене фото URL не меняется, но путь с версией '
            'отличается — ключ кэша обязан измениться');
    // Ключ опирается на путь (с версией), а не на фиксированный URL.
    expect(newKey, contains('/app/diary_photos/uuid.1699999000000.jpg'));
  });

  test(
      'БАГ #7: для одного и того же файла (версии) ключ стабилен и не пуст — '
      'лишних пересозданий Image нет', () {
    final a = rec(
      photoPath: '/app/diary_photos/uuid.1699999000000.jpg',
      photoUrl: 'user/uuid.jpg',
    );
    final b = rec(
      photoPath: '/app/diary_photos/uuid.1699999000000.jpg',
      photoUrl: 'user/uuid.jpg',
    );

    // Одинаковый файл -> одинаковые ключи, чтобы Flutter не перерисовывал.
    expect(photoCacheKey(a), photoCacheKey(b));
    expect(photoCacheKey(a), isNotEmpty);
  });

  test('БАГ #7: fallback на photoUrl, когда photoPath ещё не скачан (null)', () {
    final a = rec(photoPath: null, photoUrl: 'user/uuid.jpg');
    final b = rec(photoPath: null, photoUrl: 'user/uuid.jpg');

    expect(photoCacheKey(a), photoCacheKey(b));
    expect(photoCacheKey(a), contains('user/uuid.jpg'));
  });
}
