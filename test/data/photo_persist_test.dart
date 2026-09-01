import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pomoshchnik_okhotnika/data/photo_persist.dart';

// ============================================================
// ТЕСТЫ БАГ #6: файл фото из image_picker копируется в надёжное
// хранилище (не остаётся во временном кэше приложения)
// ============================================================

void main() {
  test('БАГ #6: persistPickedPhoto копирует файл в targetDir и возвращает путь',
      () async {
    final tmp = Directory.systemTemp.createTempSync('photo_persist_');
    final srcDir = Directory('${tmp.path}/src')..createSync();
    final targetDir = Directory('${tmp.path}/diary_photos');

    // Исходный «временный» файл, как из image_picker cache.
    final src = File('${srcDir.path}/image_picker_abc.jpg')
      ..writeAsBytesSync([1, 2, 3]);

    final dest = await persistPickedPhoto(src.path, targetDir: targetDir);

    // Копия создана в целевом каталоге.
    final destFile = File(dest);
    expect(destFile.existsSync(), isTrue);
    expect(destFile.readAsBytesSync(), [1, 2, 3]);
    // Возвращённый путь лежит внутри diary_photos и отличается от исходного.
    expect(dest, startsWith(targetDir.path));
    expect(dest, isNot(src.path));
    // Расширение сохранено.
    expect(dest, endsWith('.jpg'));

    tmp.deleteSync(recursive: true);
  });

  test('БАГ #6: расширение .png из исходного пути сохраняется', () async {
    final tmp = Directory.systemTemp.createTempSync('photo_persist_png_');
    final srcDir = Directory('${tmp.path}/src')..createSync();
    final targetDir = Directory('${tmp.path}/diary_photos');

    final src = File('${srcDir.path}/image_picker_xyz.png')
      ..writeAsBytesSync([9, 8, 7]);

    final dest = await persistPickedPhoto(src.path, targetDir: targetDir);

    expect(dest, endsWith('.png'));
    expect(File(dest).existsSync(), isTrue);

    tmp.deleteSync(recursive: true);
  });
}
