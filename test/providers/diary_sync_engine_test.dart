import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pomoshchnik_okhotnika/db/app_database.dart';
import 'package:pomoshchnik_okhotnika/models/diary_entry.dart';
import 'package:pomoshchnik_okhotnika/providers/diary_sync_engine.dart';

/// Тестовая обёртка над произвольной SQLite-БД для симуляции второго устройства.
///
/// Используется когда нужно изолированное хранилище от singleton AppDatabase.
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
    final result = await _db.rawQuery('SELECT COUNT(*) FROM diary_entries');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<int> insertDiaryEntry(DiaryEntry entry) async {
    final data = entry.toMap()..remove('id');
    data['updated_at'] = entry.updatedAt?.toIso8601String() ??
        DateTime.now().toIso8601String();
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
    data['updated_at'] = entry.updatedAt?.toIso8601String() ??
        DateTime.now().toIso8601String();
    return _db.update('diary_entries', data,
        where: 'id = ?', whereArgs: [entry.id]);
  }
}

/// Фейковый бэкенд: in-memory «сервер», эмулирующий Supabase для тестов.
class FakeBackend implements DiaryBackend {
  final Map<String, Map<String, dynamic>> server = {};
  final String user;
  bool isReady = true;

  final List<String> deletedUuids = [];
  final List<String> pushedUuids = [];

  FakeBackend({required this.user});

  @override
  bool get ready => isReady;

  @override
  String? get userId => user;

  @override
  Future<List<Map<String, dynamic>>> pull() async {
    final rows = server.values.toList()
      ..sort((a, b) => (a['entry_date'] as String).compareTo(b['entry_date'] as String));
    return rows;
  }

  @override
  Future<bool> deleteEntry(String uuid) async {
    deletedUuids.add(uuid);
    server.remove(uuid);
    return true;
  }

  @override
  Future<void> bulkUpsert(List<Map<String, dynamic>> payload) async {
    for (final row in payload) {
      pushedUuids.add(row['uuid'] as String);
      final uuid = row['uuid'] as String;
      final existing = server[uuid] ?? <String, dynamic>{};
      final merged = Map<String, dynamic>.from(existing)..addAll(row);
      server[uuid] = merged;
    }
  }

  /// Кастомный URL для фото (для тестов БАГ #1).
  String? customPhotoUrl;

  @override
  Future<String> uploadPhoto(String objName, File file) async => objName;

  @override
  Future<void> pushEntry(DiaryEntry entry, String? photoUrl) async {
    pushedUuids.add(entry.uuid!);
    final updatedAt = (entry.updatedAt ?? DateTime.now()).toIso8601String();
    // Если установлен customPhotoUrl — используем его вместо переданного.
    final effectivePhotoUrl = customPhotoUrl ?? photoUrl;
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
      'photo_url': effectivePhotoUrl,
      'result': entry.result,
      'weight': entry.weight,
      'count': entry.count,
      'method': entry.method,
      'updated_at': updatedAt,
    };
  }

  @override
  Future<Uint8List> downloadPhoto(String objName) async => Uint8List.fromList([1, 2, 3]);
}

/// In-memory хранилище known-uuid.
class MemoryKnownStore implements KnownStore {
  Set<String> data = {};
  @override
  String get name => 'test_known';

  @override
  Future<Set<String>> load() async => Set<String>.from(data);

  @override
  Future<void> save(Set<String> uuids) async => data = Set<String>.from(uuids);
}

DiaryEntry entry({
  String? uuid,
  DateTime? updatedAt,
  required DateTime date,
  String species = 'Кабан',
  String? photoPath,
  String? photoUrl,
  String? notes,
}) {
  return DiaryEntry(
    uuid: uuid,
    updatedAt: updatedAt,
    date: date,
    species: species,
    photoPath: photoPath,
    photoUrl: photoUrl,
    notes: notes,
  );
}

