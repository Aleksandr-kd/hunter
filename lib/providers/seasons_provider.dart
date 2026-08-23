import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hunting_record.dart';
import '../services/supabase_service.dart';

/// Управляет справочником сроков охоты.
///
/// Источник данных — таблица `hunting_seasons` в Supabase (публичная, доступна
/// без входа). Приложение тянет данные с сервера и **кэширует их локально**
/// ([SharedPreferences]). Если сети/сервера нет — показываем последний кэш.
/// Хардкод в приложении не используется: всё приходит с сервера.
class SeasonsProvider extends ChangeNotifier {
  static const String _cacheKey = 'hunting_seasons_cache';
  static const List<String> resources = [
    'Пернатая дичь',
    'Болотно-луговая дичь',
    'Боровая дичь',
    'Водоплавающая дичь',
    'Степная и полевая дичь',
    'Копытные животные',
    'Пушные животные',
    'Медведи',
  ];
  static const List<String> seasons = ['Весна', 'Лето', 'Осень', 'Зима'];

  /// Каталог регионов (справочник, как сезоны и ресурсы).
  /// Полнится по мере добавления регионов; сами сроки — с сервера.
  static const List<({String id, String name})> regions = [
    (id: 'krasnodar', name: 'Краснодарский край'),
  ];

  List<HuntingRecord> _records = [];
  bool _loaded = false;
  bool _syncing = false;
  DateTime? _lastUpdated;

  List<HuntingRecord> get records => List.unmodifiable(_records);
  bool get loaded => _loaded;
  bool get syncing => _syncing;
  DateTime? get lastUpdated => _lastUpdated;

  SeasonsProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadCache();
    _loaded = true;
    notifyListeners();
    await _fetchRemote();
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List)
            .cast<Map<String, dynamic>>()
            .map(HuntingRecord.fromJson)
            .toList();
        _records = list;
      }
    } catch (e) {
      debugPrint('Seasons cache read error: $e');
    }
  }

  Future<void> _fetchRemote() async {
    if (!SupabaseService.isReady) return;
    _syncing = true;
    notifyListeners();
    try {
      final res = await SupabaseService.client!
          .from('hunting_seasons')
          .select();
      final list = (res as List).cast<Map<String, dynamic>>()
          .map(HuntingRecord.fromJson)
          .toList();
      _records = list;
      _lastUpdated = DateTime.now();
      await _saveCache(list);
      notifyListeners();
    } catch (e) {
      debugPrint('Seasons fetch error: $e');
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _saveCache(List<HuntingRecord> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _cacheKey, jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('Seasons cache write error: $e');
    }
  }

  /// ID регионов из каталога.
  List<String> get regionIds => regions.map((r) => r.id).toList();

  /// Название региона по id.
  String regionName(String regionId) {
    for (final r in regions) {
      if (r.id == regionId) return r.name;
    }
    return '';
  }

  /// Ресурсы для выбранного региона. Пока каталог ресурсов статичен — возвращаем его.
  List<String> resourcesFor(String regionId) => resources;

  /// Записи по фильтрам. Пустые значения фильтров не применяются.
  List<HuntingRecord> filter({
    String? regionId,
    String? season,
    String? resource,
    String? query,
  }) {
    var result = _records;
    if (regionId != null && regionId.isNotEmpty) {
      result = result.where((r) => r.regionId == regionId).toList();
    }
    if (season != null && season.isNotEmpty) {
      result = result.where((r) => r.season == season).toList();
    }
    if (resource != null && resource.isNotEmpty) {
      result = result.where((r) => r.resource == resource).toList();
    }
    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      result = result.where((r) => r.searchKey.contains(q)).toList();
    }
    return result;
  }
}