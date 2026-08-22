import 'dart:io';

import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../models/diary_entry.dart';
import '../services/supabase_service.dart';
import '../services/tier_manager.dart';

/// Управляет записями дневника (офлайн/локально + синхронизация с Supabase).
class DiaryProvider extends ChangeNotifier {
  static const int freeLimit = 10;

  final AppDatabase _db = AppDatabase();
  List<DiaryEntry> _entries = [];
  bool _loaded = false;

  List<DiaryEntry> get entries => List.unmodifiable(_entries);
  bool get loaded => _loaded;
  int get freeRemaining => TierManager.isUnlimited ? -1 : (freeLimit - _entries.length);

  DiaryProvider() {
    load();
  }

  Future<void> load() async {
    _entries = await _db.getDiaryEntries();
    _loaded = true;
    notifyListeners();
  }

  /// Возвращает true, если запись добавлена; false — если лимит исчерпан.
  Future<bool> addEntry(DiaryEntry entry) async {
    if (!TierManager.isUnlimited && _entries.length >= freeLimit) return false;
    final id = await _db.insertDiaryEntry(entry);
    await _uploadEntry(entry);
    await load();
    return id > 0;
  }

  Future<void> deleteEntry(int id) async {
    await _db.deleteDiaryEntry(id);
    await load();
  }

  /// Загружает записи пользователя с сервера и объединяет с локальными.
  Future<void> syncWithServer() async {
    if (!SupabaseService.isReady) return;
    final auth = SupabaseService.client?.auth;
    if (auth == null) return;
    final user = auth.currentUser;
    if (user == null) return;

    try {
      final res = await SupabaseService.client!
          .from('diary_entries')
          .select('species,location,weather,notes,entry_date,latitude,longitude')
          .eq('user_id', user.id)
          .order('entry_date')
          .limit(500);
      final remote = (res as List).cast<Map<String, dynamic>>();

      // Загрузим локальные и зальём те, которых нет на сервере (по species+date).
      final local = await _db.getDiaryEntries();
      for (final entry in local) {
        final match = remote.where((r) {
          final rd = DateTime.tryParse(r['entry_date'] as String? ?? '');
          return rd != null &&
              rd.toLocal().year == entry.date.year &&
              rd.toLocal().month == entry.date.month &&
              rd.toLocal().day == entry.date.day &&
              (r['species'] ?? '') == entry.species;
        }).isNotEmpty;
        if (!match) {
          await _insertRemote(entry);
        }
      }
    } catch (e) {
      debugPrint('Diary sync error: $e');
    }
  }

  Future<void> _insertRemote(DiaryEntry entry) async {
    final auth = SupabaseService.client?.auth;
    final user = auth?.currentUser;
    if (user == null) return;
    String? photoUrl;
    try {
      // Загрузка фото в Storage (если есть локальный путь).
      final path = entry.photoPath;
      if (path != null && File(path).existsSync()) {
        final file = File(path);
        final ext = path.split('.').lastOrNull?.toLowerCase() ?? 'jpg';
        final objName =
            '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await SupabaseService.client!.storage
            .from('diary-photos')
            .upload(objName, file);
        photoUrl = objName;
      }
      await SupabaseService.client!.from('diary_entries').insert({
        'user_id': user.id,
        'species': entry.species,
        'location': entry.location,
        'weather': entry.weather,
        'notes': entry.notes,
        'entry_date': entry.date.toIso8601String(),
        'latitude': entry.latitude,
        'longitude': entry.longitude,
        'photo_url': photoUrl,
      });
    } catch (e) {
      debugPrint('Diary insert remote error: $e');
    }
  }

  Future<void> _uploadEntry(DiaryEntry entry) async {
    await _insertRemote(entry);
  }
}