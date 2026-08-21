import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../models/diary_entry.dart';

/// Управляет записями дневника (офлайн/локально).
class DiaryProvider extends ChangeNotifier {
  static const int freeLimit = 10;

  final AppDatabase _db = AppDatabase();
  List<DiaryEntry> _entries = [];
  bool _loaded = false;
  bool _hasPremium = false; // безлимит для Premium/Max

  List<DiaryEntry> get entries => List.unmodifiable(_entries);
  bool get loaded => _loaded;
  int get freeRemaining => _hasPremium ? -1 : (freeLimit - _entries.length);

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
    if (!_hasPremium && _entries.length >= freeLimit) return false;
    final id = await _db.insertDiaryEntry(entry);
    await load();
    return id > 0;
  }

  Future<void> deleteEntry(int id) async {
    await _db.deleteDiaryEntry(id);
    await load();
  }

  Future<void> setPremium(bool value) async {
    _hasPremium = value;
    notifyListeners();
  }
}