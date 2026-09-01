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

class PhotoStatusTestDb implements AppDatabase {
  final Database _db;
  PhotoStatusTestDb(this._db);

  @override
  Future<List<DiaryEntry>> getDiaryEntries() async {
    final rows = await _db.query('diary_entries', orderBy: 'date DESC');
    return rows.map(DiaryEntry.fromMap).toList();
  }

  @override
  Future<int> getDiaryCount() async {
    final r = await _db.rawQuery('SELECT COUNT(*) FROM diary_entries');
    return Sqflite.firstIntValue(r) ?? 0;
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
  Future<int> deleteDiaryEntry(int id) async =>
      _db.delete('diary_entries', where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> deleteAllDiaryEntries() async => _db.delete('diary_entries');

  @override
  Future<int> updateDiaryEntry(DiaryEntry entry) async {
    final data = entry.toMap()..remove('id');
    data['updated_at'] =
        entry.updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String();
    return _db.update('diary_entries', data,
        where: 'id = ?', whereArgs: [entry.id]);
  }
}

Future<AppDatabase> createDb() async {
  final dbFactory = databaseFactoryFfi;
  final dbPath = p.join(
      Directory.systemTemp.createTempSync('diary_status_').path, 'test.db');
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
        },
      ));
  return PhotoStatusTestDb(database);
}

class FailAwareBackend implements DiaryBackend {
  final String user;
  final Map<String, Map<String, dynamic>> server = {};
  bool isReady = true;
  bool failPhotoUpload = false;
  int uploadPhotoCalls = 0;

