import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pomoshchnik_okhotnika/db/app_database.dart';
import 'package:pomoshchnik_okhotnika/models/diary_entry.dart';
import 'package:pomoshchnik_okhotnika/providers/diary_provider.dart';
import 'package:pomoshchnik_okhotnika/providers/diary_sync_engine.dart';

// ============================================================
// Тестовая БД (изолированная, не singleton AppDatabase)
// ============================================================

class TestAppDatabase implements AppDatabase {
  final Database _db;
  TestAppDatabase(this._db);

  @override
  Future<List<DiaryEntry>> getDiaryEntries() async {
    final rows = await _db.query('diary_entries', orderBy: 'date DESC');
    return rows.map(DiaryEntry.fromMap).toList();
  }

  @override
  Future<int> getDiaryCount() async {
    final result = await _db
        .rawQuery('SELECT COUNT(*) FROM diary_entries');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<int> insertDiaryEntry(DiaryEntry entry) async {
    final data = entry.toMap()..remove('id');
    data['updated_at'] =
        entry.updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String();
    return _db.insert('diary_entries', data,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<int> deleteDiaryEntry(int id) async {
    return _db.delete('diary_entries', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteAllDiaryEntries() async {
    await _db.delete('diary_entries');
  }

  @override
  Future<int> updateDiaryEntry(DiaryEntry entry) async {
    final data = entry.toMap()..remove('id');
    data['updated_at'] =
        entry.updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String();
    return _db.update('diary_entries', data,
        where: 'id = ?', whereArgs: [entry.id]);
  }
}

Future<AppDatabase> createIsolatedDb() async {
  final dbFactory = databaseFactoryFfi;
  final dbPath =
      p.join(Directory.systemTemp.createTempSync('diary_test_').path, 'test.db');
  final database = await dbFactory.openDatabase(dbPath,
      options: OpenDatabaseOptions(
          version: 9,
          onCreate: (db, version) async {
            await db.execute('''
          CREATE TABLE diary_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT,
            updated_at TEXT,
            date TEXT NOT NULL,
            location TEXT,
            weather TEXT,
            species TEXT NOT NULL DEFAULT '',
            latitude REAL,
            longitude REAL,
            photo_path TEXT,
            photo_url TEXT,
            photo_upload_state TEXT,
            notes TEXT,
            result TEXT DEFAULT '',
            weight REAL,
            count INTEGER,
            method TEXT
          )
        ''');
            await db.execute(
                'CREATE UNIQUE INDEX IF NOT EXISTS idx_diary_uuid ON diary_entries(uuid) WHERE uuid IS NOT NULL');
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) {
              await db.execute('ALTER TABLE diary_entries ADD COLUMN uuid TEXT');
            }
            if (oldVersion < 3) {
              await db.execute(
                  "ALTER TABLE diary_entries ADD COLUMN result TEXT DEFAULT ''");
            }
            if (oldVersion < 4) {
              await db.execute(
                  'ALTER TABLE diary_entries ADD COLUMN weight REAL');
              await db.execute(
                  'ALTER TABLE diary_entries ADD COLUMN count INTEGER');
              await db.execute(
                  'ALTER TABLE diary_entries ADD COLUMN method TEXT');
            }
            if (oldVersion < 5) {
              await db.execute('''
            DELETE FROM diary_entries
            WHERE id NOT IN (
              SELECT MIN(id) FROM diary_entries
              WHERE uuid IS NOT NULL AND uuid <> '' GROUP BY uuid
            ) AND uuid IS NOT NULL AND uuid <> ''
          ''');
              await db.execute(
                  'CREATE UNIQUE INDEX IF NOT EXISTS idx_diary_uuid ON diary_entries(uuid) WHERE uuid IS NOT NULL');
            }
            if (oldVersion < 6) {
              await db.execute(
                  'ALTER TABLE diary_entries ADD COLUMN updated_at TEXT');
              await db.execute('''
            UPDATE diary_entries SET updated_at = date WHERE updated_at IS NULL
          ''');
            }
            if (oldVersion < 7) {
              await db.execute(
                  'CREATE INDEX IF NOT EXISTS idx_diary_entries_uuid ON diary_entries(uuid)');
            }
            if (oldVersion < 8) {
              await db.execute(
                  'ALTER TABLE diary_entries ADD COLUMN photo_url TEXT');
            }
            if (oldVersion < 9) {
              await db.execute(
                  'ALTER TABLE diary_entries ADD COLUMN photo_upload_state TEXT');
            }
          }));
  return TestAppDatabase(database);
}

// ============================================================
// Фейковый бэкенд (с возможностью отслеживать upload)
// ============================================================

class TrackingFakeBackend implements DiaryBackend {
  final Map<String, Map<String, dynamic>> server = {};
  final String user;
  bool isReady = true;

  /// Все photoUrl, переданные в pushEntry (заказ upload)
  final List<String?> uploadedPhotoUrls = [];

  /// Все photoUrl, переданные в pushEntry (заказ upload) — после upload фото
  final List<String?> actualPhotoUrlsOnServer = [];

  TrackingFakeBackend({required this.user});

  @override
  bool get ready => isReady;

  @override
  String? get userId => user;

  @override
  Future<List<Map<String, dynamic>>> pull() async {
    final rows = server.values.toList()
      ..sort((a, b) =>
          (a['entry_date'] as String).compareTo(b['entry_date'] as String));
    return rows;
  }

  @override
  Future<bool> deleteEntry(String uuid) async {
    server.remove(uuid);
    return true;
  }

  @override
  Future<void> bulkUpsert(List<Map<String, dynamic>> payload) async {
    for (final row in payload) {
      final uuid = row['uuid'] as String;
      final existing = server[uuid] ?? <String, dynamic>{};
      final merged = Map<String, dynamic>.from(existing)..addAll(row);
      server[uuid] = merged;
    }
  }

  @override
  Future<void> pushEntry(DiaryEntry entry, String? photoUrl) async {
    uploadedPhotoUrls.add(entry.photoUrl);
    final updatedAt =
        (entry.updatedAt ?? DateTime.now()).toIso8601String();
    server[entry.uuid!] = {
      'uuid': entry.uuid,
      'user_id': user,
      'species': entry.species,
      'location': entry.location,
      'weather': entry.weather,
      'notes': entry.notes,
      'entry_date': entry.date.toIso8601String(),
      'latitude': entry.latitude,
      'longitude': entry.longitude,
      'photo_url': photoUrl,
      'result': entry.result,
      'weight': entry.weight,
      'count': entry.count,
      'method': entry.method,
      'updated_at': updatedAt,
    };
    actualPhotoUrlsOnServer.add(photoUrl);
  }

  @override
  Future<String> uploadPhoto(String objName, File file) async => objName;

  @override
  Future<Uint8List> downloadPhoto(String objName) async =>
      Uint8List.fromList([1, 2, 3]);

  @override
  Future<void> deletePhoto(String objName) async {}
}

// ============================================================
// MemoryKnownStore
// ============================================================

class MemoryKnownStore implements KnownStore {
  Set<String> data = {};
  @override
  String get name => 'test_known';

  @override
  Future<Set<String>> load() async => Set<String>.from(data);

  @override
  Future<void> save(Set<String> uuids) async => data = Set<String>.from(uuids);
}

// ============================================================
// Утилиты
// ============================================================

/// Spy-движок: считает вызовы sync() без реальной синхронизации.
/// Используется для проверки ДЕБАУНСА post-upload sync (лавины полных
/// синков при пакетной загрузке записей с фото).
class SpySyncEngine extends DiarySyncEngine {
  SpySyncEngine({required super.db, required super.backend})
      : super(knownStore: MemoryKnownStore());

  int syncCalls = 0;

  @override
  Future<DiarySyncOutcome> sync() async {
    syncCalls++;
    return const DiarySyncOutcome(changed: false);
  }
}

DiaryEntry entry({
  int? id,
  String? uuid,
  DateTime? updatedAt,
  required DateTime date,
  String species = 'Кабан',
  String? photoPath,
  String? photoUrl,
  String? notes,
}) {
  return DiaryEntry(
    id: id,
    uuid: uuid,
    updatedAt: updatedAt,
    date: date,
    species: species,
    photoPath: photoPath,
    photoUrl: photoUrl,
    notes: notes,
  );
}

Future<File> createTempFileForTest(String name) async {
  final dir = Directory.systemTemp.createTempSync('diary_test_');
  return File('${dir.path}/$name');
}

// ============================================================
// ТЕСТЫ БАГ #2: updateEntry перечитывает данные из БД перед upload
// ============================================================

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('БАГ #2: updateEntry использует свежие данные из БД', () {
    late AppDatabase db;
    late TrackingFakeBackend backend;
    late DiaryProvider provider;

    setUp(() async {
      db = await createIsolatedDb();
      backend = TrackingFakeBackend(user: 'user-bug2');
      final engine = DiarySyncEngine(
          db: db,
          backend: backend,
          knownStore: MemoryKnownStore());
      await engine.loadKnown();
      provider = DiaryProvider(db: db, engine: engine);
      await provider.load();
      backend.isReady = true;
    });

    tearDown(() async {
      await db.deleteAllDiaryEntries();
    });

    test(
        'updateEntry: upload получает актуальный photoUrl из БД, а не из переданного entry',
        () async {
      // 1. Создаём запись с photoUrl
      final tempFile =
          await createTempFileForTest('bug2_test.jpg');
      final originalEntry = entry(
        uuid: 'uuid-bug2-test',
        date: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1, 10),
        species: 'Кабан',
        photoPath: tempFile.path,
        photoUrl: 'user-bug2/old-photo.jpg',
      );
      final id = await db.insertDiaryEntry(originalEntry);

      // 2. Обновляем запись — меняем species, но photoUrl остаётся тот же
      final updatedEntry = entry(
        id: id,
        uuid: 'uuid-bug2-test',
        date: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1, 12),
        species: 'Олень',
        photoPath: tempFile.path,
        photoUrl: 'user-bug2/old-photo.jpg',
      );
      await provider.updateEntry(updatedEntry);

      // Ждём завершения upload очереди
      await provider.uploadQueue;
      await Future.delayed(const Duration(milliseconds: 100));

      // 3. Проверяем: upload получил photoUrl из БД (который совпадает с переданным)
      // Ключевой момент: entry.photoUrl в upload должен быть 'user-bug2/old-photo.jpg'
      expect(backend.uploadedPhotoUrls, isNotEmpty);
      expect(backend.uploadedPhotoUrls.last, 'user-bug2/old-photo.jpg');
    });

    test(
        'updateEntry: после updateDiaryEntry в БД записываются корректные данные',
        () async {
      // 1. Создаём запись
      final tempFile =
          await createTempFileForTest('bug2_test2.jpg');
      final originalEntry = entry(
        uuid: 'uuid-bug2-test2',
        date: DateTime.utc(2026, 9, 2),
        updatedAt: DateTime.utc(2026, 9, 2, 10),
        species: 'Лось',
        photoPath: tempFile.path,
        photoUrl: 'user-bug2/initial.jpg',
      );
      final id = await db.insertDiaryEntry(originalEntry);

      // 2. Обновляем запись
      final updatedEntry = entry(
        id: id,
        uuid: 'uuid-bug2-test2',
        date: DateTime.utc(2026, 9, 2),
        updatedAt: DateTime.utc(2026, 9, 2, 12),
        species: 'Заяц',
        photoPath: tempFile.path,
        photoUrl: 'user-bug2/initial.jpg',
      );
      await provider.updateEntry(updatedEntry);

      // 3. Проверяем БД
      final local = await db.getDiaryEntries();
      final updated = local.firstWhere((e) => e.id == id);
      expect(updated.species, 'Заяц');
      expect(updated.photoUrl, 'user-bug2/initial.jpg');
    });
  });

  // ============================================================
  // ТЕСТЫ БАГ #1: смена фото при редактировании не затирает photoUrl
  // ============================================================

  group('БАГ #1: смена фото при редактировании', () {
    late AppDatabase db;
    late TrackingFakeBackend backend;
    late DiaryProvider provider;

    setUp(() async {
      db = await createIsolatedDb();
      backend = TrackingFakeBackend(user: 'user-bug1');
      final engine = DiarySyncEngine(
          db: db,
          backend: backend,
          knownStore: MemoryKnownStore());
      await engine.loadKnown();
      provider = DiaryProvider(db: db, engine: engine);
      await provider.load();
      backend.isReady = true;
    });

    tearDown(() async {
      await db.deleteAllDiaryEntries();
    });

    test(
        'updateEntry: смена photoPath не передаёт старый photoUrl в БД',
        () async {
      // 1. Создаём запись с photoUrl
      final tempFileOld =
          await createTempFileForTest('bug1_old.jpg');
      final tempFileNew =
          await createTempFileForTest('bug1_new.jpg');
      final originalEntry = entry(
        uuid: 'uuid-bug1-test',
        date: DateTime.utc(2026, 9, 5),
        updatedAt: DateTime.utc(2026, 9, 5, 10),
        species: 'Кабан',
        photoPath: tempFileOld.path,
        photoUrl: 'user-bug1/old-photo.jpg',
      );
      final id = await db.insertDiaryEntry(originalEntry);

      // 2. Симулируем _save() из diary_screen.dart при смене фото:
      //    photoUrl = null (фото изменено)
      final updatedEntry = entry(
        id: id,
        uuid: 'uuid-bug1-test',
        date: DateTime.utc(2026, 9, 5),
        updatedAt: DateTime.utc(2026, 9, 5, 12),
        species: 'Кабан',
        photoPath: tempFileNew.path, // НОВЫЙ файл!
        photoUrl: null, // ВАЖНО: photoUrl = null при смене фото
      );
      await provider.updateEntry(updatedEntry);

      // 3. Проверяем: в БД photoUrl = null (не старый URL!)
      final local = await db.getDiaryEntries();
      final updated = local.firstWhere((e) => e.id == id);
      expect(updated.photoUrl, isNull);
      // photoPath обновлён на новый
      expect(updated.photoPath, tempFileNew.path);
    });

    test(
        'updateEntry: без смены photoPath photoUrl сохраняется',
        () async {
      // 1. Создаём запись с photoUrl
      final tempFile =
          await createTempFileForTest('bug1_nochange.jpg');
      final originalEntry = entry(
        uuid: 'uuid-bug1-nochange',
        date: DateTime.utc(2026, 9, 6),
        updatedAt: DateTime.utc(2026, 9, 6, 10),
        species: 'Лось',
        photoPath: tempFile.path,
        photoUrl: 'user-bug1/existing-photo.jpg',
      );
      final id = await db.insertDiaryEntry(originalEntry);

      // 2. Обновляем запись БЕЗ смены фото:
      //    photoUrl = widget.initial?.photoUrl (старый URL)
      final updatedEntry = entry(
        id: id,
        uuid: 'uuid-bug1-nochange',
        date: DateTime.utc(2026, 9, 6),
        updatedAt: DateTime.utc(2026, 9, 6, 12),
        species: 'Лось',
        photoPath: tempFile.path, // тот же файл
        photoUrl: 'user-bug1/existing-photo.jpg', // тот же URL
      );
      await provider.updateEntry(updatedEntry);

      // 3. Проверяем: в БД photoUrl сохранён
      final local = await db.getDiaryEntries();
      final updated = local.firstWhere((e) => e.id == id);
      expect(updated.photoUrl, 'user-bug1/existing-photo.jpg');
    });

    test(
        'pushEntry: при photoPath=null photoUrl не затирается на сервере',
        () async {
      // 1. Создаём запись и пушим на сервер
      final originalEntry = entry(
        uuid: 'uuid-bug1-push',
        date: DateTime.utc(2026, 9, 7),
        updatedAt: DateTime.utc(2026, 9, 7, 10),
        species: 'Олень',
        photoUrl: 'user-bug1/push-test.jpg',
      );
      await db.insertDiaryEntry(originalEntry);

      final engine = provider.engine;
      final ok = await engine.pushEntry(originalEntry);
      expect(ok, isTrue);

      // 2. Проверяем: на сервере photoUrl установлен
      expect(backend.server['uuid-bug1-push']!['photo_url'],
          'user-bug1/push-test.jpg');

      // 3. Редактируем без фото (photoPath=null) — photoUrl не должен затереться
      final editNoPhoto = entry(
        uuid: 'uuid-bug1-push',
        date: DateTime.utc(2026, 9, 7),
        updatedAt: DateTime.utc(2026, 9, 7, 12),
        species: 'Олень',
        photoPath: null,
        photoUrl: 'user-bug1/push-test.jpg',
      );
      final ok2 = await engine.pushEntry(editNoPhoto);
      expect(ok2, isTrue);

      // 4. Проверяем: на сервере photoUrl НЕ обнулился
      expect(backend.server['uuid-bug1-push']!['photo_url'],
          'user-bug1/push-test.jpg');
    });

    test(
        'pushEntry: при наличии photoPath photoUrl обновляется на новый',
        () async {
      // 1. Создаём запись с новым фото — сохраняем ссылку на файл
      //    чтобы GC не удалил temp-директорию до окончания теста
      final tempDir = Directory.systemTemp.createTempSync('diary_bug1_');
      final tempFile = File('${tempDir.path}/bug1_upload.jpg')
        ..createSync();
      final originalEntry = entry(
        uuid: 'uuid-bug1-upload',
        date: DateTime.utc(2026, 9, 8),
        updatedAt: DateTime.utc(2026, 9, 8, 10),
        species: 'Утка',
        photoPath: tempFile.path,
        photoUrl: null,
      );
      await db.insertDiaryEntry(originalEntry);

      final engine = provider.engine;
      final ok = await engine.pushEntry(originalEntry);
      expect(ok, isTrue);

      // 2. Проверяем: на сервере photo_url = objName (новый URL)
      final serverPhotoUrl =
          backend.server['uuid-bug1-upload']!['photo_url'];
      expect(serverPhotoUrl, isNotNull);
      expect(serverPhotoUrl, isNotEmpty);
    });
  });

  // ============================================================
  // ТЕСТЫ БАГ #3: после смены фото локальный photoUrl обновляется
  // на НОВЫЙ URL после upload (а не остаётся null/старый)
  // ============================================================

  group('БАГ #3: локальный photoUrl обновляется после смены фото', () {
    late AppDatabase db;
    late TrackingFakeBackend backend;
    late DiaryProvider provider;

    setUp(() async {
      db = await createIsolatedDb();
      backend = TrackingFakeBackend(user: 'user-bug3');
      final engine = DiarySyncEngine(
          db: db,
          backend: backend,
          knownStore: MemoryKnownStore());
      await engine.loadKnown();
      provider = DiaryProvider(db: db, engine: engine);
      await provider.load();
      backend.isReady = true;
    });

    tearDown(() async {
      await db.deleteAllDiaryEntries();
    });

    test(
        'updateEntry со сменой фото: после upload в локальной БД photoUrl = НОВЫЙ URL, '
        'а не null/старый', () async {
      final tempDir = Directory.systemTemp.createTempSync('diary_bug3_');
      final tempFileOld =
          File('${tempDir.path}/old.jpg')..createSync();
      final tempFileNew =
          File('${tempDir.path}/new.jpg')..createSync();

      // 1. Существующая запись со старым фото на сервере.
      final originalEntry = entry(
        uuid: 'uuid-bug3-test',
        date: DateTime.utc(2026, 9, 10),
        updatedAt: DateTime.utc(2026, 9, 10, 10),
        species: 'Лиса',
        photoPath: tempFileOld.path,
        photoUrl: 'user-bug3/old-photo.jpg',
      );
      final id = await db.insertDiaryEntry(originalEntry);

      // 2. Редактируем: меняем фото — _save() передаёт photoUrl = null.
      final updatedEntry = entry(
        id: id,
        uuid: 'uuid-bug3-test',
        date: DateTime.utc(2026, 9, 10),
        updatedAt: DateTime.utc(2026, 9, 10, 12),
        species: 'Лиса',
        photoPath: tempFileNew.path,
        photoUrl: null,
      );
      await provider.updateEntry(updatedEntry);

      // 3. Ждём завершения upload-очереди (фоновая загрузка нового фото).
      await provider.uploadQueue;
      await Future.delayed(const Duration(milliseconds: 100));

      // 4. Ключевая проверка БАГ #3: локальный photoUrl стал НОВЫМ URL
      //    (objName), а не остался null. Новый URL = user-bug3/uuid-bug3-test_<ms>.jpg
      //    (FakeBackend.uploadPhoto возвращает objName; версия из updated_at — БАГ #7).
      final local = await db.getDiaryEntries();
      final updated = local.firstWhere((e) => e.id == id);
      expect(updated.photoUrl, isNotNull,
          reason: 'БАГ #3: после смены фото локальный photoUrl должен '
              'обновиться на новый URL после upload');
      expect(updated.photoUrl, 'user-bug3/uuid-bug3-test_1789041600000.jpg');
      // Сервер тоже должен держать новый URL (регресс БАГ #1).
      expect(backend.server['uuid-bug3-test']!['photo_url'],
          'user-bug3/uuid-bug3-test_1789041600000.jpg');

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
        'pushEntryWithPhoto: возвращает запись с НОВЫМ photoUrl (не null)',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('diary_bug3b_');
      final tempFile = File('${tempDir.path}/new.jpg')..createSync();

      final edit = entry(
        uuid: 'uuid-bug3b',
        date: DateTime.utc(2026, 9, 12),
        updatedAt: DateTime.utc(2026, 9, 12, 10),
        species: 'Кабан',
        photoPath: tempFile.path,
        photoUrl: null, // смена фото: старый URL затёрт
      );
      await db.insertDiaryEntry(edit);

      final returned = await provider.engine.pushEntryWithPhoto(edit);

      // Ключевая проверка: возвращённая запись содержит НОВЫЙ photoUrl.
      expect(returned, isNotNull);
      expect(returned!.photoUrl, isNotNull);
      // Версия (мс от updated_at) в objName — БАГ #7.
      expect(returned.photoUrl, 'user-bug3/uuid-bug3b_1789207200000.jpg');

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });
  });

  // ============================================================
  // Дебаунс post-upload sync: лавина полных синков при пакетной загрузке
  // ============================================================

  group('Debounce: post-upload sync не запускается на каждый upload', () {
    late AppDatabase db;
    late TrackingFakeBackend backend;
    late SpySyncEngine engine;
    late DiaryProvider provider;

    setUp(() async {
      db = await createIsolatedDb();
      backend = TrackingFakeBackend(user: 'user-debounce');
      engine = SpySyncEngine(db: db, backend: backend);
      await engine.loadKnown();
      provider = DiaryProvider(db: db, engine: engine);
      await provider.load();
      backend.isReady = true;
    });

    tearDown(() async {
      await db.deleteAllDiaryEntries();
    });

    test(
        'несколько upload-ов подряд запускают ОДИН post-upload sync (а не лавину, равную числу записей)',
        () async {
      // Три записи с фото-файлом: каждая пройдёт через _uploadEntry.
      for (var i = 0; i < 3; i++) {
        final f = await createTempFileForTest('debounce_$i.jpg');
        await db.insertDiaryEntry(entry(
          uuid: 'uuid-debounce-$i',
          date: DateTime.utc(2026, 9, 1 + i),
          updatedAt: DateTime.utc(2026, 9, 1 + i, 10),
          species: 'Кабан',
          photoPath: f.path,
          photoUrl: null,
        ));
      }

      // Три upload-a подряд, все завершаются успешно (нет фото-ошибок,
      // успешный upload -> планируется post-upload sync).
      for (var i = 0; i < 3; i++) {
        await provider.uploadQueue;
        final all = await db.getDiaryEntries();
        final target = all.firstWhere((e) => e.uuid == 'uuid-debounce-$i');
        await provider.updateEntry(target);
      }
      // Дожидаемся, пока асинхронный post-upload sync проиграется.
      await Future<void>.delayed(const Duration(milliseconds: 400));

      // Главная проверка: полных синков меньше, чем записей (3). Если бы
      // пост-аплоад синк запускался на каждую запись — было бы >=3.
      // Дебаунс схлопывает серию в 1-2 полных синка.
      expect(engine.syncCalls, lessThan(3));
    });

    test('записи с паузой > 2с порождают НОВЫЙ отдельный sync', () async {
      final f = await createTempFileForTest('debounce_gap.jpg');
      await db.insertDiaryEntry(entry(
        uuid: 'uuid-debounce-gap',
        date: DateTime.utc(2026, 9, 5),
        updatedAt: DateTime.utc(2026, 9, 5, 10),
        species: 'Кабан',
        photoPath: f.path,
        photoUrl: null,
      ));

      // Первый upload — синк планируется и проигрывается.
      await provider.uploadQueue;
      var all = await db.getDiaryEntries();
      var target = all.firstWhere((x) => x.uuid == 'uuid-debounce-gap');
      await provider.updateEntry(target);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(engine.syncCalls, greaterThan(0));
      final callsAfterFirst = engine.syncCalls;

      // Пауза больше debounce-окна (2 сек) — следующий upload должен
      // снова запустить отдельный sync.
      await Future<void>.delayed(const Duration(milliseconds: 2700));
      engine.syncCalls = 0; // считаем только второй upload

      await provider.uploadQueue;
      all = await db.getDiaryEntries();
      target = all.firstWhere((x) => x.uuid == 'uuid-debounce-gap');
      await provider.updateEntry(target);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // После паузы > debounce-окна новый upload вызывает отдельный sync.
      expect(engine.syncCalls, greaterThan(0));
      // Барьер против «затухания»: до паузы первый sync так же отработал.
      expect(callsAfterFirst, greaterThanOrEqualTo(1));
    });
  });

  // ============================================================
  // Реальный жизненный цикл: удаление на устройстве A синхронизируется на B
  // ============================================================

  group('Multi-device: удаление записи на A доходит до B', () {
    late AppDatabase dbA;
    late AppDatabase dbB;
    late TrackingFakeBackend backend;
    late DiaryProvider providerA;
    late DiaryProvider providerB;
    late DiarySyncEngine engineB;

    setUp(() async {
      // Два изолированных устройства, общий «сервер» (backend).
      dbA = await createIsolatedDb();
      dbB = await createIsolatedDb();
      backend = TrackingFakeBackend(user: 'user-multidev');
      final knownA = MemoryKnownStore();
      final engineA = DiarySyncEngine(
          db: dbA, backend: backend, knownStore: knownA);
      await engineA.loadKnown();
      engineB = DiarySyncEngine(
          db: dbB,
          backend: backend,
          knownStore: MemoryKnownStore());
      await engineB.loadKnown();
      providerA = DiaryProvider(db: dbA, engine: engineA);
      await providerA.load();
      providerB = DiaryProvider(db: dbB, engine: engineB);
      await providerB.load();
      backend.isReady = true;
    });

    tearDown(() async {
      await dbA.deleteAllDiaryEntries();
      await dbB.deleteAllDiaryEntries();
    });

    test(
        'после удаления на A запись удаляется локально и на B после синка',
        () async {
      final uuid = 'uuid-multidev-remove';
      final photo = await createTempFileForTest('$uuid.jpg');

      // A добавляет запись с uuid на сервер (как делает addEntry+upload).
      await dbA.insertDiaryEntry(entry(
        uuid: uuid,
        date: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1, 10),
        species: 'Кабан',
        photoPath: photo.path,
        photoUrl: 'user-multidev/$uuid.jpg',
      ));

      // A синкает — локальная запись заливается на сервер.
      await providerA.engine.sync();
      expect(backend.server.containsKey(uuid), isTrue,
          reason: 'A должен залить запись на сервер');

      // B впервые синкает — подтягивает запись и узнаёт uuid в known.
      await providerB.engine.sync();
      var localB = await dbB.getDiaryEntries();
      expect(localB.any((e) => e.uuid == uuid), isTrue,
          reason: 'B должен увидеть запись после первого синка');

      // A удаляет запись (локально + с сервера + забывает uuid).
      final onA = (await dbA.getDiaryEntries()).first;
      await providerA.deleteEntry(onA.id!);
      expect(backend.server.containsKey(uuid), isFalse,
          reason: 'A должен удалить запись с сервера');

      // B делает синк — удалённая запись обязана исчезнуть локально.
      await providerB.engine.sync();
      localB = await dbB.getDiaryEntries();
      expect(localB.any((e) => e.uuid == uuid), isFalse,
          reason: 'B должен удалить запись после синка (удаление с A)');
    });
  });
}
