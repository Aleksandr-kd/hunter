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

  static const List<String> _defaultTitles = [
    'Охотничий билет',
    'Разрешение на оружие (РСОА)',
    'Договор / путёвка охотхозяйства',
    'Разрешение на добычу (текущий сезон)',
  ];

  final List<Document> _documents = [];
  // title -> локальное время последнего изменения (для LWW при синке).
  Map<String, DateTime> _lastModified = {};
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
          // Новый документ с сервера — добавляем.
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

      // 3) Удаляем с сервера те, которых больше нет локально.
      final localTitles = _documents.map((d) => d.title).toSet();
      final remoteTitles = remote.map((r) => r['title'] as String).toSet();
      final toDelete = remoteTitles.difference(localTitles);
      for (final title in toDelete) {
        final record = remote.firstWhere((r) => r['title'] == title);
        final supabaseId = record['id'] as String?;
        if (supabaseId != null) {
          try {
            await SupabaseService.client!
                .from('user_documents')
                .delete()
                .eq('id', supabaseId);
            debugPrint('SYNC: deleted remote doc "$title"');
          } catch (e) {
            debugPrint('SYNC: delete remote doc error: $e');
          }
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

  /// Удаляет документ локально и на сервере.
  Future<void> deleteDocument(Document doc) async {
    final idx = _documents.indexWhere((d) => d.title == doc.title);
    if (idx < 0) return;

    final title = doc.title;
    final supabaseId = doc.supabaseId;

    _documents.removeAt(idx);
    _lastModified.remove(title);
    await _saveLocal();
    notifyListeners();

    // Удаляем с сервера.
    if (supabaseId != null && SupabaseService.isReady) {
      try {
        await SupabaseService.client!
            .from('user_documents')
            .delete()
            .eq('id', supabaseId);
        debugPrint('SYNC: deleted local doc "$title"');
      } catch (e) {
        debugPrint('DocumentProvider: delete error: $e');
      }
    }
  }

  static DateTime? _parseUpdatedAt(Object? v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}
