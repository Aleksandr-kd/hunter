import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../models/diary_entry.dart';
import '../services/supabase_service.dart';
import 'diary_sync_engine.dart';

const _uuid = Uuid();

/// Управляет записями дневника (офлайн/локально + синхронизация с Supabase).
class DiaryProvider extends ChangeNotifier {
  final AppDatabase _db;
  final DiarySyncEngine _engine;
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

  // Инициализация known-кэша: syncWithServer обязан дождаться её, иначе
  // toDeleteLocal не увидит ранее известных uuid (гонка при старте).
  late Future<void> _knownLoaded;

  /// [db] и [engine] инжектируются для тестируемости. По умолчанию — прод-
  /// реализация (AppDatabase + SupabaseDiaryBackend).
  DiaryProvider({AppDatabase? db, DiarySyncEngine? engine})
      : _db = db ?? AppDatabase(),
        _engine = engine ?? DiarySyncEngine(db: db ?? AppDatabase(), backend: SupabaseDiaryBackend()) {
    load();
    _knownLoaded = _engine.loadKnown();
    _setupRealtime();
    // Одна синхронизация при старте — чтобы показать lastSync.
    unawaited(syncWithServer());
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
    await _engine.resetKnown();
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
      // Удаляем на сервере; из known-кэша uuid убираем ТОЛЬКО после успешного
      // удаления — иначе при следующем pull запись «воскреснет» с сервера.
      await _engine.deleteRemoteAndForget(uuid);
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

  /// Двухсторонняя синхронизация: делегирует алгоритм в DiarySyncEngine,
  /// а здесь ведёт только состояние (флаг синка, повторный запрос, lastSync).
  Future<void> syncWithServer() async {
    debugPrint('SYNC: start, ready=${_engine.backend.ready}');
    if (!_engine.backend.ready) return;
    final user = _engine.backend.userId;
    debugPrint('SYNC: user=$user');
    if (user == null) return;

    await _knownLoaded; // дожидаемся загрузки known-кэша (см. конструктор).
    if (_syncRunning) {
      _needResync = true;
      return;
    }
    _syncRunning = true;

    _syncing = true;
    notifyListeners();
    try {
      final outcome = await _engine.sync();
      _lastSync = DateTime.now();
      _lastError = outcome.error;
      if (outcome.changed) await load();
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
      photoUrl: e.photoUrl,
      notes: e.notes,
      result: e.result,
      weight: e.weight,
      count: e.count,
      method: e.method,
    );
  }

  Future<void> _uploadEntry(DiaryEntry entry) async {
    final ok = await _engine.pushEntry(entry);
    // Обновляем updatedAt локально после успешного апsertа — предотвращает
    // бесконечный ретрайд если фото не загрузилось. Заодно фиксируем
    // photoUrl, чтобы повторный sync не качал фото заново (баг 8).
    // БАГ #1 исправлен: entry.photoUrl уже содержит новый URL из _pushWithPhoto.
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
        photoUrl: entry.photoUrl,
        notes: entry.notes,
        result: entry.result,
        weight: entry.weight,
        count: entry.count,
        method: entry.method,
      ));
      // После успешного upload — pull с сервера, чтобы гарантировать
      // что данные обновятся на всех устройствах (realtime может не работать).
      unawaited(syncWithServer());
    }
  }
}
