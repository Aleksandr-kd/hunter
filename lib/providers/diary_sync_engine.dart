import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../models/diary_entry.dart';
import '../services/supabase_service.dart';

const _uuidEngine = Uuid();
const _knownKeyEngine = 'diary_known_uuids';

/// Абстракция доступа к бэкенду для синхронизации дневника.
///
/// Прод-реализация (SupabaseDiaryBackend) оборачивает SupabaseService.client.
/// В тестах подставляется фейк — этим достигается тестируемость синхронизации
/// без реальной сети.
abstract class DiaryBackend {
  bool get ready;
  String? get userId;

  /// Тянет все записи пользователя (уже отсортированные по entry_date).
  Future<List<Map<String, dynamic>>> pull();

  /// Удаляет запись по uuid. Возвращает true при успехе.
  Future<bool> deleteEntry(String uuid);

  /// Массовый upsert текстовых записей (без фото).
  Future<void> bulkUpsert(List<Map<String, dynamic>> payload);

  /// Одиночный upsert записи вместе с photo_url (создание/обновление с фото).
  Future<void> pushEntry(DiaryEntry entry, String? photoUrl);

  /// Загружает фото и возвращает имя объекта (objName). Кидает при ошибке.
  Future<String> uploadPhoto(String objName, File file);

  /// Скачивает фото по имени объекта. Кидает при ошибке.
  Future<Uint8List> downloadPhoto(String objName);
}

/// Прод-бэкенд поверх Supabase.
class SupabaseDiaryBackend implements DiaryBackend {
  @override
  bool get ready => SupabaseService.isReady;

  @override
  String? get userId => SupabaseService.client?.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> pull() async {
    final user = SupabaseService.client?.auth.currentUser;
    if (user == null) return [];
    final res = await SupabaseService.client!
        .from('diary_entries')
        .select(
            'uuid,species,location,weather,notes,entry_date,latitude,longitude,photo_url,result,weight,count,method,updated_at')
        .eq('user_id', user.id)
        .order('entry_date')
        .limit(1000);
    return (res as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<bool> deleteEntry(String uuid) async {
    final user = SupabaseService.client?.auth.currentUser;
    if (user == null) return false;
    try {
      await SupabaseService.client!
          .from('diary_entries')
          .delete()
          .eq('uuid', uuid)
          .eq('user_id', user.id);
      debugPrint('SYNC: deleted remote $uuid');
      return true;
    } catch (e) {
      debugPrint('Diary delete remote error: $e');
      return false;
    }
  }

  @override
  Future<void> bulkUpsert(List<Map<String, dynamic>> payload) async {
    // onConflict: 'user_id,uuid' — уникальный ключ (миграция 0009).
    // 'id' НЕ передаём: при вставке сервер генерирует gen_random_uuid(),
    // при конфликте обновляются поля, а существующий id сохраняется.
    await SupabaseService.client!
        .from('diary_entries')
        .upsert(payload, onConflict: 'user_id,uuid');
  }

  @override
  Future<void> pushEntry(DiaryEntry entry, String? photoUrl) async {
    final user = SupabaseService.client?.auth.currentUser;
    if (user == null) return;
    await SupabaseService.client!.from('diary_entries').upsert({
      'uuid': entry.uuid,
      'user_id': user.id,
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
      'updated_at': (entry.updatedAt ?? DateTime.now()).toIso8601String(),
    }, onConflict: 'user_id,uuid');
  }

  @override
  Future<String> uploadPhoto(String objName, File file) async {
    await SupabaseService.client!
        .storage
        .from('diary-photos')
        .upload(objName, file, fileOptions: const FileOptions(upsert: true));
    return objName;
  }

  @override
  Future<Uint8List> downloadPhoto(String objName) async {
    return SupabaseService.client!.storage.from('diary-photos').download(objName);
  }
}

/// Абстракция хранения «известных» uuid (кэш удалённых/ранее виденных).
///
/// Прод — SharedPreferences; в тестах можно подставить фейк или использовать
/// SharedPreferences.setMockInitialValues.
abstract class KnownStore {
  Future<Set<String>> load();
  Future<void> save(Set<String> uuids);

  /// Имя ключа (для прозрачности фейков).
  String get name;
}

class SharedPrefsKnownStore implements KnownStore {
  @override
  String get name => _knownKeyEngine;

  @override
  Future<Set<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_knownKeyEngine);
      return list == null ? <String>{} : list.toSet();
    } catch (_) {
      return <String>{};
    }
  }

  @override
  Future<void> save(Set<String> uuids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_knownKeyEngine, uuids.toList());
    } catch (_) {}
  }
}