  FailAwareBackend(this.user);

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
      'updated_at':
          (entry.updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  @override
  Future<String> uploadPhoto(String objName, File file) async {
    uploadPhotoCalls++;
    if (failPhotoUpload) {
      throw Exception('upload photo failed (test)');
    }
    return objName;
  }

  @override
  Future<Uint8List> downloadPhoto(String objName) async =>
      Uint8List.fromList([1, 2, 3]);

  @override
  Future<void> deletePhoto(String objName) async {}
}

class MemKnownStore implements KnownStore {
  Set<String> data = {};
  @override
  String get name => 'known_status';
  @override
  Future<Set<String>> load() async => Set<String>.from(data);
  @override
  Future<void> save(Set<String> uuids) async => data = Set<String>.from(uuids);
}

DiaryEntry entry({
  int? id,
  String? uuid,
  DateTime? updatedAt,
  required DateTime date,
  String species = 'Кабан',
  String? photoPath,
  String? photoUrl,
  String? photoUploadState,
}) {
  return DiaryEntry(
    id: id,
    uuid: uuid,
    updatedAt: updatedAt,
    date: date,
    species: species,
    photoPath: photoPath,
    photoUrl: photoUrl,
    photoUploadState: photoUploadState,
  );
}

Future<File> tempFile(String name) async {
  final dir = Directory.systemTemp.createTempSync('diary_status_');
  final f = File('${dir.path}/$name');
  await f.writeAsBytes([1, 2, 3, 4]);
  return f;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Модель DiaryEntry — photoUploadState', () {
    test('toMap/fromMap сохраняет статус', () {
      final e = entry(
        uuid: 'u1',
        date: DateTime.utc(2026, 9, 1),
        photoPath: '/tmp/a.jpg',
        photoUrl: 'u1/obj.jpg',
        photoUploadState: 'failed',
      );
      final m = e.toMap();
      expect(m['photo_upload_state'], 'failed');
      final back = DiaryEntry.fromMap(m);
      expect(back.photoUploadState, 'failed');
    });

    test('copyWith может явно сбросить фото-поля и статус на null', () {
      final e = entry(
        uuid: 'u2',
        date: DateTime.utc(2026, 9, 1),
        photoPath: '/tmp/b.jpg',
        photoUrl: 'u2/obj.jpg',
        photoUploadState: 'failed',
      );
      final reset = e.copyWith(
        photoPath: null,
        photoUrl: null,
        photoUploadState: null,
      );
      expect(reset.photoPath, isNull);
      expect(reset.photoUrl, isNull);
      expect(reset.photoUploadState, isNull);
    });
  });

  group('Движок — статусы _pushWithPhoto (pushEntryWithPhoto)', () {
    late AppDatabase db;
    late FailAwareBackend backend;
    late DiarySyncEngine engine;

    setUp(() async {
      db = await createDb();
      backend = FailAwareBackend('u-status');
      engine = DiarySyncEngine(
          db: db, backend: backend, knownStore: MemKnownStore());
      await engine.loadKnown();
    });

    test('успешный upload фото → статус null (тихо)', () async {
      final f = await tempFile('ok.jpg');
      final e = entry(
        uuid: 'u-ok',
        date: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1, 10),
        photoPath: f.path,
      );
      final res = await engine.pushEntryWithPhoto(e);
      expect(res, isNotNull);
      expect(res!.photoUploadState, isNull);
      expect(res.photoUrl, isNotNull);
    });

    test('провал upload фото → статус failed', () async {
      backend.failPhotoUpload = true;
      final f = await tempFile('fail.jpg');
      final e = entry(
        uuid: 'u-fail',
        date: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1, 10),
        photoPath: f.path,
      );
      final res = await engine.pushEntryWithPhoto(e);
      expect(res, isNotNull);
      expect(res!.photoUploadState, 'failed');
    });
  });

  group('Провайдер — retryPhotoUpload / removePhoto', () {
    late AppDatabase db;
    late FailAwareBackend backend;
    late DiarySyncEngine engine;

    setUp(() async {
      db = await createDb();
      backend = FailAwareBackend('u-prov');
      engine = DiarySyncEngine(
          db: db, backend: backend, knownStore: MemKnownStore());
      await engine.loadKnown();
    });

    test('retryPhotoUpload ставит uploading и успешно завершается → статус null',
        () async {
      final provider = DiaryProvider(db: db, engine: engine);
      await provider.load();
      final f = await tempFile('retry.jpg');
      final e = entry(
        uuid: 'u-retry',
        date: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1, 10),
        photoPath: f.path,
        photoUrl: 'u-prov/old.jpg',
      );
      final id = await db.insertDiaryEntry(e);
      final saved = await db.getDiaryEntries();
      final withId = saved.firstWhere((x) => x.id == id);

      await provider.retryPhotoUpload(withId);

      // Дожидаемся завершения фоновой очереди.
      await provider.uploadQueue;

      final after = await db.getDiaryEntries();
      final updated = after.firstWhere((x) => x.id == id);
      expect(updated.photoUploadState, isNull);
      expect(backend.server.containsKey('u-retry'), isTrue);
    });

    test('removePhoto при офлайне чистит локальное фото и ставит tombstone',
        () async {
      // backend выключаем до создания провайдера: стартовый фоновый sync
      // (unawaited(syncWithServer()) в конструкторе) сразу выйдет по
      // !ready и не перезапишет запись после удаления фото.
      backend.isReady = false;
      final provider = DiaryProvider(db: db, engine: engine);
      await provider.load();

      final f = await tempFile('del.jpg');
      final e = entry(
        uuid: 'u-del',
        date: DateTime.utc(2026, 9, 1),
        photoPath: f.path,
        photoUrl: 'u-prov/del.jpg',
        photoUploadState: 'failed',
      );
      final id = await db.insertDiaryEntry(e);
      final saved = await db.getDiaryEntries();
      final withId = saved.firstWhere((x) => x.id == id);
      expect(File(f.path).existsSync(), isTrue);

      final ok = await provider.removePhoto(withId);
      expect(ok, isTrue);

      final after = await db.getDiaryEntries();
      final updated = after.firstWhere((x) => x.id == id);
      // Локально фото удалено; objName сохранён в photoUrl, tombstone 'removed',
      // чтобы после восстановления сети sync доудалил объект и не вернул фото.
      expect(updated.photoPath, isNull);
      expect(updated.photoUrl, 'u-prov/del.jpg');
      expect(updated.photoUploadState, 'removed');
      expect(File(f.path).existsSync(), isFalse);
      expect(provider.isRemovingPhoto(withId), isFalse);
    });

    test('removePhoto офлайн → sync при сети: фото не возвращается и tombstone снимается',
        () async {
      // Проверяем критичный сценарий из запроса: удалил фото офлайн, потом
      // сеть появилась — синхронизация должна доудалить объект и НЕ вернуть
      // фотографию.
      //
      // Provider создаём при offline, чтобы стартовый фоновый sync в
      // конструкторе (unawaited(syncWithServer())) сразу вышел по !ready и
      // не мешал. Затем переключаем сеть вручную.
      backend.isReady = false;
      final provider = DiaryProvider(db: db, engine: engine);
      await provider.load();

      final f = await tempFile('del-offline-sync.jpg');
      final e = entry(
        uuid: 'u-del-offsync',
        date: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1, 10),
        photoPath: f.path,
        photoUrl: 'u-prov/del-offsync.jpg',
        photoUploadState: 'failed',
      );
      final id = await db.insertDiaryEntry(e);
      final saved = await db.getDiaryEntries();
      final withId = saved.firstWhere((x) => x.id == id);

      // Сначала заливаем запись на сервер с фото (как после успешного upload):
      // локальная запись и сервер равны по updated_at, фото на сервере есть.
      backend.isReady = true;
      await engine.sync();
      final serverUrl = backend.server['u-del-offsync']?['photo_url'];
      expect(serverUrl, isNotNull);

      // Пользователь перестал ловить сеть и удаляет фото.
      backend.isReady = false;
      final ok = await provider.removePhoto(withId);
      expect(ok, isTrue);
      var after = await db.getDiaryEntries();
      var tombstone = after.firstWhere((x) => x.id == id);
      expect(tombstone.photoUploadState, 'removed');

      // Сеть вернулась — синхронизация доудаляет фото и не «возвращает» его.
      backend.isReady = true;
      await provider.syncWithServer();
      await provider.uploadQueue;

      after = await db.getDiaryEntries();
      final updated = after.firstWhere((x) => x.id == id);
      expect(updated.photoPath, isNull);
      expect(updated.photoUploadState, isNull);
      expect(updated.photoUrl, isNull);
      expect(File(f.path).existsSync(), isFalse);
      // На сервере photo_url занулён — фото не «воскреснет» на других устройствах.
      expect(backend.server['u-del-offsync']?['photo_url'], isNull);
    });

    test('removePhoto при включённой сети снимает фото без tombstone', () async {
      // Provider создаём при offline, чтобы фоновый sync не вмешивался,
      // затем включаем сеть.
      backend.isReady = false;
      final provider = DiaryProvider(db: db, engine: engine);
      await provider.load();

      final f = await tempFile('del-online.jpg');
      final e = entry(
        uuid: 'u-del-online',
        date: DateTime.utc(2026, 9, 1),
        photoPath: f.path,
        photoUrl: 'u-prov/del-online.jpg',
        photoUploadState: 'failed',
      );
      final id = await db.insertDiaryEntry(e);
      final saved = await db.getDiaryEntries();
      final withId = saved.firstWhere((x) => x.id == id);

      backend.isReady = true;
      final ok = await provider.removePhoto(withId);
      expect(ok, isTrue);

      final after = await db.getDiaryEntries();
      final updated = after.firstWhere((x) => x.id == id);
      expect(updated.photoPath, isNull);
      expect(updated.photoUrl, isNull);
      expect(updated.photoUploadState, isNull);
      expect(File(f.path).existsSync(), isFalse);
    });

    test('removePhoto у записи без id → false (UI покажет «Повторить»)',
        () async {
      backend.isReady = false;
      final provider = DiaryProvider(db: db, engine: engine);
      await provider.load();

      final f = await tempFile('del-no-id.jpg');
      final e = entry(
        uuid: 'u-del-noid',
        date: DateTime.utc(2026, 9, 1),
        photoPath: f.path,
        photoUploadState: 'failed',
      );
      final ok = await provider.removePhoto(e);
      expect(ok, isFalse);
      expect(File(f.path).existsSync(), isTrue);
      expect(provider.isRemovingPhoto(e), isFalse);
    });
  });

  group('Движок — авто-ретрай фото в sync()', () {
    test('failed-запись: при успешном повторном upload статус очищается '
        'и upload вызван ровно один раз дополнительно', () async {
      final db = await createDb();
      final backend = FailAwareBackend('u-sync');
      final engine = DiarySyncEngine(
          db: db, backend: backend, knownStore: MemKnownStore());
      await engine.loadKnown();

      // Запись уже синхронизирована на сервере (текстовая часть), но фото
      // локально не загрузилось (status failed). В sync() такая запись не
      // попадает в push-фазу (не новее серверной) — за неё отвечает именно
      // авто-ретрай. updatedAt у локальной и серверной равны.
      final base = entry(
        uuid: 'u-autoretry',
        date: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1, 10),
      );
      await backend.pushEntry(base, null);

      final f = await tempFile('autoretry.jpg');
      await db.insertDiaryEntry(base.copyWith(
        photoPath: f.path,
        photoUploadState: 'failed',
      ));

      final outcome = await engine.sync();

      final after = await db.getDiaryEntries();
      final e = after.firstWhere((x) => x.uuid == 'u-autoretry');
      expect(e.photoUploadState, isNull);
      // Ровно одна попытка загрузки фото — внутри авто-ретрая.
      expect(backend.uploadPhotoCalls, 1);
      expect(outcome.changed, isTrue);
    });

    test('LWW-pull с серверным photo_url снимает локальный uploading '
        '(вечный лоадер на устройстве-редакторе)', () async {
      final db = await createDb();
      final backend = FailAwareBackend('u-lww');
      final engine = DiarySyncEngine(
          db: db, backend: backend, knownStore: MemKnownStore());
      await engine.loadKnown();

      // На устройстве A локальная запись ещё загружает фото (uploading),
      // а на сервере (от B) запись уже с photo_url и новее по updated_at.
      final localBase = entry(
        uuid: 'u-lww',
        date: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1, 10),
        photoUploadState: 'uploading',
      );
      final id = await db.insertDiaryEntry(localBase);

      backend.server['u-lww'] = {
        'uuid': 'u-lww',
        'user_id': 'u-lww',
        'species': 'Заяц',
        'location': null,
        'weather': null,
        'notes': null,
        'entry_date': localBase.date.toIso8601String(),
        'latitude': null,
        'longitude': null,
        'photo_url': 'u-lww/zaits.jpg',
        'result': '',
        'weight': null,
        'count': null,
        'method': null,
        // Новее локальной — LWW применится.
        'updated_at': DateTime.utc(2026, 9, 1, 12).toIso8601String(),
      };

      await engine.sync();

      final after = await db.getDiaryEntries();
      final e = after.firstWhere((x) => x.id == id);
      // Фото подтверждено на сервере (photo_url есть) — uploading снят,
      // иначе спиннер крутился бы вечно.
      expect(e.photoUploadState, isNull);
      expect(e.photoUrl, 'u-lww/zaits.jpg');
    });

    test('failed-запись: при повторном провале статус остаётся failed '
        '(авто-ретрай ровно 1 раз)', () async {
      final db = await createDb();
      final backend = FailAwareBackend('u-sync2');
      final engine = DiarySyncEngine(
          db: db, backend: backend, knownStore: MemKnownStore());
      await engine.loadKnown();

      final base = entry(
        uuid: 'u-autoretry2',
        date: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1, 10),
      );
      await backend.pushEntry(base, null);

      final f = await tempFile('autoretry2.jpg');
      await db.insertDiaryEntry(base.copyWith(
        photoPath: f.path,
        photoUploadState: 'failed',
      ));

      // Бэкенд всё ещё падает.
      backend.failPhotoUpload = true;

      final outcome = await engine.sync();

      final after = await db.getDiaryEntries();
      final e = after.firstWhere((x) => x.uuid == 'u-autoretry2');
      expect(e.photoUploadState, 'failed');
      // Ровно одна попытка — внутри авто-ретрая (push-фаза её не трогала).
      expect(backend.uploadPhotoCalls, 1);
      expect(outcome.changed, isFalse);
    });
  });
}
