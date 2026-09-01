import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// БАГ #6: `image_picker` кладёт выбранный файл во временный кэш приложения,
/// который Android может почистить в любой момент. После чистки запись
/// остаётся без фото (`File(photoPath).existsSync() == false`), пока не
/// придёт синхронизация.
///
/// Копирует исходный файл в надёжное хранилище `documents/diary_photos` и
/// возвращает новый стабильный путь. Параметр [targetDir] позволяет
/// подставить каталог в тестах (иначе используется documents-каталог).
Future<String> persistPickedPhoto(String srcPath, {Directory? targetDir}) async {
  final dir =
      targetDir ??
      Directory('${(await getApplicationDocumentsDirectory()).path}/diary_photos');
  await dir.create(recursive: true);
  final ext = srcPath.split('.').lastOrNull?.toLowerCase() ?? 'jpg';
  final destName = 'picked_${DateTime.now().millisecondsSinceEpoch}.$ext';
  final dest = '${dir.path}/$destName';
  await File(srcPath).copy(dest);
  return dest;
}