/// Результат одного цикла синхронизации.
class DiarySyncOutcome {
  final bool changed;
  final String? error;
  const DiarySyncOutcome({required this.changed, this.error});
}

/// Двухсторонняя синхронизация записей дневника (извлечена из DiaryProvider
/// для тестируемости). Описывает весь алгоритм: pull → merge/удаление (LWW)
/// → push/присвоение uuid → обновление кэша known uuid.
class DiarySyncEngine {
  final AppDatabase db;
  final DiaryBackend backend;
  final KnownStore knownStore;

  Set<String> knownRemoteUuids = {};

  DiarySyncEngine({required this.db, required this.backend, KnownStore? knownStore})
      : knownStore = knownStore ?? SharedPrefsKnownStore();

  Future<void> loadKnown() async {
    knownRemoteUuids = await knownStore.load();
  }

  Future<void> saveKnown() async {
    await knownStore.save(knownRemoteUuids);
  }

  /// Очищает кэш известных uuid (при выходе из аккаунта).
  Future<void> resetKnown() async {
    knownRemoteUuids = <String>{};
    await knownStore.save(knownRemoteUuids);
  }

  DiaryEntry _copyWithUuid(DiaryEntry e, String uid) {
    return DiaryEntry(
      id: e.id,
      uuid: uid,
      updatedAt: e.updatedAt,
      date: e.date,
      location: e.location,
      weather: e.weather,
      species: e.species,
      latitude: e.latitude,
      longitude: e.longitude,
      photoPath: e.photoPath,
      photoUrl: e.photoUrl,
      notes: e.notes,
      result: e.result,
      weight: e.weight,
      count: e.count,
      method: e.method,
    );
  }

