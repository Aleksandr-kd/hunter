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

const _uuid = Uuid();
const _knownKey = 'diary_known_uuids';

/// Управляет записями дневника (офлайн/локально + синхронизация с Supabase).
class DiaryProvider extends ChangeNotifier {
  final AppDatabase _db = AppDatabase();
  List<DiaryEntry> _entries = [];
  bool _loaded = false;
  bool _syncing = false;
  bool _syncRunning = false;
  bool _needResync = false;
  RealtimeChannel? _realtimeSub;

  // Последовательная очередь фоновых аплоадов. Все addEntry/updateEntry/
  // restoreFromBackup ставят загрузку в цепочку, а deleteEntry дожидается
  // её завершения — это исключает «воскрешение» удалённой записи на сервере
  // и конфликты параллельных upsert.
  Future<void> _uploadQueue = Future.value();
  String? _lastUploadError;
  String? get lastUploadError => _lastUploadError;

  void _enqueueUpload(Future<void> Function() task) {
    _uploadQueue = _uploadQueue.then((_) => task()).catchError((e) {
      _lastUploadError = e.toString();
      _lastError = _lastUploadError;
      notifyListeners();
    });
  }

  List<DiaryEntry> get entries => List.unmodifiable(_entries);
  bool get loaded => _loaded;
  bool get syncing => _syncing;
  DateTime? _lastSync;
  String? _lastError;
  bool _hasRemoteChange = false;
  bool get hasRemoteChange => _hasRemoteChange;
  DateTime? get lastSync => _lastSync;
  String? get lastError => _lastError;

  Set<String> _knownRemoteUuids = {};
  // Инициализация known-кэша: syncWithServer обязан дождаться её, иначе
  // тоDeleteLocal не увидит ранее известных uuid (гонка при старте).
  late Future<void> _knownLoaded;

  DiaryProvider() {
    load();
    _knownLoaded = _loadKnown();
    _setupRealtime();
    // Одна синхронизация при старте — чтобы показать lastSync.
    unawaited(syncWithServer());
  }

