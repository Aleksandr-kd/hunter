import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  DiaryProvider() {
    load();
    _loadKnown();
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

  @override
  void dispose() {
    _realtimeSub?.unsubscribe();
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
    unawaited(_uploadEntry(withUuid).then((_) {
      _lastSync = DateTime.now();
      notifyListeners();
    }).catchError((_) {}));
    await load();
    return id > 0;
  }

  Future<void> deleteEntry(int id) async {
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
      unawaited(_deleteRemote(uuid).then((_) {
        _lastSync = DateTime.now();
        notifyListeners();
      }).catchError((_) {}));
      _knownRemoteUuids.remove(uuid);
      unawaited(_saveKnown(_knownRemoteUuids));
    }
  }

  Future<void> _deleteRemote(String uuid) async {
    if (!SupabaseService.isReady) return;
    final user = SupabaseService.client?.auth.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.client!
          .from('diary_entries')
          .delete()
          .eq('uuid', uuid)
          .eq('user_id', user.id);
      debugPrint('SYNC: deleted remote $uuid');
    } catch (e) {
      debugPrint('Diary delete remote error: $e');
    }
  }

  /// Обновляет существующую запись локально и выгружает на сервер.
  Future<void> updateEntry(DiaryEntry entry) async {
    if (entry.id == null) return;
    await _db.updateDiaryEntry(entry);
    await load();
    if (entry.uuid != null) {
      unawaited(_uploadEntry(entry).then((_) {
        _lastSync = DateTime.now();
        notifyListeners();
      }).catchError((_) {}));
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
      unawaited(_uploadEntry(withUuid).then((_) {
        _lastSync = DateTime.now();
        notifyListeners();
      }).catchError((_) {}));
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
          .select('uuid,species,location,weather,notes,entry_date,latitude,longitude,photo_url,result,weight,count,method')
          .eq('user_id', user.id)
          .order('entry_date')
          .limit(1000);
      final remote = (res as List).cast<Map<String, dynamic>>();
      debugPrint('SYNC: remote=${remote.length}, sample=${remote.isNotEmpty ? remote.first : "none"}');

      var local = await _db.getDiaryEntries();
      final localUuids = local.map((e) => e.uuid).whereType<String>().toSet();
      final remoteUuids = remote.map((r) => r['uuid'] as String?).whereType<String>().toSet();
      debugPrint('SYNC: local=${local.length}, known=${_knownRemoteUuids.length}');

      // 2) Вставляем серверные, которых нет локально.
      var changed = false;
      for (final r in remote) {
        final ru = r['uuid'] as String?;
        if (ru == null || localUuids.contains(ru)) continue;
        await _db.insertDiaryEntry(DiaryEntry(
          uuid: ru,
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
        ));
        changed = true;
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
        // Перечитываем после вставок/удалений.
        local = await _db.getDiaryEntries();
      }

      // 3) Заливаем локальные изменения на сервер.
      // a) Новые записи (uuid не на сервере и не был известен — ещё не синкались).
      final newEntries = local
          .where((e) => e.uuid != null && !remoteUuids.contains(e.uuid) && !_knownRemoteUuids.contains(e.uuid))
          .toList();
      // b) Обновления — все локальные с uuid, которые уже есть на сервере, перезаписываем (last-write-wins).
      // Чтобы не терять офлайн-правки, выгружаем все локальные с uuid (батчем без фото).
      // Новые уже включены, но для простоты выгружаем все локальные с uuid как upsert.
      final allWithUuid = local.where((e) => e.uuid != null).toList();
      if (allWithUuid.isNotEmpty) {
        final plain = allWithUuid.where((e) =>
            e.photoPath == null || !File(e.photoPath!).existsSync()).toList();
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
              }).toList();
          try {
            await SupabaseService.client!.from('diary_entries').upsert(payload, onConflict: 'uuid');
          } catch (e) {
            debugPrint('SYNC: bulk upsert error $e');
          }
        }
        for (final e in allWithUuid) {
          if (e.photoPath != null && File(e.photoPath!).existsSync()) {
            await _insertRemote(e);
          }
        }
        // Присвоить uuid тем, у кого его не было (старые записи).
        final withoutUuid = local.where((e) => e.uuid == null).toList();
        for (final e in withoutUuid) {
          final uid = _uuid.v4();
          await _db.updateDiaryEntry(DiaryEntry(
            id: e.id,
            uuid: uid,
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
          await _insertRemote(_copyWithUuid(e, uid));
        }
      } else if (newEntries.isNotEmpty) {
        // Fallback: старые записи без uuid — уже обработаны выше.
      }

      // Обновляем кэш известных uuid.
      await _saveKnown(remoteUuids.union(allWithUuid.map((e) => e.uuid!).toSet()));
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

  /// Подписка на изменения на сервере.
  /// Realtime только сигнализирует об изменениях — фактическая синхронизация
  /// происходит по требованию (баннер + кнопка пользователя).
  void _setupRealtime() {
    SupabaseService.client?.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        listenRealtime();
        // При входе — синхронизация.
        unawaited(syncWithServer());
      } else {
        _realtimeSub?.unsubscribe();
        _realtimeSub = null;
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
    _realtimeSub?.unsubscribe();
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

  Future<void> _insertRemote(DiaryEntry entry) async {
    final auth = SupabaseService.client?.auth;
    final user = auth?.currentUser;
    if (user == null) return;
    String? photoUrl;
    try {
      final path = entry.photoPath;
      if (path != null && File(path).existsSync()) {
        final file = File(path);
        final ext = path.split('.').lastOrNull?.toLowerCase() ?? 'jpg';
        final objName = '${user.id}/${entry.uuid ?? DateTime.now().millisecondsSinceEpoch}.$ext';
        await SupabaseService.client!.storage.from('diary-photos').upload(objName, file);
        photoUrl = objName;
      }
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
      }, onConflict: 'uuid');
    } catch (e) {
      debugPrint('Diary insert remote error: $e');
    }
  }

  Future<void> _uploadEntry(DiaryEntry entry) async {
    await _insertRemote(entry);
  }
}