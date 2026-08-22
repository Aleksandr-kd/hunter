import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../models/diary_entry.dart';
import '../services/supabase_service.dart';
import '../services/tier_manager.dart';

const _uuid = Uuid();

/// Управляет записями дневника (офлайн/локально + синхронизация с Supabase).
class DiaryProvider extends ChangeNotifier {
  static const int freeLimit = 10;

  final AppDatabase _db = AppDatabase();
  List<DiaryEntry> _entries = [];
  bool _loaded = false;
  bool _syncing = false;
  RealtimeChannel? _realtimeSub;

  List<DiaryEntry> get entries => List.unmodifiable(_entries);
  bool get loaded => _loaded;
  bool get syncing => _syncing;
  int get freeRemaining => TierManager.isUnlimited ? -1 : (freeLimit - _entries.length);

  DiaryProvider() {
    load();
    _setupRealtime();
  }

  Future<void> load() async {
    _entries = await _db.getDiaryEntries();
    _loaded = true;
    notifyListeners();
  }

  /// Возвращает true, если запись добавлена; false — если лимит исчерпан.
  Future<bool> addEntry(DiaryEntry entry) async {
    if (!TierManager.isUnlimited && _entries.length >= freeLimit) return false;
    final uid = entry.uuid ?? _uuid.v4();
    final withUuid = _copyWithUuid(entry, uid);
    final id = await _db.insertDiaryEntry(withUuid);
    // Выгрузка на сервер в фоне — не блокирует закрытие экрана.
    unawaited(_uploadEntry(withUuid));
    await load();
    return id > 0;
  }

  Future<void> deleteEntry(int id) async {
    await _db.deleteDiaryEntry(id);
    await load();
  }

  /// Двухсторонняя синхронизация: серверные записи в локальные и наоборот.
  Future<void> syncWithServer() async {
    debugPrint('SYNC: start, ready=${SupabaseService.isReady}');
    if (!SupabaseService.isReady) return;
    final user = SupabaseService.client?.auth.currentUser;
    debugPrint('SYNC: user=${user?.email}, id=${user?.id}');
    if (user == null) return;

    _syncing = true;
    notifyListeners();
    try {
      // 1) Тянем с сервера записи.
      final res = await SupabaseService.client!
          .from('diary_entries')
          .select('uuid,species,location,weather,notes,entry_date,latitude,longitude,photo_url')
          .eq('user_id', user.id)
          .order('entry_date')
          .limit(1000);
      final remote = (res as List).cast<Map<String, dynamic>>();
      debugPrint('SYNC: remote=${remote.length}, sample=${remote.isNotEmpty ? remote.first : "none"}');

      final local = await _db.getDiaryEntries();
      final localUuids = local.map((e) => e.uuid).whereType<String>().toSet();
      debugPrint('SYNC: local=${local.length}');

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
        ));
        changed = true;
      }

      // 3) Заливаем локальные, которых нет на сервере.
      final remoteUuids = remote.map((r) => r['uuid'] as String?).whereType<String>().toSet();
      for (final entry in local) {
        if (entry.uuid == null || !remoteUuids.contains(entry.uuid)) {
          await _insertRemote(entry);
        }
      }

      if (changed) await load();
    } catch (e) {
      debugPrint('Diary sync error: $e');
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Подписка на изменения на сервере (реальное время появления записей с других устройств).
  void _setupRealtime() {
    SupabaseService.client?.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        listenRealtime();
        syncWithServer();
      } else {
        _realtimeSub?.unsubscribe();
        _realtimeSub = null;
      }
    });
    if (SupabaseService.client?.auth.currentUser != null) {
      listenRealtime();
      // При старте приложения (сессия уже есть) — подтягиваем всё с сервера.
      syncWithServer();
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
          callback: (_) => syncWithServer(),
        )
        .subscribe();
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
      }, onConflict: 'uuid');
    } catch (e) {
      debugPrint('Diary insert remote error: $e');
    }
  }

  Future<void> _uploadEntry(DiaryEntry entry) async {
    await _insertRemote(entry);
  }
}