import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/document.dart';
import '../services/supabase_service.dart';

/// Управляет документами (офлайн/локально + синхронизация с Supabase).
class DocumentProvider extends ChangeNotifier {
  static const _key = 'documents_expiry';
  static const _lastModifiedKey = 'documents_last_modified';
  static const _deletedIdsKey = 'documents_deleted_ids';

  static const List<String> _defaultTitles = [
    'Охотничий билет',
    'Разрешение на оружие (РСОА)',
    'Договор / путёвка охотхозяйства',
    'Разрешение на добычу (текущий сезон)',
  ];

  final List<Document> _documents = [];
  // title -> локальное время последнего изменения (для LWW при синке).
  Map<String, DateTime> _lastModified = {};
  // Tombstone: supabaseId документов, удалённых этим устройством. Защищает от
  // «воскрешения» удалённого документа при синке и от авто-удаления чужих
  // записей (P1-2).
  Set<String> _deletedIds = {};
  bool _loaded = false;
  bool _syncing = false;
  DateTime? _lastSync;
  String? _lastError;

  List<Document> get documents => List.unmodifiable(_documents);
  bool get loaded => _loaded;
  bool get syncing => _syncing;
  DateTime? get lastSync => _lastSync;
  String? get lastError => _lastError;

  DocumentProvider() {
    _loadLocal();
    unawaited(syncWithServer());
    // При выходе из аккаунта чистим локальный кэш, чтобы документы одного
    // пользователя не утекли другому на этом же устройстве (см. ячейку 2).
    SupabaseService.client?.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        clearLocal();
      }
    });
  }

  // ------------------------------------------------------------------
  // Локальный кэш (SharedPreferences)
  // ------------------------------------------------------------------

  /// Сбрасывает локальные документы (даты и кэш LWW) при выходе из аккаунта.
  Future<void> clearLocal() async {
    final defaults = _defaultTitles;
    _documents
      ..clear()
      ..addAll(defaults.map((t) => Document(title: t)));
    _lastModified.clear();
    _deletedIds.clear();
    _lastSync = null;
    _lastError = null;
    await _saveLocal();
    notifyListeners();
  }

  Future<void> _loadLocal() async {
    final defaults = _defaultTitles;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final rawLastMod = prefs.getString(_lastModifiedKey);
      final rawDeleted = prefs.getStringList(_deletedIdsKey);
      if (rawDeleted != null) {
        _deletedIds = rawDeleted.toSet();
      }
      if (rawLastMod != null && rawLastMod.isNotEmpty) {
        try {
          final map = (jsonDecode(rawLastMod) as Map<String, dynamic>);
          _lastModified = {
            for (final e in map.entries)
              e.key: DateTime.tryParse(e.value as String? ?? '') ?? DateTime.now(),
          };
        } catch (_) {}
      }
      if (raw != null && raw.isNotEmpty) {
        final map = (jsonDecode(raw) as Map<String, dynamic>);
        for (final title in defaults) {
          final iso = map[title];
          _documents.add(Document(
            title: title,
            expiryDate: iso != null ? DateTime.tryParse(iso) : null,
          ));
        }
      } else {
        for (final title in defaults) {
          _documents.add(Document(title: title));
        }
      }
    } catch (e) {
      debugPrint('DocumentProvider: local load error: $e');
    }
    if (_documents.isEmpty) {
      for (final title in defaults) {
        _documents.add(Document(title: title));
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, String>{};
      for (final doc in _documents) {
        if (doc.expiryDate != null) {
          map[doc.title] = doc.expiryDate!.toIso8601String();
        }
      }
      await prefs.setString(_key, jsonEncode(map));
      final lastMod = <String, String>{
        for (final e in _lastModified.entries) e.key: e.value.toIso8601String(),
      };
      await prefs.setString(_lastModifiedKey, jsonEncode(lastMod));
      if (_deletedIds.isNotEmpty) {
        await prefs.setStringList(_deletedIdsKey, _deletedIds.toList());
      } else {
        await prefs.remove(_deletedIdsKey);
      }
    } catch (e) {
      debugPrint('DocumentProvider: local save error: $e');
    }
  }

  // ------------------------------------------------------------------
  // Синхронизация с сервером
  // ------------------------------------------------------------------

  Future<void> syncWithServer() async {
    if (!SupabaseService.isReady) return;
    final user = SupabaseService.client?.auth.currentUser;
    if (user == null) return;

    _syncing = true;
    notifyListeners();
    try {
      // 1) Тянем с сервера.
      final res = await SupabaseService.client!
          .from('user_documents')
          .select('id,title,expiry_date,updated_at')
          .eq('user_id', user.id);
      final remote = (res as List).cast<Map<String, dynamic>>();

      // 2) Обновляем локальные данные из серверных.
      // LWW: серверная версия применяется только если она новее локальной.
      // Иначе локальная версия сохраняется и повторно пушится на сервер
      // (страховка от потери изменения при недоступном upload-моменте).
      final toPush = <String>[];
      for (final r in remote) {
        final title = r['title'] as String?;
        if (title == null) continue;
        final idx = _documents.indexWhere((d) => d.title == title);
        final expiry = r['expiry_date'] != null
            ? DateTime.tryParse(r['expiry_date'] as String)
            : null;
        final remoteUpdated = _parseUpdatedAt(r['updated_at']);
        final localUpdated = _lastModified[title];
        if (idx >= 0) {
          final current = _documents[idx];
          final keepLocal = localUpdated != null &&
              (remoteUpdated == null || !remoteUpdated.isAfter(localUpdated));
          if (keepLocal) {
            if (current.supabaseId == null && r['id'] != null) {
              _documents[idx] = current.copyWith(supabaseId: r['id'] as String?);
            }
            toPush.add(title);
          } else {
            _documents[idx] = current.copyWith(
              supabaseId: r['id'] as String?,
              expiryDate: expiry,
              updatedAt: remoteUpdated,
            );
            _lastModified.remove(title);
          }
        } else {
          // Новый документ с сервера. Пропускаем, если этот документ был
          // удалён этим устройством (tombstone) — иначе удалённый документ
          // «воскреснет» при следующем sync (P1-2).
          final remoteId = r['id'] as String?;
          if (remoteId != null && _deletedIds.contains(remoteId)) {
            continue;
          }
          _documents.add(Document(
            supabaseId: r['id'] as String?,
            title: title,
            expiryDate: expiry,
            updatedAt: remoteUpdated,
          ));
        }
      }

      // 2b) Повторно выгружаем локальные документы, которые новее серверных
      // (изменения, не долетевшие до сервера при прошлой попытке).
      for (final title in toPush) {
        final idx = _documents.indexWhere((d) => d.title == title);
        if (idx >= 0) {
          await _uploadDocument(_documents[idx]);
        }
      }

      // 3) Удаляем с сервера те, которые помечены этим устройством как
      // удалённые (tombstone) и которых уже нет локально. Удаление ТОЛЬКО по
      // supabaseId из tombstone: произвольные серверные записи (добавленные
      // на другом устройстве) не трогаются, пока их явно не удалят (P1-2).
      final toDeleteIds = remoteIdsToDelete(_documents, remote, _deletedIds);
      for (final id in toDeleteIds) {
        final record = remote.firstWhere((r) => r['id'] == id);
        final title = record['title'] as String?;
        try {
          await SupabaseService.client!
              .from('user_documents')
              .delete()
              .eq('id', id);
          debugPrint('SYNC: deleted remote doc "$title"');
        } catch (e) {
          debugPrint('SYNC: delete remote doc error: $e');
        }
      }

      _lastSync = DateTime.now();
      _lastError = null;
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      debugPrint('DocumentProvider: sync error: $e');
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------
  // Операции с документами
  // ------------------------------------------------------------------

  /// Обновляет дату истечения документа и синхронизирует с сервером.
  Future<void> updateExpiry(Document doc, DateTime? expiry) async {
    final idx = _documents.indexWhere((d) => d.title == doc.title);
    if (idx < 0) return;

    _documents[idx] = _documents[idx].copyWith(
      expiryDate: expiry,
      updatedAt: DateTime.now(),
    );
    // Фиксируем локальное время изменения для LWW.
    _lastModified[doc.title] = DateTime.now();
    await _saveLocal();
    notifyListeners();

    // Синхронизация с сервером в фоне.
    unawaited(_uploadDocument(_documents[idx]));
  }

  /// Выгружает один документ на сервер. Возвращает true при успехе.
  /// Используем onConflict: 'user_id, title' вместо N+1 SELECT → INSERT/UPDATE.
  Future<bool> _uploadDocument(Document doc) async {
    if (!SupabaseService.isReady) return false;
    final user = SupabaseService.client?.auth.currentUser;
    if (user == null) return false;

    try {
      final client = SupabaseService.client!;
      // onConflict: 'id' — primary key. Supabase поддерживает upsert по
      // уникальному constraint (user_id, title), но для простоты используем
      // id и обновляем запись по user_id + title.
      final existing = await client
          .from('user_documents')
          .select('id')
          .eq('user_id', user.id)
          .eq('title', doc.title)
          .maybeSingle();
      if (existing != null && existing['id'] != null) {
        await client
            .from('user_documents')
            .update({
              'user_id': user.id,
              'title': doc.title,
              'expiry_date': doc.expiryDate?.toIso8601String(),
              'updated_at': (doc.updatedAt ?? DateTime.now()).toIso8601String(),
            })
            .eq('id', existing['id']);
      } else {
        await client.from('user_documents').insert({
          'user_id': user.id,
          'title': doc.title,
          'expiry_date': doc.expiryDate?.toIso8601String(),
          'updated_at': (doc.updatedAt ?? DateTime.now()).toIso8601String(),
        });
      }
      // Сервер догнал локальную версию — снимаем флаг «локально изменённого».
      // Для сброса даты (expiry == null) флаг держим, чтобы параллельная
      // синхронизация не вернула с сервера устаревшую дату до её фактического
      // обнуления в БД (защита от «воскрешения» сброшенной даты).
      if (doc.expiryDate != null) {
        _lastModified.remove(doc.title);
      }
      await _saveLocal();
      debugPrint('SYNC: uploaded doc "${doc.title}"');
      return true;
    } catch (e) {
      debugPrint('DocumentProvider: upload error: $e');
      return false;
    }
  }

  /// Удаляет документ локально и на сервере. При неудаче серверного удаления
  /// удалённый supabaseId сохраняется в tombstone, чтобы следующий sync не
  /// «воскресил» документ и не удалил чужие записи (P1-2).
  Future<void> deleteDocument(Document doc) async {
    final idx = _documents.indexWhere((d) => d.title == doc.title);
    if (idx < 0) return;

    final title = doc.title;
    final supabaseId = doc.supabaseId;

    _documents.removeAt(idx);
    _lastModified.remove(title);
    if (supabaseId != null) {
      _deletedIds.add(supabaseId);
    }
    await _saveLocal();
    notifyListeners();

    // Удаляем с сервера. При успехе tombstone можно снять, но безопаснее
    // оставить до фактического удаления в sync (id больше не встретится).
    if (supabaseId != null && SupabaseService.isReady) {
      try {
        await SupabaseService.client!
            .from('user_documents')
            .delete()
            .eq('id', supabaseId);
        _deletedIds.remove(supabaseId);
        await _saveLocal();
        debugPrint('SYNC: deleted local doc "$title"');
      } catch (e) {
        debugPrint('DocumentProvider: delete error: $e');
      }
    }
  }

  /// Чистая функция выбора серверных id документов для удаления при синке
  /// (P1-2). Удаляются ТОЛЬКО записи, которые:
  ///   - присутствуют локально как удалённые (id в tombstone `deletedIds`), И
  ///   - уже отсутствуют в локальном списке документов.
  /// Документы, добавленные на других устройствах (id не в tombstone), НЕ
  /// удаляются, даже если их title отсутствует локально. Вынесена в static
  /// (публичный helper) для юнит-тестирования без сети.
  static List<String> remoteIdsToDelete(
    List<Document> local,
    List<Map<String, dynamic>> remote,
    Set<String> deletedIds,
  ) {
    final localSupabaseIds = local
        .map((d) => d.supabaseId)
        .whereType<String>()
        .toSet();
    final result = <String>[];
    for (final r in remote) {
      final id = r['id'] as String?;
      if (id == null) continue;
      // Запись ещё есть локально — не удаляем (удаление не «доехало»).
      if (localSupabaseIds.contains(id)) continue;
      // Удаляем только те, что это устройство явно пометило tombstone.
      if (!deletedIds.contains(id)) continue;
      result.add(id);
    }
    return result;
  }

  static DateTime? _parseUpdatedAt(Object? v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}
