import 'dart:async';
import 'dart:io';

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
  bool _resyncPending = false;
  DateTime? _lastPostUploadSync;
  Timer? _realtimeSyncDebounce;
  /// До этого момента realtime-эхо от СОБСТВЕННОГО синка игнорируется, чтобы
  /// наш же upsert (и, шире, любой activity после sync) не раскручивал
  /// самоподпитывающийся цикл «синк → realtime-эхо → синк». Настоящие чужие
  /// изменения вне этого окна продолжают запускать автосинк.
  DateTime? _ignoreRealtimeUntil;
  RealtimeChannel? _realtimeSub;

  /// Окно, в котором realtime-эхо от собственного синка игнорируется.
  /// Должно быть чуть больше дебаунса realtime-синка (по умолчанию 2с),
  /// чтобы эхо успело прийти и быть подавленным, но не блокировало надолго
  /// чужие изменения. Параметризуется для тестов.
  final Duration realtimeEchoWindow;
  final Duration realtimeDebounce;

  // Последовательная очередь фоновых аплоадов. Все addEntry/updateEntry/
  // restoreFromBackup ставят загрузку в цепочку, а deleteEntry дожидается
  // её завершения — это исключает «воскрешение» удалённой записи на сервере
  // и конфликты параллельных upsert.
  Future<void> _uploadQueue = Future.value();
  /// Очередь upload для тестового ожидания завершения фоновых операций.
  Future<void> get uploadQueue => _uploadQueue;
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
  DiarySyncEngine get engine => _engine;
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
  /// реализация (AppDatabase + SupabaseDiaryBackend). [realtimeEchoWindow]
  /// и [realtimeDebounce] также настраиваемые (для тестов), по умолчанию
  /// 4с/2с соответственно.
  DiaryProvider({
    AppDatabase? db,
    DiarySyncEngine? engine,
    this.realtimeEchoWindow = const Duration(seconds: 4),
    this.realtimeDebounce = const Duration(seconds: 2),
  })  : _db = db ?? AppDatabase(),
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
    _realtimeSyncDebounce?.cancel();
    _realtimeSyncDebounce = null;
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
    final withUuid = _copyWithUuid(_markUploading(entry), uid);
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
    String? photoObj;
    try {
      final found = _entries.where((e) => e.id == id).toList();
      if (found.isNotEmpty) {
        uuid = found.first.uuid;
        photoObj = found.first.photoUrl?.isNotEmpty == true
            ? found.first.photoUrl
            : null;
      }
      if (uuid == null) {
        final all = await _db.getDiaryEntries();
        final m = all.where((e) => e.id == id).toList();
        if (m.isNotEmpty) {
          uuid = m.first.uuid;
          photoObj = m.first.photoUrl?.isNotEmpty == true
              ? m.first.photoUrl
              : null;
        }
      }
    } catch (_) {}
    // Удаляем фото из storage, чтобы не копить мусор при удалении записи.
    // Ошибка не блокирует удаление записи — объект зачистится позже (если
    // что, это не мешает синку, т.к. запись удаляется целиком).
    if (photoObj != null && _engine.backend.ready) {
      try {
        await _engine.backend.deletePhoto(photoObj);
      } catch (e) {
        debugPrint('Diary delete entry photo from storage error: $e');
      }
    }
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
    await _db.updateDiaryEntry(_markUploading(entry));
    await load();
    if (entry.uuid != null) {
      // Перечитываем из БД перед upload — чтобы upload использовал
      // актуальные данные (в т.ч. photoUrl который мог обновиться
      // в _uploadEntry предыдущего цикла).
      final fresh = (await _db.getDiaryEntries())
          .firstWhere((e) => e.id == entry.id);
      _enqueueUpload(() => _uploadEntry(fresh));
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
      // Свой push (upsert/self-heal) спровоцирует realtime-эхо на подписку
      // про то же устройство. Глушим его на короткое окно, чтобы не
      // запустить повторный синк и не раскрутить бесконечный цикл.
      _ignoreRealtimeUntil = DateTime.now().add(realtimeEchoWindow);
      _lastSync = DateTime.now();
      _lastError = outcome.error;
      if (outcome.changed) await load();
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _syncing = false;
      _syncRunning = false;
      notifyListeners();
      // Повторяем, если во время синка поступил ещё один запрос. Один
      // флаг на один проход — не позволяем самоподдерживающейся цепочке
      // _needResync раскручивать синк в бесконечный цикл.
      if (_needResync && !_resyncPending) {
        _needResync = false;
        _resyncPending = true;
        unawaited(_runAfterResync());
      }
    }
  }

  /// Выполняет один повторный синк после [syncWithServer] и гарантирует,
  /// что цепочка повторов обрезана (доп. повторы игнорируются до реальных
  /// изменений/новых вызовов). Предотвращает «вечное вращение» баннера.
  Future<void> _runAfterResync() async {
    try {
      await syncWithServer();
    } finally {
      _resyncPending = false;
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
      // M4: исключение в async-слушателе не должно всплывать в изолят и
      // ронять подписку — сеть/очистка могут сбоить.
      try {
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
      } catch (e) {
        debugPrint('Diary auth listener error: $e');
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
  /// Автоматически дёргает синхронизацию с дебаунсом, чтобы чужие изменения
  /// (в т.ч. удаления) доходили без ручного нажатия кнопки в баннере.
  void _onRemoteChange() {
    _hasRemoteChange = true;
    notifyListeners();
    // Эхо от СОБСТВЕННОГО синка (наш upsert/self-heal) приходит на ту же
    // подписку realtime. Внутри окна глушения игнорируем его — не планируем
    // повторный синк, чтобы не раскрутить бесконечный цикл
    // «синк → realtime-эхо → синк». Баннер уже показан; настоящие чужие
    // изменения вне окна продолжают запускать автосинк.
    final until = _ignoreRealtimeUntil;
    if (until != null && DateTime.now().isBefore(until)) return;
    _realtimeSyncDebounce?.cancel();
    _realtimeSyncDebounce = Timer(realtimeDebounce, () {
      _realtimeSyncDebounce = null;
      unawaited(syncWithServer());
    });
  }

  /// Обработчик изменения на сервере. Публичен для тестов (симулирует
  /// realtime-событие); в проде вызывается колбэком подписки.
  @visibleForTesting
  void handleRealtimeChange() => _onRemoteChange();

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

  /// Помечает запись статусом «фото загружается», если есть фото-файл.
  /// Если фото нет — статус сбрасывается (null).
  DiaryEntry _markUploading(DiaryEntry e) {
    final hasFile = e.photoPath != null && File(e.photoPath!).existsSync();
    return e.copyWith(photoUploadState: hasFile ? 'uploading' : null);
  }

  Future<void> _uploadEntry(DiaryEntry entry) async {
    final updated = await _engine.pushEntryWithPhoto(entry);
    // Обновляем updatedAt локально после успешного апортта — предотвращает
    // бесконечный ретрайд если фото не загрузилось. Заодно фиксируем
    // photoUrl, чтобы повторный sync не качал фото заново (баг 8).
    // БАГ #3 исправлен: используем ВОЗВРАЩЁННЫЙ updated.photoUrl (новый URL),
    // а не прежний entry.photoUrl (null после смены фото).
    if (updated != null && entry.id != null) {
      await _db.updateDiaryEntry(DiaryEntry(
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
      // После успешного upload — pull с сервера, чтобы гарантировать что
      // данные обновятся на всех устройствах (realtime может не работать).
      // ДЕБАУНС: при пакетной загрузке (миграция ~30 записей) не запускаем
      // полный engine.sync() на ПЕРВУЮ запись — это была лавина полных синков
      // (по одному на запись), каждый с медленным фото-upload, что выглядело
      // как «вечно висящая синхронизация». Вместо этого планируем один pull
      // не чаще раза в 2 секунды; лишние запросы схлопываются.
      final now = DateTime.now();
      final last = _lastPostUploadSync;
      if (last == null || now.difference(last).inSeconds >= 2) {
        _lastPostUploadSync = now;
        // ignore: unawaited_futures
        unawaited(_engine.sync().then((outcome) {
          if (outcome.changed) load();
        }));
      }
    } else if (updated == null && entry.id != null) {
      // Upload не удался (текстовая часть не ушла) — вернём статус failed,
      // чтобы пользователь мог нажать «Повторить» (если фото было).
      await _db.updateDiaryEntry(entry.copyWith(
        photoUploadState:
            (entry.photoPath != null && File(entry.photoPath!).existsSync())
                ? 'failed'
                : null,
      ));
    }
  }

  /// Ручной повторный upload фото записи (кнопка «Повторить» в UI).
  /// Используется, когда авто-ретрай (1 раз) не помог и статус = failed.
  Future<void> retryPhotoUpload(DiaryEntry entry) async {
    if (entry.id == null) return;
    await _db.updateDiaryEntry(_markUploading(entry));
    await load();
    _enqueueUpload(() => _uploadEntry(entry));
  }

  /// id записей, у которых прямо сейчас выполняется удаление фото.
  /// Используется UI для показа спиннера вместо крестика/бейджа.
  final Set<int> _removingPhotoIds = {};
  bool isRemovingPhoto(DiaryEntry e) =>
      e.id != null && _removingPhotoIds.contains(e.id!);

  /// Удаляет фото из записи: локально (photoPath/photoUrl/статус) и из
  /// Supabase storage (чтобы не копить мусор). Вызывается тихо, без
  /// подтверждения. Если storage недоступен — фото удаляется локально,
  /// а следующая синхронизация зачистит объект (upsert с photo_url=null не
  /// затрёт чужое: объект чистим отдельно).
  ///
  /// Пока операция идёт, запись числится в [isRemovingPhoto] (UI показывает
  /// лоадер). Возвращает `true`, если фото удалено локально успешно, и
  /// `false` при сбое (например, не удалось удалить локальный файл) — тогда
  /// UI может предложить «Повторить». Повторный вызов во время выполнения
  /// считается успешным (операция уже идёт), чтобы двойной тап не показывал
  /// ложную ошибку.
  Future<bool> removePhoto(DiaryEntry entry) async {
    if (entry.id == null) return false;
    if (_removingPhotoIds.contains(entry.id)) return true;
    _removingPhotoIds.add(entry.id!);
    notifyListeners();
    try {
      // Сохраняем objName (photoUrl) — он нужен, чтобы при офлайне позже
      // (когда сеть вернётся) удалить объект из storage. Если удаление
      // удастся сразу — сбросим. Иначе ставим tombstone 'removed', и sync
      // дожмёт удаление (не «вернёт» фото).
      final objName = entry.photoUrl;
      final path = entry.photoPath;
      var ok = true;
      var tombstone = false;

      if (objName != null && objName.isNotEmpty && _engine.backend.ready) {
        try {
          await _engine.backend.deletePhoto(objName);
        } catch (e) {
          debugPrint('Diary remove photo from storage error: $e');
          tombstone = true;
        }
      } else if (objName != null && objName.isNotEmpty) {
        // Сети нет / storage недоступен — оставляем tombstone для доудаления.
        tombstone = true;
      }

      final updated = entry.copyWith(
        photoPath: null,
        photoUrl: tombstone ? objName : null,
        photoUploadState: tombstone ? 'removed' : null,
        updatedAt: DateTime.now(),
      );
      await _db.updateDiaryEntry(updated);
      await load();

      // Убираем локальный файл.
      if (path != null) {
        try {
          final f = File(path);
          if (f.existsSync()) await f.delete();
        } catch (_) {
          ok = false;
        }
      }

      // Онлайн-удаление: сразу продавливаем photo_url=null на сервер, чтобы
      // другие устройства перестали 404-кать удалённый объект и увидели факт
      // удаления без ожидания следующего синка. Офлайн-случай (tombstone)
      // дожимается в sync через _pushWithPhoto. Ошибка не критична — ближайший
      // bulk (теперь включает photo_url) закроет это.
      if (!tombstone && entry.uuid != null && entry.uuid!.isNotEmpty) {
        try {
          await _engine.backend.pushEntry(updated, null);
        } catch (e) {
          debugPrint('Diary remove photo remote push error: $e');
        }
      }
      return ok;
    } finally {
      _removingPhotoIds.remove(entry.id);
      notifyListeners();
    }
  }
}
