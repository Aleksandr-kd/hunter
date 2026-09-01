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

  /// Удаляет фото из storage по имени объекта (если существует).
  Future<void> deletePhoto(String objName);
}

/// Прод-бэкенд поверх Supabase.
class SupabaseDiaryBackend implements DiaryBackend {
  /// Лимит на сетевую операцию, чтобы «повисший» HTTP/обрыв соединения не
  /// блокировал синхронизацию на десятки секунд (симптом «вечно висящей
  /// синхронизации» из-за ClientException с длинным дефолтным таймаутом).
  static const _networkTimeout = Duration(seconds: 20);

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
        .limit(1000)
        .timeout(_networkTimeout);
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
          .eq('user_id', user.id)
          .timeout(_networkTimeout);
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
        .upsert(payload, onConflict: 'user_id,uuid')
        .timeout(_networkTimeout);
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
    }, onConflict: 'user_id,uuid').timeout(_networkTimeout);
  }

  @override
  Future<String> uploadPhoto(String objName, File file) async {
    await SupabaseService.client!
        .storage
        .from('diary-photos')
        .upload(objName, file, fileOptions: const FileOptions(upsert: true))
        .timeout(_networkTimeout);
    return objName;
  }

  @override
  Future<Uint8List> downloadPhoto(String objName) async {
    return SupabaseService.client!
        .storage
        .from('diary-photos')
        .download(objName)
        .timeout(_networkTimeout);
  }

  @override
  Future<void> deletePhoto(String objName) async {
    await SupabaseService.client!
        .storage
        .from('diary-photos')
        .remove([objName])
        .timeout(_networkTimeout);
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

  /// Переопределение каталога документов для тестов (иначе path_provider
  /// бросает MissingPluginException в flutter_test).
  @visibleForTesting
  Future<Directory> Function()? documentsDirOverride;

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
      photoUploadState: e.photoUploadState,
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
            photoPath: r['photo_url'] == null ? null : localEntry.photoPath,
            photoUrl: r['photo_url'] as String?,
            // Статус загрузки фото — локальный факт устройства; серверное
            // обновление текста/URL не меняет его. ИСКЛЮЧЕНИЕ: если на
            // сервере уже есть непустой photo_url — фото подтверждено на сервере
            // (это наше же загруженное фото либо фото с другого устройства),
            // поэтому локальный 'uploading' снимаем. Иначе «вечный лоадер» на
            // устройстве-редакторе: A грузит фото, реальный time пулл LWW
            // видит серверный photo_url и сохраняет 'uploading' (фото доставлено
            // отдельно через _syncPhoto), спиннер крутится бесконечно.
            photoUploadState:
                (r['photo_url'] as String?)?.isNotEmpty == true
                    ? null
                    : (r['photo_url'] == null ? null : localEntry.photoUploadState),
            notes: r['notes'] as String? ?? localEntry.notes,
            result: r['result'] as String? ?? localEntry.result,
            weight: (r['weight'] as num?)?.toDouble() ?? localEntry.weight,
            count: (r['count'] as num?)?.toInt() ?? localEntry.count,
            method: r['method'] as String? ?? localEntry.method,
          ));
          changed = true;
          debugPrint('SYNC: updated local $ru from remote (LWW)');
          // Если на сервере фото удалено (photo_url=null), а локально файл ещё
          // есть — убираем его с диска, чтобы не оставался осиротевший файл.
          if (r['photo_url'] == null && localEntry.photoPath != null) {
            try {
              final f = File(localEntry.photoPath!);
              if (f.existsSync()) await f.delete();
            } catch (_) {}
          }
        }
        // Фото: скачиваем с сервера, если на сервере есть и локального файла ещё нет.
        final rPhoto = r['photo_url'] as String?;
        if (rPhoto != null && rPhoto.isNotEmpty) {
          if (await _syncPhoto(ru, rPhoto, remoteUpdated)) changed = true;
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
          photoUploadState: e.photoUploadState,
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
                // Фото-URL прожатывается в bulk: локальное удаление фото
                // (photoUrl == null) доходит до сервера и реплицируется на
                // другие устройства. Без этого онлайн-removePhoto чистил объект
                // в storage, но на сервере оставался stale photo_url -> 404.
                'photo_url': e.photoUrl,
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
            final updated = await _pushWithPhoto(e);
            // Даже если фото не загрузилось, текстовая часть на сервере —
            // обновляем updatedAt, чтобы не зациклить повторные аплоады.
            if (updated != null && e.id != null) {
              // БАГ #3 исправлен: пишем актуальный photoUrl из возвращённой записи.
              await db.updateDiaryEntry(DiaryEntry(
                id: e.id,
                uuid: updated.uuid,
                updatedAt: DateTime.now(),
                date: updated.date,
                location: updated.location,
                weather: updated.weather,
                species: updated.species,
                latitude: updated.latitude,
                longitude: updated.longitude,
                photoPath: updated.photoPath,
                photoUrl: updated.photoUrl,
                // Сохраняем статус загрузки фото (uploading/failed/null),
                // чтобы после sync не терять состояние (иначе failed
                // мгновенно стирался бы и кнопка «Повторить» не появлялась).
                photoUploadState: updated.photoUploadState,
                notes: updated.notes,
                result: updated.result,
                weight: updated.weight,
                count: updated.count,
                method: updated.method,
              ));
            }
          }
        }
      }

      // Авто-ретрай фото (1 раз за цикл): для записей, у которых фото не
      // загрузилось (failed), пробуем повторно. Если снова не вышло — оставляем
      // failed, и пользователь видит кнопку «Повторить» для ручного ретрая.
      final afterPush = await db.getDiaryEntries();
      final failedWithPhoto = afterPush.where((e) =>
          e.photoUploadState == 'failed' &&
          e.photoPath != null &&
          File(e.photoPath!).existsSync());
      for (final e in failedWithPhoto) {
        final updated = await _pushWithPhoto(e);
        if (updated != null && updated.photoUploadState != 'failed') {
          // Перепроверяем актуальное состояние записи: пока шёл upload,
          // пользователь мог удалить фото или сбросить статус — не
          // перетираем свежее состояние (иначе удалённое фото вернётся).
          final rows = await db.getDiaryEntries();
          DiaryEntry? current;
          for (final r in rows) {
            if (r.id == e.id) {
              current = r;
              break;
            }
          }
          if (current == null ||
              current.photoUploadState != 'failed' ||
              current.photoPath == null ||
              !File(current.photoPath!).existsSync()) {
            debugPrint(
                'SYNC: skip auto-retry write for ${e.uuid} (state changed)');
            continue;
          }
          await db.updateDiaryEntry(DiaryEntry(
            id: e.id,
            uuid: updated.uuid,
            updatedAt: DateTime.now(),
            date: updated.date,
            location: updated.location,
            weather: updated.weather,
            species: updated.species,
            latitude: updated.latitude,
            longitude: updated.longitude,
            photoPath: updated.photoPath,
            photoUrl: updated.photoUrl,
            photoUploadState: updated.photoUploadState,
            notes: updated.notes,
            result: updated.result,
            weight: updated.weight,
            count: updated.count,
            method: updated.method,
          ));
          changed = true;
          debugPrint('SYNC: auto-retry photo succeeded for ${e.uuid}');
        }
      }

      // Обработка tombstone «фото удалено»: записи, у которых пользователь
      // удалил фото офлайн (photoUploadState=='removed'), — дожимаем удаление на
      // сервере (storage + photo_url=null) и снимаем флаг.
      final removedWithPhoto = await db.getDiaryEntries();
      final removedEntries = removedWithPhoto
          .where((e) => e.photoUploadState == 'removed')
          .toList();
      for (final e in removedEntries) {
        final updated = await _pushWithPhoto(e);
        if (updated != null && e.id != null) {
          await db.updateDiaryEntry(DiaryEntry(
            id: e.id,
            uuid: updated.uuid,
            updatedAt: DateTime.now(),
            date: updated.date,
            location: updated.location,
            weather: updated.weather,
            species: updated.species,
            latitude: updated.latitude,
            longitude: updated.longitude,
            photoPath: null,
            photoUrl: updated.photoUrl,
            photoUploadState: updated.photoUploadState,
            notes: updated.notes,
            result: updated.result,
            weight: updated.weight,
            count: updated.count,
            method: updated.method,
          ));
          changed = true;
          debugPrint('SYNC: photo removed tombstone finalized for ${e.uuid}');
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
  Future<bool> pushEntry(DiaryEntry entry) async =>
      await _pushWithPhoto(entry) != null;

  /// Как [pushEntry], но возвращает запись с обновлённым photoUrl (БАГ #3),
  /// чтобы вызывающий записал актуальный URL в локальную БД. Возвращает null,
  /// если текстовая часть не ушла на сервер.
  Future<DiaryEntry?> pushEntryWithPhoto(DiaryEntry entry) =>
      _pushWithPhoto(entry);

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

  /// Заливает запись на сервер (текст + опциональное фото) и возвращает
  /// запись с актуальным photoUrl (БАГ #3). Возвращает null, если текстовая
  /// часть не ушла на сервер — вызывающий тогда НЕ пишет фотоUrl в БД.
  Future<DiaryEntry?> _pushWithPhoto(DiaryEntry entry) async {
    final user = backend.userId;
    if (user == null) return null;
    // БАГ #4: если локального файла нет (нет пути или он не существует),
    // сохраняем уже известный серверный URL как есть, чтобы не затереть
    // фото на сервере upsert-ом с photo_url=null (фото не удаляли).
    String? photoUrl = entry.photoUrl;
    // Статус загрузки: по умолчанию — прежний. Обновим ниже по результату.
    String? uploadState = entry.photoUploadState;
    final path = entry.photoPath;
    if (uploadState == 'removed') {
      // Пользователь удалил фото локально (возможно офлайн). Дожимаем
      // удаление: чистим объект в storage (по сохранённому objName в photoUrl)
      // и пишем на сервер photo_url=null, затем снимаем tombstone-флаг.
      final objToDelete = photoUrl;
      photoUrl = null;
      uploadState = null;
      if (objToDelete != null && objToDelete.isNotEmpty) {
        try {
          await backend.deletePhoto(objToDelete);
        } catch (e) {
          debugPrint('Diary remove photo storage during sync: $e');
        }
      }
    } else if (path != null && File(path).existsSync()) {
      uploadState = 'uploading';
      try {
        final file = File(path);
        final ext = path.split('.').lastOrNull?.toLowerCase() ?? 'jpg';
        // БАГ #7: включаем версию (мс от updated_at) в имя объекта. UUID
        // фиксирован, поэтому БЕЗ версии URL фото никогда не меняется при
        // перезаписи — другие устройства не могут обнаружить смену фото.
        final version = (entry.updatedAt ?? DateTime.now()).millisecondsSinceEpoch;
        final objName = '$user/${entry.uuid ?? DateTime.now().millisecondsSinceEpoch}_$version.$ext';
        photoUrl = await backend.uploadPhoto(objName, file);
        // Успех — тихо (статус стирается).
        uploadState = null;
      } catch (e) {
        debugPrint('Diary photo upload error (entry kept without photo): $e');
        // Ошибка загрузки фото — помечаем failed, чтобы UI показал кнопку
        // «Повторить» (и движок сделал 1 авто-ретрай).
        uploadState = 'failed';
      }
    } else if (photoUrl == null && path != null) {
      // Файла нет, а URL тоже нет — фото удалили/нет; статус не нужен.
      uploadState = null;
    }
    try {
      // Обновляем entry.photoUrl новым URL из storage — это исправление БАГ #1.
      // Возвращаем обновлённую запись наружу, чтобы вызывающий записал
      // актуальный URL в локальную БД (БАГ #3) — а не прежний null/старый URL.
      final updatedEntry =
          entry.copyWith(photoUrl: photoUrl, photoUploadState: uploadState);
      await backend.pushEntry(updatedEntry, photoUrl);
      return updatedEntry;
    } catch (e) {
      debugPrint('Diary insert remote error: $e');
      return null;
    }
  }

  Future<bool> _syncPhoto(
      String uuid, String photoUrl, DateTime? remoteUpdated) async {
    final all = await db.getDiaryEntries();
    DiaryEntry? e;
    for (final x in all) {
      if (x.uuid == uuid) {
        e = x;
        break;
      }
    }
    if (e == null) return false;
    // Tombstone: пользователь удалил фото локально (возможно офлайн) и удаление
    // ещё не продавлено на сервер. НЕ качаем фото обратно, иначе удалённая
    // фотография «вернётся» после восстановления сети.
    if (e.photoUploadState == 'removed') return false;
    try {
      final dir = await _photosBaseDir();
      final photosDir = Directory('${dir.path}/diary_photos');
      await photosDir.create(recursive: true);
      final ext = photoUrl.split('.').lastOrNull?.toLowerCase() ?? 'jpg';
      // Версия содержимого берётся ИЗ URL (имени объекта), а не из серверного
      // updated_at. Имя объекта вида `$user/$uuid_<versionMs>.$ext` (БАГ #7),
      // поэтому по одному UUID+URL путь стабилен: текст-правка bump-ает только
      // updated_at, а URL не меняется -> локальный путь не меняется -> лишнего
      // скачивания (или 404, если старый объект уже зачищен) не происходит.
      // Смена фото меняет URL -> меняется и путь -> фото перекачивается.
      final version = _parseVersionFromUrl(photoUrl);
      final localPath = version != null
          ? '${photosDir.path}/$uuid.$version.$ext'
          : '${photosDir.path}/$uuid.$ext';
      // Гейт: файл уже лежит под путём, вычисленным из ТЕКУЩЕГО URL, — качать
      // нечего. (Старый гейт по равенству URL всегда срабатывал после LWW-копии
      // photoUrl и не давал скачать СМЕНЁННОЕ фото на другом устройстве,
      // а старая версия пути от remoteUpdated дёргала скачивание на любую
      // текст-правку.)
      if (e.photoPath == localPath && File(e.photoPath!).existsSync()) {
        return false;
      }
      final bytes = await backend.downloadPhoto(photoUrl);
      await File(localPath).writeAsBytes(bytes, flush: true);
      final oldPath = e.photoPath;
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
        // Фото скачано с сервера — статус успеха (тихо).
        photoUploadState: null,
        notes: e.notes,
        result: e.result,
        weight: e.weight,
        count: e.count,
        method: e.method,
      ));
      // Старый локальный файл (другой версии) больше не нужен — чистим, чтобы
      // не копить мусор при каждой смене фото.
      if (oldPath != null &&
          oldPath != localPath &&
          oldPath.startsWith('${photosDir.path}/')) {
        try {
          final old = File(oldPath);
          if (old.existsSync()) await old.delete();
        } catch (_) {}
      }
      debugPrint('SYNC: photo downloaded for $uuid -> $localPath');
      return true;
    } catch (err) {
      debugPrint('Diary photo download error: $err');
      // Self-heal: URL ведёт на НЕсуществующий объект storage (фото удалили на
      // другом устройстве без обновления photo_url, либо объект зачищен вруч-
      // ную). Чистим локальную ссылку и bump-аем updated_at, чтобы тот же цикл
      // синка продавил photo_url=null на сервер и 404 перестали сыпаться на
      // всех устройствах. Сетевые/прочие ошибки НЕ трогаем.
      if (_isStorageObjectMissing(err)) {
        final healed = await _selfHealMissingPhoto(e);
        return healed;
      }
      return false;
    }
  }

  /// Сбрасывает локальную ссылку на «битое» фото и bump-ает updated_at, чтобы
  /// ближайший push (в этом же цикле через toPush) продавил photo_url=null.
  Future<bool> _selfHealMissingPhoto(DiaryEntry e) async {
    if (e.id == null) return false;
    try {
      final healed = DiaryEntry(
        id: e.id,
        uuid: e.uuid,
        updatedAt: DateTime.now(),
        date: e.date,
        location: e.location,
        weather: e.weather,
        species: e.species,
        latitude: e.latitude,
        longitude: e.longitude,
        photoPath: null,
        photoUrl: null,
        photoUploadState: null,
        notes: e.notes,
        result: e.result,
        weight: e.weight,
        count: e.count,
        method: e.method,
      );
      await db.updateDiaryEntry(healed);
      debugPrint('SYNC: self-heal missing photo for ${e.uuid} (photo_url cleared)');
      // Сразу прожатываем photo_url=null на сервер, НЕ полагаясь на LWW-фильтр
      // toPush: если серверный триггер перезаписывает updated_at на now()
      // (миграция 0007), локальный enabled_at проигрывает LWW, null не доходит,
      // и при следующем пулле сервер снова отдаёт битый photo_url -> бесконечный
      // цикл 404/self-heal. Прямой upsert с photo_url=null сохраняется независимо
      // от триггера.
      try {
        await backend.pushEntry(healed, null);
      } catch (err) {
        debugPrint('Diary self-heal push error: $err');
      }
      return true;
    } catch (err) {
      debugPrint('Diary self-heal photo error: $err');
      return false;
    }
  }

  /// Ошибка означает «объект в storage точно отсутствует» (404 NoSuchKey):
  /// только тогда чиним ссылку. Transient-сбои сети НЕ попадают в этот класс,
  /// иначе офлайн-синк мог бы стереть фото.
  static bool _isStorageObjectMissing(Object error) {
    final s = error.toString();
    return s.contains('404') &&
        (s.contains('NoSuchKey') || s.contains('not_found') || s.contains('Object not found'));
  }

  /// Извлекает версию содержимого из имени объекта storage (БАГ #7):
  /// `user/$uuid_<versionMs>.<ext>`. Для старых объектов без версии — null.
  static int? _parseVersionFromUrl(String photoUrl) {
    try {
      final lastSeg = photoUrl.split('/').last;
      final base = lastSeg.split('.').first;
      final token = base.split('_').last;
      return int.tryParse(token);
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _photosBaseDir() async {
    final override = documentsDirOverride;
    if (override != null) return override();
    return getApplicationDocumentsDirectory();
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
      // Запись с сервера — фото на сервере есть, статус успеха (тихо).
      photoUploadState: null,
      notes: r['notes'] as String?,
      result: r['result'] as String? ?? '',
      weight: (r['weight'] as num?)?.toDouble(),
      count: (r['count'] as num?)?.toInt(),
      method: r['method'] as String?,
    );
  }

  Future<void> _uploadEntry(DiaryEntry entry) async {
    final updated = await _pushWithPhoto(entry);
    if (updated != null && entry.id != null) {
      // БАГ #3 исправлен: используем ВОЗВРАЩЁННЫЙ updated.photoUrl (новый URL
      // из storage), а не прежний entry.photoUrl (null/старый).
      await db.updateDiaryEntry(DiaryEntry(
        id: entry.id,
        uuid: updated.uuid,
        updatedAt: DateTime.now(),
        date: updated.date,
        location: updated.location,
        weather: updated.weather,
        species: updated.species,
        latitude: updated.latitude,
        longitude: updated.longitude,
        photoPath: updated.photoPath,
        photoUrl: updated.photoUrl,
        photoUploadState: updated.photoUploadState,
        notes: updated.notes,
        result: updated.result,
        weight: updated.weight,
        count: updated.count,
        method: updated.method,
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
