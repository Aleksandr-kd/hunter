import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/document.dart';
import '../services/supabase_service.dart';

/// Управляет документами (офлайн/локально + синхронизация с Supabase).
class DocumentProvider extends ChangeNotifier {
  static const _key = 'documents_expiry';

  final List<Document> _documents = [];
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
  }

  // ------------------------------------------------------------------
  // Локальный кэш (SharedPreferences)
  // ------------------------------------------------------------------

  Future<void> _loadLocal() async {
    final defaults = [
      'Охотничий билет',
      'Разрешение на оружие (РСОА)',
      'Договор / путёвка охотхозяйства',
      'Разрешение на добычу (текущий сезон)',
    ];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
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
      for (final r in remote) {
        final title = r['title'] as String?;
        if (title == null) continue;
        final idx = _documents.indexWhere((d) => d.title == title);
        final expiry = r['expiry_date'] != null
            ? DateTime.tryParse(r['expiry_date'] as String)
            : null;
        if (idx >= 0) {
          _documents[idx] = _documents[idx].copyWith(
            supabaseId: r['id'] as String?,
            expiryDate: expiry,
          );
        } else {
          // Новый документ с сервера — добавляем.
          _documents.add(Document(
            supabaseId: r['id'] as String?,
            title: title,
            expiryDate: expiry,
          ));
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

    _documents[idx] = _documents[idx].copyWith(expiryDate: expiry);
    await _saveLocal();
    notifyListeners();

    // Синхронизация с сервером в фоне.
    unawaited(_uploadDocument(_documents[idx]));
  }

  /// Выгружает один документ на сервер.
  Future<void> _uploadDocument(Document doc) async {
    if (!SupabaseService.isReady) return;
    final user = SupabaseService.client?.auth.currentUser;
    if (user == null) return;

    try {
      final client = SupabaseService.client!;
      final fields = {
        'user_id': user.id,
        'title': doc.title,
        'expiry_date': doc.expiryDate?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      // Не полагаемся на имя уникального constraint: ищем существующую
      // запись по (user_id, title) и обновляем по id, иначе вставляем новую.
      final existing = await client
          .from('user_documents')
          .select('id')
          .eq('user_id', user.id)
          .eq('title', doc.title)
          .maybeSingle();
      if (existing != null && existing['id'] != null) {
        await client
            .from('user_documents')
            .update(fields)
            .eq('id', existing['id']);
      } else {
        await client.from('user_documents').insert(fields);
      }
      debugPrint('SYNC: uploaded doc "${doc.title}"');
    } catch (e) {
      debugPrint('DocumentProvider: upload error: $e');
    }
  }
}