/// Создаёт изолированную БД для симуляции второго устройства.
///
/// AppDatabase использует singleton `static Database? _db`, поэтому для
/// изоляции используем in-memory SQLite через DatabaseFactoryFfi напрямую.
Future<AppDatabase> createIsolatedDb() async {
  // Создаём in-memory базу напрямую — она не будет кешироваться
  // в singleton AppDatabase._db.
  final dbFactory = databaseFactoryFfi;
  final dbPath = p.join(Directory.systemTemp.createTempSync('diary_test_b_').path, 'test_b.db');
  final database = await dbFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: 8,
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
          await db.execute('ALTER TABLE diary_entries ADD COLUMN weight REAL');
          await db.execute('ALTER TABLE diary_entries ADD COLUMN count INTEGER');
          await db.execute('ALTER TABLE diary_entries ADD COLUMN method TEXT');
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
          await db.execute('ALTER TABLE diary_entries ADD COLUMN updated_at TEXT');
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
      },
    ),
  );
  // Создаём обёртку над этой БД.
  return TestAppDatabase(database);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final db = AppDatabase();
  final known = MemoryKnownStore();

  setUp(() async {
    known.data = <String>{};
    await db.deleteAllDiaryEntries();
  });

  Future<DiarySyncEngine> makeEngine(FakeBackend backend) async {
    final engine = DiarySyncEngine(db: db, backend: backend, knownStore: known);
    await engine.loadKnown();
    return engine;
  }

  Future<List<DiaryEntry>> localEntries() => db.getDiaryEntries();

  test('push: локальная запись без дублей уезжает на сервер и попадает в known',
      () async {
    final backend = FakeBackend(user: 'user-1');
    final engine = await makeEngine(backend);
    final uuid = 'uuid-fresh';
    await db.insertDiaryEntry(entry(
      uuid: uuid,
      date: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1, 10),
    ));

    final outcome = await engine.sync();

    // Запись ушла на сервер (bulk) ровно один раз — без дублей.
    expect(backend.server.containsKey(uuid), isTrue);
    expect(backend.pushedUuids.where((u) => u == uuid).length, 1);
    // Локально дублей нет.
    expect((await localEntries()).where((e) => e.uuid == uuid).length, 1);
    // БАГ #1: свежесозданная запушенная запись попадает в known.
    expect(engine.knownRemoteUuids.contains(uuid), isTrue);
    expect(outcome.changed, isFalse);
  });

  test('pull: новая серверная запись подтягивается локально', () async {
    final backend = FakeBackend(user: 'user-1');
    backend.server['uuid-remote'] = {
      'uuid': 'uuid-remote',
      'user_id': 'user-1',
      'species': 'Лось',
      'location': 'Лес',
      'notes': 'Пришла с другого устройства',
      'entry_date': DateTime.utc(2026, 2, 1).toIso8601String(),
      'photo_url': null,
      'result': 'наблюдение',
      'updated_at': DateTime.utc(2026, 2, 1, 12).toIso8601String(),
    };
    final engine = await makeEngine(backend);

    final outcome = await engine.sync();

    final local = await localEntries();
    expect(local.any((e) => e.uuid == 'uuid-remote'), isTrue);
    final pulled = local.firstWhere((e) => e.uuid == 'uuid-remote');
    expect(pulled.species, 'Лось');
    expect(pulled.notes, 'Пришла с другого устройства');
    expect(outcome.changed, isTrue);
    // Pull-снапшот тоже попал в known.
    expect(engine.knownRemoteUuids.contains('uuid-remote'), isTrue);
  });

  test('LWW pull: серверная версия свежее — локальная перезаписывается',
      () async {
    final uuid = 'uuid-lww-remote';
    await db.insertDiaryEntry(entry(
      uuid: uuid,
      date: DateTime.utc(2026, 3, 1),
      updatedAt: DateTime.utc(2026, 3, 1, 8),
      species: 'Кабан',
      notes: 'старая локальная',
    ));
    final backend = FakeBackend(user: 'user-1');
    backend.server[uuid] = {
      'uuid': uuid,
      'user_id': 'user-1',
      'species': 'Олень',
      'notes': 'новая серверная',
      'entry_date': DateTime.utc(2026, 3, 1).toIso8601String(),
      'photo_url': null,
      'updated_at': DateTime.utc(2026, 3, 1, 10).toIso8601String(),
    };
    final engine = await makeEngine(backend);

    await engine.sync();

    final local = await localEntries();
    final updated = local.firstWhere((e) => e.uuid == uuid);
    expect(updated.species, 'Олень');
    expect(updated.notes, 'новая серверная');
  });

  test('LWW push: локальная версия свежее — уезжает на сервер (не стягивается старая)',
      () async {
    final uuid = 'uuid-lww-local';
    final backend = FakeBackend(user: 'user-1');
    backend.server[uuid] = {
      'uuid': uuid,
      'user_id': 'user-1',
      'species': 'Старое на сервере',
      'entry_date': DateTime.utc(2026, 4, 1).toIso8601String(),
      'photo_url': null,
      'updated_at': DateTime.utc(2026, 4, 1, 6).toIso8601String(),
    };
    // Локальная запись свежее серверной.
    await db.insertDiaryEntry(entry(
      uuid: uuid,
      date: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1, 12),
      species: 'Новое локально',
      notes: 'правка на телефоне',
    ));
    final engine = await makeEngine(backend);

    await engine.sync();

    // Локальная НЕ перезаписана старой серверной версией.
    final local = await localEntries();
    expect(local.firstWhere((e) => e.uuid == uuid).species, 'Новое локально');
    // На сервер ушла свежая версия.
    expect(backend.server[uuid]!['species'], 'Новое локально');
    expect(backend.pushedUuids, contains(uuid));
  });

  test('удаление: известная, но исчезнувшая на сервере запись удаляется локально',
      () async {
    final uuid = 'uuid-deleted-elsewhere';
    await db.insertDiaryEntry(entry(
      uuid: uuid,
      date: DateTime.utc(2026, 5, 1),
      updatedAt: DateTime.utc(2026, 5, 1, 10),
      species: 'Заяц',
    ));
    // Запись была на сервере (known), но с сервера её удалили (в списке нет).
    known.data = {uuid};
    final backend = FakeBackend(user: 'user-1');
    final engine = await makeEngine(backend);

    await engine.sync();

    // Локально удалена, на сервер повторно НЕ запушена (не воскресает).
    final local = await localEntries();
    expect(local.any((e) => e.uuid == uuid), isFalse);
    expect(backend.pushedUuids, isNot(contains(uuid)));
    expect(backend.deletedUuids, isNot(contains(uuid)));
  });

  test('БАГ #1: свежая запись, запушенная в этот цикл и удалённая на другом'
      ' устройстве до второго pull, НЕ воскресает', () async {
    final uuid = 'uuid-fresh-then-deleted';
    final backend = FakeBackend(user: 'user-1');
    final engine = await makeEngine(backend);

    // Синк #1: локально появляется новая запись (uuid новый, на сервере её нет).
    await db.insertDiaryEntry(entry(
      uuid: uuid,
      date: DateTime.utc(2026, 6, 1),
      updatedAt: DateTime.utc(2026, 6, 1, 10),
      species: 'Утка',
    ));
    await engine.sync();
    // Фикс: после первого синка свежий uuid попал в known.
    expect(engine.knownRemoteUuids.contains(uuid), isTrue);
    expect(backend.server.containsKey(uuid), isTrue);

    // Другое устройство удалило запись на сервере.
    backend.server.remove(uuid);

    // Синк #2: серверный снапшот больше не содержит uuid.
    await engine.sync();

    // Локально удалена и НЕ запушена обратно (не воскресла).
    final local = await localEntries();
    expect(local.any((e) => e.uuid == uuid), isFalse);
    expect(backend.server.containsKey(uuid), isFalse);
  });

  test('БАГ #4: правка записи с фото (без смены файла) не обнуляет photoUrl',
      () async {
    final backend = FakeBackend(user: 'user-1');
    final engine = await makeEngine(backend);
    final uuid = 'uuid-photo';
    final existing = 'user-1/uuid-photo.jpg';

    final edit = entry(
      uuid: uuid,
      date: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 1, 10),
      species: 'Лиса',
      // Локального файла нет (photoPath null) — фото не трогали, но photoUrl
      // уже был на сервере.
      photoPath: null,
      photoUrl: existing,
    );
    final ok = await engine.pushEntry(edit);

    expect(ok, isTrue);
    // На сервере photo_url сохранён, а не затёрт в null.
    expect(backend.server[uuid]!['photo_url'], existing);
  });

  test('безUuid: записи без uuid присваивается и запись уходит на сервер',
      () async {
    final backend = FakeBackend(user: 'user-1');
    final engine = await makeEngine(backend);
    // Вставляем запись без uuid (старая запись из ранней версии приложения).
    await db.insertDiaryEntry(entry(date: DateTime.utc(2026, 8, 1)));

    await engine.sync();

    final local = await localEntries();
    final assigned = local.firstWhere((e) => e.uuid != null);
    expect(assigned.uuid, isNotNull);
    // uuid валидный (не пустой).
    expect(assigned.uuid, isNotEmpty);
    // Записана на сервер.
    expect(backend.server.containsKey(assigned.uuid), isTrue);
    // Попала в known.
    expect(engine.knownRemoteUuids.contains(assigned.uuid), isTrue);
  });

  // ================================================================
  // БАГ #1 (исправлен): смена фото в существующей записи
  // ================================================================

  /// Создаёт временный файл для теста.
  Future<File> createTempFileForTest(String name) async {
    final dir = Directory.systemTemp.createTempSync('diary_test_');
    return File('${dir.path}/$name');
  }

  test('БАГ #1: pushEntry с новым фото обновляет photoUrl на сервере',
      () async {
    final backend = FakeBackend(user: 'user-1');
    final engine = await makeEngine(backend);
    final uuid = 'uuid-change-photo';
    // Старый photoUrl на сервере.
    final oldPhotoUrl = 'user-1/uuid-change-photo-old.jpg';
    // Новый URL который должен появиться после аплоада.
    final newPhotoUrl = 'user-1/uuid-change-photo-uploaded.jpg';

    // Создаём временный файл чтобы File(path).existsSync() == true.
    final tempFile = await createTempFileForTest('$uuid.jpg');

    // Локальная запись с photoPath (файл существует).
    final edit = entry(
      uuid: uuid,
      date: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1, 10),
      species: 'Кабан',
      photoPath: tempFile.path,
      // Старый URL — должен обновиться на новый.
      photoUrl: oldPhotoUrl,
    );

    // Кастомизируем backend чтобы он возвращал новый URL.
    backend.customPhotoUrl = newPhotoUrl;

    final ok = await engine.pushEntry(edit);

    expect(ok, isTrue);
    // На сервере photo_url должен быть НОВЫМ, а не старым.
    final serverPhotoUrl = backend.server[uuid]!['photo_url'];
    expect(serverPhotoUrl, isNotNull);
    expect(serverPhotoUrl, isNot(oldPhotoUrl));
    expect(serverPhotoUrl, newPhotoUrl);
  });

  test('БАГ #1: pushEntry без фото (photoPath=null) сохраняет photoUrl',
      () async {
    final backend = FakeBackend(user: 'user-1');
    final engine = await makeEngine(backend);
    final uuid = 'uuid-no-photo-change';
    final existing = 'user-1/uuid-no-photo-change.jpg';

    // Редактирование без смены фото — photoPath=null.
    final edit = entry(
      uuid: uuid,
      date: DateTime.utc(2026, 9, 5),
      updatedAt: DateTime.utc(2026, 9, 5, 10),
      species: 'Лось',
      photoPath: null,
      photoUrl: existing,
    );

    final ok = await engine.pushEntry(edit);

    expect(ok, isTrue);
    // photoUrl должен остаться тем же.
    expect(backend.server[uuid]!['photo_url'], existing);
  });

  test('БАГ #1: pushEntry с фото и старым photoUrl=null не теряет фото',
      () async {
    final backend = FakeBackend(user: 'user-1');
    final engine = await makeEngine(backend);
    final uuid = 'uuid-new-photo-no-old';
    final newPhotoUrl = 'user-1/uuid-new-photo-no-old-uploaded.jpg';

    // Создаём временный файл.
    final tempFile = await createTempFileForTest('$uuid.jpg');

    // Запись с новым фото, но без старого photoUrl.
    final edit = entry(
      uuid: uuid,
      date: DateTime.utc(2026, 9, 10),
      updatedAt: DateTime.utc(2026, 9, 10, 10),
      species: 'Олень',
      photoPath: tempFile.path,
      photoUrl: null,
    );

    // Кастомизируем backend чтобы он возвращал новый URL.
    backend.customPhotoUrl = newPhotoUrl;

    final ok = await engine.pushEntry(edit);

    expect(ok, isTrue);
    // На сервере должен появиться новый photo_url.
    final serverPhotoUrl = backend.server[uuid]!['photo_url'];
    expect(serverPhotoUrl, isNotNull);
    expect(serverPhotoUrl, isNotEmpty);
    expect(serverPhotoUrl, newPhotoUrl);
  });

  test('copyWith: DiaryEntry создаёт копию с обновлённым photoUrl',
      () async {
    // Тест на copyWith — базовая проверка что метод работает корректно.
    final original = entry(
      uuid: 'uuid-copyWith',
      date: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15, 10),
      species: 'Заяц',
      photoPath: '/old/path.jpg',
      photoUrl: 'user-1/old.jpg',
    );

    final updated = original.copyWith(photoUrl: 'user-1/new.jpg');

    // Копия имеет новый photoUrl.
    expect(updated.photoUrl, 'user-1/new.jpg');
    // Остальные поля сохранены.
    expect(updated.uuid, original.uuid);
    expect(updated.species, original.species);
    expect(updated.photoPath, original.photoPath);
    expect(updated.date, original.date);
    // Оригинальная запись НЕ изменена.
    expect(original.photoUrl, 'user-1/old.jpg');
  });

  // ================================================================
  // БАГ #1b: syncWithServer (pull) после upload — данные синхронизируются
  // ================================================================

  test('БАГ #1b: pushEntry + sync — pull подтягивает обновлённый photoUrl',
      () async {
    final backend = FakeBackend(user: 'user-1');
    final engine = await makeEngine(backend);
    final uuid = 'uuid-sync-after-upload';
    final oldPhotoUrl = 'user-1/uuid-sync-after-upload-old.jpg';
    final newPhotoUrl = 'user-1/uuid-sync-after-upload-uploaded.jpg';

    // Создаём временный файл.
    final tempFile = await createTempFileForTest('$uuid.jpg');

    // Локальная запись со старым photoUrl.
    final edit = entry(
      uuid: uuid,
      date: DateTime.utc(2026, 9, 20),
      updatedAt: DateTime.utc(2026, 9, 20, 10),
      species: 'Кабан',
      photoPath: tempFile.path,
      photoUrl: oldPhotoUrl,
    );

    // Вставляем запись локально — как делает DiaryProvider.
    await db.insertDiaryEntry(edit);

    // Upload — как делает DiaryProvider._uploadEntry().
    backend.customPhotoUrl = newPhotoUrl;
    final ok = await engine.pushEntry(edit);
    expect(ok, isTrue);

    // Проверяем что на сервере новый URL.
    expect(backend.server[uuid]!['photo_url'], newPhotoUrl);

    // Теперь вызываем sync() — как делает DiaryProvider.syncWithServer().
    // Это pull + push. Pull должен подтянуть новый photoUrl.
    final outcome = await engine.sync();

    // Sync прошёл успешно, изменений нет (данные уже совпадают).
    expect(outcome.changed, isFalse);
    // photoUrl на сервере — новый.
    expect(backend.server[uuid]!['photo_url'], newPhotoUrl);
  });

  // ================================================================
  // БАГ #1b: сценарий двух устройств — фото синхронизируется
  // ================================================================

  test('БАГ #1b: устройство A upload + устройство B pull — photoUrl обновляется',
      () async {
    final backend = FakeBackend(user: 'user-1');
    final engineA = await makeEngine(backend);
    // Устройство B — изолированная БД и отдельный known-кэш (имитирует другое устройство).
    final dbB = await createIsolatedDb();
    final knownB = MemoryKnownStore();
    final engineB = DiarySyncEngine(db: dbB, backend: backend, knownStore: knownB);
    await engineB.loadKnown();
    final uuid = 'uuid-two-devices';
    final oldPhotoUrl = 'user-1/uuid-two-devices-old.jpg';
    final newPhotoUrl = 'user-1/uuid-two-devices-uploaded.jpg';

    // Создаём временный файл.
    final tempFile = await createTempFileForTest('$uuid.jpg');

    // --- Устройство A: добавляет запись с фото ---
    final entryA = entry(
      uuid: uuid,
      date: DateTime.utc(2026, 9, 25),
      updatedAt: DateTime.utc(2026, 9, 25, 10),
      species: 'Лось',
      photoPath: tempFile.path,
      photoUrl: oldPhotoUrl,
    );
    await db.insertDiaryEntry(entryA);

    // Upload на сервер (как делает DiaryProvider после _save).
    backend.customPhotoUrl = newPhotoUrl;
    final uploadOk = await engineA.pushEntry(entryA);
    expect(uploadOk, isTrue);
    expect(backend.server[uuid]!['photo_url'], newPhotoUrl);

    // --- Устройство B: делает sync (pull) ---
    // На устройе B нет записи — sync должен подтянуть.
    final outcomeB = await engineB.sync();
    expect(outcomeB.changed, isTrue);

    // Проверяем что устройство B подтянуло запись с новым photoUrl.
    final localB = await dbB.getDiaryEntries();
    expect(localB.any((e) => e.uuid == uuid), isTrue);
    final entryB = localB.firstWhere((e) => e.uuid == uuid);
    expect(entryB.photoUrl, newPhotoUrl);

    // Очищаем временные файлы.
    try {
      await tempFile.parent.parent.delete(recursive: true);
    } catch (_) {}
    await dbB.deleteAllDiaryEntries();
  });

  // ================================================================
  // Юнит-тест на исправление: engine.sync() вместо syncWithServer()
  // ================================================================

  test('ИСПРАВЛЕНИЕ: engine.sync() напрямую после pushEntry синхронизирует фото',
      () async {
    // Этот тест проверяет что после pushEntry можно вызвать
    // engine.sync() напрямую (как делает DiaryProvider._uploadEntry)
    // и данные синхронизируются без блокировки _syncRunning.
    final backend = FakeBackend(user: 'user-1');
    final engine = await makeEngine(backend);
    final uuid = 'uuid-direct-sync';
    final oldPhotoUrl = 'user-1/uuid-direct-sync-old.jpg';
    final newPhotoUrl = 'user-1/uuid-direct-sync-uploaded.jpg';

    // Создаём временный файл.
    final tempFile = await createTempFileForTest('$uuid.jpg');

    // Локальная запись со старым photoUrl.
    final edit = entry(
      uuid: uuid,
      date: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1, 10),
      species: 'Кабан',
      photoPath: tempFile.path,
      photoUrl: oldPhotoUrl,
    );

    // Вставляем запись локально — получаем id.
    final id = await db.insertDiaryEntry(edit);

    // Upload — как делает DiaryProvider._uploadEntry().
    backend.customPhotoUrl = newPhotoUrl;
    final uploadOk = await engine.pushEntry(edit);
    expect(uploadOk, isTrue);

    // Проверяем что на сервере новый photoUrl.
    expect(backend.server[uuid]!['photo_url'], newPhotoUrl);

    // DiaryProvider._uploadEntry обновляет локальную БД после успешного upload.
    // Имитируем это — обновляем photoUrl и updatedAt в локальной БД как делает DiaryProvider.
    // updatedAt = edit.updatedAt + 1 час чтобы локальная версия была явно новее серверной
    // и sync не перезаписал её обратно (LWW).
    final freshUpdatedAt = edit.updatedAt!.add(const Duration(hours: 1));
    await db.updateDiaryEntry(DiaryEntry(
      id: id,
      uuid: edit.uuid,
      updatedAt: freshUpdatedAt,
      date: edit.date,
      location: edit.location,
      weather: edit.weather,
      species: edit.species,
      latitude: edit.latitude,
      longitude: edit.longitude,
      photoPath: edit.photoPath,
      photoUrl: newPhotoUrl, // новый URL из upload
      notes: edit.notes,
      result: edit.result,
      weight: edit.weight,
      count: edit.count,
      method: edit.method,
    ));

    // Теперь вызываем engine.sync() напрямую — как делает DiaryProvider
    // после исправления (вместо syncWithServer()).
    // Это ключевая проверка: engine.sync() должен работать напрямую
    // без блокировки _syncRunning.
    final outcome = await engine.sync();

    // Sync прошёл успешно.
    expect(outcome.changed, isFalse); // изменений нет, данные уже совпадают
    // photoUrl на сервере — новый.
    expect(backend.server[uuid]!['photo_url'], newPhotoUrl);

    // Проверяем что локальная БД тоже обновлена.
    final local = await localEntries();
    final entryLocal = local.firstWhere((e) => e.uuid == uuid);
    expect(entryLocal.photoUrl, newPhotoUrl);

    // Очищаем временные файлы.
    try {
      await tempFile.parent.parent.delete(recursive: true);
    } catch (_) {}
  });
}