  /// Основной цикл синхронизации (порядок и семантика идентичны прежней
  /// реализации syncWithServer). Выполняется при готовом бэкенде и залоги-
  /// ненном пользователе — это обязан проверять вызывающий (provider).
  Future<DiarySyncOutcome> sync() async {
    final userId = backend.userId;
    if (userId == null) {
      return const DiarySyncOutcome(changed: false);
    }
    try {
      // 1) Тянем с сервера записи.
      final remote = await backend.pull();
      debugPrint('SYNC: remote=${remote.length}, sample=${remote.isNotEmpty ? remote.first : "none"}');

      var local = await db.getDiaryEntries();
      final localByUuid = {
        for (final e in local)
          if (e.uuid != null) e.uuid!: e,
      };
      final remoteByUuid = <String, Map<String, dynamic>>{
        for (final r in remote)
          if (r['uuid'] != null) r['uuid'] as String: r,
      };
      final remoteUuids = remoteByUuid.keys.toSet();
      debugPrint('SYNC: local=${local.length}, known=${knownRemoteUuids.length}');

      // 2) Подтягиваем серверные изменения (новые записи ИЛИ свежее по updated_at).
      var changed = false;
      for (final ru in remoteUuids) {
        final r = remoteByUuid[ru]!;
        final remoteUpdated = _parseUpdatedAt(r['updated_at']) ?? DateTime.tryParse(r['entry_date'] as String? ?? '');
        final localEntry = localByUuid[ru];
        if (localEntry == null) {
          await db.insertDiaryEntry(_fromRemote(r));
          changed = true;
        } else if (_isRemoteNewer(localEntry, remoteUpdated)) {
          await db.updateDiaryEntry(DiaryEntry(
            id: localEntry.id,
            uuid: ru,
            updatedAt: remoteUpdated,
            date: DateTime.tryParse(r['entry_date'] as String? ?? '') ?? localEntry.date,
            location: r['location'] as String? ?? localEntry.location,
            weather: r['weather'] as String? ?? localEntry.weather,
            species: r['species'] as String? ?? localEntry.species,
            latitude: (r['latitude'] as num?)?.toDouble() ?? localEntry.latitude,
            longitude: (r['longitude'] as num?)?.toDouble() ?? localEntry.longitude,
            photoPath: localEntry.photoPath,
            photoUrl: r['photo_url'] as String? ?? localEntry.photoUrl,
            notes: r['notes'] as String? ?? localEntry.notes,
            result: r['result'] as String? ?? localEntry.result,
            weight: (r['weight'] as num?)?.toDouble() ?? localEntry.weight,
            count: (r['count'] as num?)?.toInt() ?? localEntry.count,
            method: r['method'] as String? ?? localEntry.method,
          ));
          changed = true;
          debugPrint('SYNC: updated local $ru from remote (LWW)');
        }
        // Фото: скачиваем с сервера, если на сервере есть и локального файла ещё нет.
        final rPhoto = r['photo_url'] as String?;
        if (rPhoto != null && rPhoto.isNotEmpty) {
          if (await _syncPhoto(ru, rPhoto)) changed = true;
        }
      }

      // 2b) Удаляем локальные, которые были удалены на другом устройстве.
      final toDeleteLocal = local
          .where((e) => e.uuid != null && knownRemoteUuids.contains(e.uuid) && !remoteUuids.contains(e.uuid))
          .toList();
      for (final e in toDeleteLocal) {
        if (e.id != null) {
          await db.deleteDiaryEntry(e.id!);
          changed = true;
          debugPrint('SYNC: deleted local ${e.uuid} (removed on other device)');
        }
      }
      if (changed) {
        local = await db.getDiaryEntries();
      }
      final localByUuidFinal = {
        for (final e in local)
          if (e.uuid != null) e.uuid!: e,
      };

      // 3) Заливаем локальные изменения на сервер (только те, что свежее серверных).
      final withoutUuid = local.where((e) => e.uuid == null).toList();
      final assignedUuids = <String>[];
      for (final e in withoutUuid) {
        final uid = _uuidEngine.v4();
        assignedUuids.add(uid);
        final withUid = _copyWithUuid(e, uid);
        await db.updateDiaryEntry(DiaryEntry(
          id: e.id,
          uuid: uid,
          updatedAt: DateTime.now(),
          date: e.date,
          location: e.location,
          weather: e.weather,
          species: e.species,
          latitude: e.latitude,
          longitude: e.longitude,
          photoPath: e.photoPath,
          photoUrl: e.photoUrl,
          notes: e.notes,
          result: e.result,
          weight: e.weight,
          count: e.count,
          method: e.method,
        ));
        await _uploadEntry(withUid);
      }

      // a) Новые записи (uuid не на сервере), b) изменённые локально (local update новее remote).
      final toPush = <DiaryEntry>[];
      for (final e in localByUuidFinal.values) {
        final remoteEntry = remoteByUuid[e.uuid];
        if (remoteEntry == null) {
          toPush.add(e);
          continue;
        }
        final remoteUpdated = _parseUpdatedAt(remoteEntry['updated_at']) ??
            DateTime.tryParse(remoteEntry['entry_date'] as String? ?? '');
        if (_isLocalNewer(e, remoteUpdated)) {
          toPush.add(e);
        }
      }
      if (toPush.isNotEmpty) {
        final plain = toPush
            .where((e) => e.photoPath == null || !File(e.photoPath!).existsSync())
            .toList();
        if (plain.isNotEmpty) {
          final payload = plain.map((e) => {
                'uuid': e.uuid,
                'user_id': userId,
                'species': e.species,
                'location': e.location,
                'weather': e.weather,
                'notes': e.notes,
                'entry_date': e.date.toIso8601String(),
                'latitude': e.latitude,
                'longitude': e.longitude,
                'result': e.result,
                'weight': e.weight,
                'count': e.count,
                'method': e.method,
                'updated_at': (e.updatedAt ?? DateTime.now()).toIso8601String(),
              }).toList();
          try {
            await backend.bulkUpsert(payload);
          } catch (e) {
            debugPrint('SYNC: bulk upsert error $e');
          }
        }
        for (final e in toPush) {
          if (e.photoPath != null && File(e.photoPath!).existsSync()) {
            final ok = await _pushWithPhoto(e);
            // Даже если фото не загрузилось, текстовая часть на сервере —
            // обновляем updatedAt, чтобы не зациклить повторные аплоады.
            if (ok && e.id != null) {
              await db.updateDiaryEntry(DiaryEntry(
                id: e.id,
                uuid: e.uuid,
                updatedAt: DateTime.now(),
                date: e.date,
                location: e.location,
                weather: e.weather,
                species: e.species,
                latitude: e.latitude,
                longitude: e.longitude,
                photoPath: e.photoPath,
                photoUrl: e.photoUrl,
                notes: e.notes,
                result: e.result,
                weight: e.weight,
                count: e.count,
                method: e.method,
              ));
            }
          }
        }
      }

      // Обновляем кэш известных uuid (фикс resurrection: добавляем и запушенные
      // в этом цикле, а не только из pull-снапшота).
      final knownUuids = remoteUuids.toSet();
      for (final e in toPush) {
        if (e.uuid != null) knownUuids.add(e.uuid!);
      }
      // withoutUuid-объекты имеют uuid == null, поэтому берём реально
      // присвоенные в цикле uuid (иначе свежезамигрированные записи не попадут
      // в known и «воскреснут» после удаления на другом устройстве).
      knownUuids.addAll(assignedUuids);
      knownRemoteUuids = knownUuids;
      await saveKnown();

      return DiarySyncOutcome(changed: changed);
    } catch (e) {
      debugPrint('Diary sync error: $e');
      return DiarySyncOutcome(changed: false, error: e.toString());
    }
  }