  Future<void> _loadKnown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_knownKey);
      if (list != null) _knownRemoteUuids = list.toSet();
    } catch (_) {}
  }

  Future<void> _saveKnown(Set<String> uuids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_knownKey, uuids.toList());
      _knownRemoteUuids = uuids;
    } catch (_) {}
  }

  void consumeRemoteChange() {
    _hasRemoteChange = false;
    notifyListeners();
  }

  /// Очищает локальный кэш дневника и known-кэш uuid.
  /// Вызывается при выходе из аккаунта, чтобы записи одного пользователя
  /// не попали в другой аккаунт при следующем входе на этом устройстве
  /// (утечка данных между профилями).
  Future<void> clearLocal() async {
    await _uploadQueue;
    await _db.deleteAllDiaryEntries();
    _knownRemoteUuids.clear();
    await _saveKnown({});
    _hasRemoteChange = false;
    await load();
  }

  @override
  void dispose() {
    unawaited(_disposeRealtime());
    super.dispose();
  }

  Future<void> load() async {
    _entries = await _db.getDiaryEntries();
    _loaded = true;
    notifyListeners();
  }

  Future<bool> addEntry(DiaryEntry entry) async {
    final uid = entry.uuid ?? _uuid.v4();
    final withUuid = _copyWithUuid(entry, uid);
    final id = await _db.insertDiaryEntry(withUuid);
    // Выгрузка на сервер в фоне — не блокирует закрытие экрана.
    _enqueueUpload(() => _uploadEntry(withUuid));
    await load();
    return id > 0;
  }

  Future<void> deleteEntry(int id) async {
    // Ждём завершения фоновых аплоадов: если запись только что добавлена,
    // незавершённый upload мог бы выполниться после _deleteRemote и «вернуть»
    // её на сервер. Дождавшись очереди, удаляем согласованно.
    await _uploadQueue;
    // Находим uuid до локального удаления для синхронизации.
    String? uuid;
    try {
      final found = _entries.where((e) => e.id == id).toList();
      if (found.isNotEmpty) uuid = found.first.uuid;
      if (uuid == null) {
        final all = await _db.getDiaryEntries();
        final m = all.where((e) => e.id == id).toList();
        if (m.isNotEmpty) uuid = m.first.uuid;
      }
    } catch (_) {}
    await _db.deleteDiaryEntry(id);
    await load();
    if (uuid != null && uuid.isNotEmpty) {
      // Удаляем на сервере; _knownRemoteUuids очищаем ТОЛЬКО после успешного
      // удаления — иначе при следующем pull запись «воскреснет» с сервера.
      final ok = await _deleteRemote(uuid);
      if (ok) {
        _knownRemoteUuids.remove(uuid);
        unawaited(_saveKnown(_knownRemoteUuids));
      }
    }
  }

  /// Удаляет запись на сервере. Возвращает true при успехе.
  Future<bool> _deleteRemote(String uuid) async {
    if (!SupabaseService.isReady) return false;
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

  /// Обновляет существующую запись локально и выгружает на сервер.
  Future<void> updateEntry(DiaryEntry entry) async {
    if (entry.id == null) {
      debugPrint('updateEntry: пропущено, id == null (запись без id не редактируется)');
      return;
    }
    await _db.updateDiaryEntry(entry);
    await load();
    if (entry.uuid != null) {
      _enqueueUpload(() => _uploadEntry(entry));
    }
  }

  /// Восстанавливает записи из резервной копии.
  /// Пропускает записи с uuid, которые уже есть локально.
  /// Возвращает количество восстановленных записей.
  Future<int> restoreFromBackup(List<DiaryEntry> entries) async {
    final local = await _db.getDiaryEntries();
    final localUuids = local.map((e) => e.uuid).whereType<String>().toSet();
    var added = 0;
    for (final e in entries) {
      if (e.uuid != null && localUuids.contains(e.uuid)) continue;
      final withUuid = e.uuid == null ? _copyWithUuid(e, _uuid.v4()) : e;
      await _db.insertDiaryEntry(withUuid);
      _enqueueUpload(() => _uploadEntry(withUuid));
      added++;
    }
    await load();
    return added;
  }

  /// Двухсторонняя синхронизация: серверные записи в локальные и наоборот.
  /// Обрабатывает добавления, изменения и удаления — данные идентичны на
  /// всех устройствах одного пользователя.
  Future<void> syncWithServer() async {
    debugPrint('SYNC: start, ready=${SupabaseService.isReady}');
    if (!SupabaseService.isReady) return;
    final user = SupabaseService.client?.auth.currentUser;
    debugPrint('SYNC: user=${user?.email}, id=${user?.id}');
    if (user == null) return;

    // Защита от параллельного запуска: если синк уже идёт — запоминаем
    // запрос и перезапускаем после завершения. Это исключает дубли записей,
    // когда несколько триггеров (старт, вход, кнопка, realtime) вызывают синк
    // одновременно.
    await _knownLoaded; // дожидаемся загрузки known-кэша (см. конструктор).
    if (_syncRunning) {
      _needResync = true;
      return;
    }
    _syncRunning = true;

    _syncing = true;
    notifyListeners();
    try {
      // 1) Тянем с сервера записи.
      final res = await SupabaseService.client!
          .from('diary_entries')
          .select('uuid,species,location,weather,notes,entry_date,latitude,longitude,photo_url,result,weight,count,method,updated_at')
          .eq('user_id', user.id)
          .order('entry_date')
          .limit(1000);
      final remote = (res as List).cast<Map<String, dynamic>>();
      debugPrint('SYNC: remote=${remote.length}, sample=${remote.isNotEmpty ? remote.first : "none"}');

      var local = await _db.getDiaryEntries();
      final localByUuid = {
        for (final e in local)
          if (e.uuid != null) e.uuid!: e,
      };
      final remoteByUuid = <String, Map<String, dynamic>>{
        for (final r in remote)
          if (r['uuid'] != null) r['uuid'] as String: r,
      };
      final remoteUuids = remoteByUuid.keys.toSet();
      debugPrint('SYNC: local=${local.length}, known=${_knownRemoteUuids.length}');

      // 2) Подтягиваем серверные изменения (новые записи ИЛИ свежее по updated_at).
      var changed = false;
      for (final ru in remoteUuids) {
        final r = remoteByUuid[ru]!;
        final remoteUpdated = _parseUpdatedAt(r['updated_at']) ?? DateTime.tryParse(r['entry_date'] as String? ?? '');
        final localEntry = localByUuid[ru];
        if (localEntry == null) {
          // Нет локально — вставляем.
          await _db.insertDiaryEntry(_fromRemote(r));
          changed = true;
        } else if (_isRemoteNewer(localEntry, remoteUpdated)) {
          // Серверная версия свежее — обновляем локальную (LWW pull).
          await _db.updateDiaryEntry(DiaryEntry(
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
      // Если uuid был известен ранее (был на сервере), а сейчас его нет — значит удалён.
      final toDeleteLocal = local
          .where((e) => e.uuid != null && _knownRemoteUuids.contains(e.uuid) && !remoteUuids.contains(e.uuid))
          .toList();
      for (final e in toDeleteLocal) {
        if (e.id != null) {
          await _db.deleteDiaryEntry(e.id!);
          changed = true;
          debugPrint('SYNC: deleted local ${e.uuid} (removed on other device)');
        }
      }
      if (changed) {
        // Перечитываем после вставок/обновлений/удалений.
        local = await _db.getDiaryEntries();
      }
      final localByUuidFinal = {
        for (final e in local)
          if (e.uuid != null) e.uuid!: e,
      };

      // 3) Заливаем локальные изменения на сервер (только те, что свежее серверных).
      // Присвоить uuid тем, у кого его не было (старые записи).
      final withoutUuid = local.where((e) => e.uuid == null).toList();
      for (final e in withoutUuid) {
        final uid = _uuid.v4();
        final withUid = _copyWithUuid(e, uid);
        await _db.updateDiaryEntry(DiaryEntry(
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
          toPush.add(e); // новой записи на сервере нет — создаём.
          continue;
        }
        final remoteUpdated = _parseUpdatedAt(remoteEntry['updated_at']) ??
            DateTime.tryParse(remoteEntry['entry_date'] as String? ?? '');
        if (_isLocalNewer(e, remoteUpdated)) {
          toPush.add(e); // локальная версия свежее — перезаписываем.
        }
      }
      if (toPush.isNotEmpty) {
        final plain = toPush
            .where((e) => e.photoPath == null || !File(e.photoPath!).existsSync())
            .toList();
        if (plain.isNotEmpty) {
          final payload = plain.map((e) => {
                'uuid': e.uuid,
                'user_id': user.id,
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
            // onConflict: 'user_id,uuid' — уникальный ключ (миграция 0009).
            // 'id' НЕ передаём: при вставке сервер генерирует gen_random_uuid(),
            // при конфликте обновляются поля, а существующий id сохраняется.
            await SupabaseService.client!
                .from('diary_entries')
                .upsert(payload, onConflict: 'user_id,uuid');
          } catch (e) {
            debugPrint('SYNC: bulk upsert error $e');
          }
        }
        for (final e in toPush) {
          if (e.photoPath != null && File(e.photoPath!).existsSync()) {
            final ok = await _insertRemote(e);
            // Даже если фото не загрузилось, текстовая часть на сервере —
            // обновляем updatedAt, чтобы не зациклить повторные аплоады.
            if (ok && e.id != null) {
              await _db.updateDiaryEntry(DiaryEntry(
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

      // Обновляем кэш известных uuid.
      await _saveKnown(remoteUuids);
      _lastSync = DateTime.now();
      _lastError = null;

      if (changed) await load();
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Diary sync error: $e');
    } finally {
      _syncing = false;
      _syncRunning = false;
      notifyListeners();
      // Повторяем, если во время синка поступил ещё один запрос.
      if (_needResync) {
        _needResync = false;
        unawaited(syncWithServer());
      }
    }
  }

  Future<void> _disposeRealtime() async {
    final old = _realtimeSub;
    _realtimeSub = null;
    if (old != null) {
      try {
        await old.unsubscribe();
      } catch (e) {
        debugPrint('Realtime unsubscribe error: $e');
      }
    }
  }

  /// Подписка на изменения на сервере.
  /// Realtime только сигнализирует об изменениях — фактическая синхронизация
  /// происходит по требованию (баннер + кнопка пользователя).
  void _setupRealtime() {
    SupabaseService.client?.auth.onAuthStateChange.listen((data) async {
      // Ждём полного отключения старого канала до подписки нового — иначе
      // на короткое время может быть два активных канала одного пользователя.
      await _disposeRealtime();
      if (data.session != null) {
        listenRealtime();
        // При входе — синхронизация.
        unawaited(syncWithServer());
      } else if (data.event == AuthChangeEvent.signedOut) {
        // При выходе из аккаунта — очищаем локальный кэш, чтобы чужой
        // пользователь не увидел / не получил записи предыдущего владельца.
        await clearLocal();
      }
    });
    if (SupabaseService.client?.auth.currentUser != null) {
      listenRealtime();
    }
  }

  void listenRealtime() {
    final client = SupabaseService.client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    _realtimeSub = client
        .channel('public:diary_entries')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'diary_entries',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: user.id),
          callback: (_) => _onRemoteChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'diary_entries',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: user.id),
          callback: (_) => _onRemoteChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'diary_entries',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: user.id),
          callback: (_) => _onRemoteChange(),
        )
        .subscribe();
  }

  /// Сигнал о том, что на сервере появились изменения (с другого устройства).
  /// Фактическая синхронизация — по нажатию пользователя на баннер.
  void _onRemoteChange() {
    _hasRemoteChange = true;
    notifyListeners();
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
      notes: e.notes,
      result: e.result,
      weight: e.weight,
      count: e.count,
      method: e.method,
    );
  }

  /// Возвращает true, если текстовая часть записи успешно апsert-нута на сервере.
  /// Фото может не загрузиться — это не считается ошибкой для всей записи.
  Future<bool> _insertRemote(DiaryEntry entry) async {
    final auth = SupabaseService.client?.auth;
    final user = auth?.currentUser;
    if (user == null) return false;
    String? photoUrl;
    final path = entry.photoPath;
    if (path != null && File(path).existsSync()) {
      try {
        final file = File(path);
        final ext = path.split('.').lastOrNull?.toLowerCase() ?? 'jpg';
        final objName = '${user.id}/${entry.uuid ?? DateTime.now().millisecondsSinceEpoch}.$ext';
        await SupabaseService.client!.storage.from('diary-photos').upload(objName, file);
        photoUrl = objName;
      } catch (e) {
        debugPrint('Diary photo upload error (entry kept without photo): $e');
      }
    }
    try {
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
      return true;
    } catch (e) {
      debugPrint('Diary insert remote error: $e');
      return false;
    }
  }

  /// Скачивает фото записи с сервера (по photo_url) в локальную папку
  /// и сохраняет путь в БД. Возвращает true, если фото обновлено.
  /// Возвращает false, если скачивать нечего или уже есть локальный файл.
  Future<bool> _syncPhoto(String uuid, String photoUrl) async {
    final all = await _db.getDiaryEntries();
    DiaryEntry? e;
    for (final x in all) {
      if (x.uuid == uuid) {
        e = x;
        break;
      }
    }
    if (e == null) return false;
    // Локальный файл уже есть — не качаем повторно.
    if (e.photoPath != null && File(e.photoPath!).existsSync()) return false;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${dir.path}/diary_photos');
      await photosDir.create(recursive: true);
      final ext = photoUrl.split('.').lastOrNull?.toLowerCase() ?? 'jpg';
      final localPath = '${photosDir.path}/$uuid.$ext';
      final bytes = await SupabaseService.client!.storage
          .from('diary-photos')
          .download(photoUrl);
      await File(localPath).writeAsBytes(bytes, flush: true);
      await _db.updateDiaryEntry(DiaryEntry(
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

  DiaryEntry _fromRemote(Map<String, dynamic> r) {    return DiaryEntry(
      uuid: r['uuid'] as String?,
      updatedAt: _parseUpdatedAt(r['updated_at']),
      date: DateTime.tryParse(r['entry_date'] as String? ?? '') ?? DateTime.now(),
      location: r['location'] as String?,
      weather: r['weather'] as String?,
      species: r['species'] as String? ?? '',
      latitude: (r['latitude'] as num?)?.toDouble(),
      longitude: (r['longitude'] as num?)?.toDouble(),
      notes: r['notes'] as String?,
      result: r['result'] as String? ?? '',
      weight: (r['weight'] as num?)?.toDouble(),
      count: (r['count'] as num?)?.toInt(),
      method: r['method'] as String?,
    );
  }

  static DateTime? _parseUpdatedAt(Object? v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static bool _isRemoteNewer(DiaryEntry local, DateTime? remoteUpdated) {
    // Если remoteUpdated null, fallback на DateTime.min — значит remote
    // «старше» любой локальной записи, и локальная не будет перезаписана.
    if (remoteUpdated == null) return false;
    return remoteUpdated.isAfter(local.updatedAt ?? local.date);
  }

  static bool _isLocalNewer(DiaryEntry e, DateTime? remoteUpdated) {
    final l = e.updatedAt ?? e.date;
    // Если remoteUpdated null — remote «старше» любой локальной.
    if (remoteUpdated == null) return true;
    final r = remoteUpdated;
    return l.isAfter(r);
  }

  Future<void> _uploadEntry(DiaryEntry entry) async {
    final ok = await _insertRemote(entry);
    // Обновляем updatedAt локально после успешного апsertа — предотвращает
    // бесконечный ретрайд если фото не загрузилось.
    if (ok && entry.id != null) {
      await _db.updateDiaryEntry(DiaryEntry(
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
        notes: entry.notes,
        result: entry.result,
        weight: entry.weight,
        count: entry.count,
        method: entry.method,
      ));
    }
  }
}