  /// Публичная обёртка одиночного аплоада записи (текст + опциональное фото),
  /// используемая DiaryProvider при add/update. Возвращает true, если текстовая
  /// часть успешно ушла на сервер (фото может не загрузиться — не критично).
  Future<bool> pushEntry(DiaryEntry entry) => _pushWithPhoto(entry);

  /// Удаляет запись на сервере и, при успехе, забывает ее uuid (чтобы она не
  /// «воскресла» с сервера при следующем pull). Возвращает true при успехе.
  Future<bool> deleteRemoteAndForget(String uuid) async {
    final ok = await backend.deleteEntry(uuid);
    if (ok) {
      knownRemoteUuids.remove(uuid);
      await saveKnown();
    }
    return ok;
  }

  Future<bool> _pushWithPhoto(DiaryEntry entry) async {
    final user = backend.userId;
    if (user == null) return false;
    // БАГ #4: если локального файла нет (нет пути или он не существует),
    // сохраняем уже известный серверный URL как есть, чтобы не затереть
    // фото на сервере upsert-ом с photo_url=null (фото не удаляли).
    String? photoUrl = entry.photoUrl;
    final path = entry.photoPath;
    if (path != null && File(path).existsSync()) {
      try {
        final file = File(path);
        final ext = path.split('.').lastOrNull?.toLowerCase() ?? 'jpg';
        final objName = '$user/${entry.uuid ?? DateTime.now().millisecondsSinceEpoch}.$ext';
        photoUrl = await backend.uploadPhoto(objName, file);
      } catch (e) {
        debugPrint('Diary photo upload error (entry kept without photo): $e');
      }
    }
    try {
      await backend.pushEntry(entry, photoUrl);
      return true;
    } catch (e) {
      debugPrint('Diary insert remote error: $e');
      return false;
    }
  }

  Future<bool> _syncPhoto(String uuid, String photoUrl) async {
    final all = await db.getDiaryEntries();
    DiaryEntry? e;
    for (final x in all) {
      if (x.uuid == uuid) {
        e = x;
        break;
      }
    }
    if (e == null) return false;
    if (e.photoUrl == photoUrl &&
        e.photoPath != null &&
        File(e.photoPath!).existsSync()) {
      return false;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${dir.path}/diary_photos');
      await photosDir.create(recursive: true);
      final ext = photoUrl.split('.').lastOrNull?.toLowerCase() ?? 'jpg';
      final localPath = '${photosDir.path}/$uuid.$ext';
      final bytes = await backend.downloadPhoto(photoUrl);
      await File(localPath).writeAsBytes(bytes, flush: true);
      await db.updateDiaryEntry(DiaryEntry(
        id: e.id,
        uuid: e.uuid,
        updatedAt: e.updatedAt,
        date: e.date,
        location: e.location,
        weather: e.weather,
        species: e.species,
        latitude: e.latitude,
        longitude: e.longitude,
        photoPath: localPath,
        photoUrl: photoUrl,
        notes: e.notes,
        result: e.result,
        weight: e.weight,
        count: e.count,
        method: e.method,
      ));
      debugPrint('SYNC: photo downloaded for $uuid -> $localPath');
      return true;
    } catch (e) {
      debugPrint('Diary photo download error: $e');
      return false;
    }
  }

  DiaryEntry _fromRemote(Map<String, dynamic> r) {
    return DiaryEntry(
      uuid: r['uuid'] as String?,
      updatedAt: _parseUpdatedAt(r['updated_at']),
      date: DateTime.tryParse(r['entry_date'] as String? ?? '') ?? DateTime.now(),
      location: r['location'] as String?,
      weather: r['weather'] as String?,
      species: r['species'] as String? ?? '',
      latitude: (r['latitude'] as num?)?.toDouble(),
      longitude: (r['longitude'] as num?)?.toDouble(),
      // photoPath не присваиваем серверный URL: фото качается отдельно через
      // _syncPhoto (иначе File(photoPath).existsSync() с URL был бы false и
      // запись в UI выглядела «без фото» / неверно считалась в статистике).
      photoPath: null,
      photoUrl: r['photo_url'] as String?,
      notes: r['notes'] as String?,
      result: r['result'] as String? ?? '',
      weight: (r['weight'] as num?)?.toDouble(),
      count: (r['count'] as num?)?.toInt(),
      method: r['method'] as String?,
    );
  }

  Future<void> _uploadEntry(DiaryEntry entry) async {
    final ok = await _pushWithPhoto(entry);
    if (ok && entry.id != null) {
      final user = backend.userId;
      String? resolvedPhotoUrl = entry.photoUrl;
      if (entry.photoPath != null &&
          File(entry.photoPath!).existsSync() &&
          user != null) {
        final ext = entry.photoPath!.split('.').lastOrNull?.toLowerCase() ?? 'jpg';
        resolvedPhotoUrl =
            '$user/${entry.uuid ?? DateTime.now().millisecondsSinceEpoch}.$ext';
      }
      await db.updateDiaryEntry(DiaryEntry(
        id: entry.id,
        uuid: entry.uuid,
        updatedAt: DateTime.now(),
        date: entry.date,
        location: entry.location,
        weather: entry.weather,
        species: entry.species,
        latitude: entry.latitude,
        longitude: entry.longitude,
        photoPath: entry.photoPath,
        photoUrl: resolvedPhotoUrl,
        notes: entry.notes,
        result: entry.result,
        weight: entry.weight,
        count: entry.count,
        method: entry.method,
      ));
    }
  }

  static DateTime? _parseUpdatedAt(Object? v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static bool _isRemoteNewer(DiaryEntry local, DateTime? remoteUpdated) {
    if (remoteUpdated == null) return false;
    return remoteUpdated.isAfter(local.updatedAt ?? local.date);
  }

  static bool _isLocalNewer(DiaryEntry e, DateTime? remoteUpdated) {
    final l = e.updatedAt ?? e.date;
    if (remoteUpdated == null) return true;
    return l.isAfter(remoteUpdated);
  }
}
