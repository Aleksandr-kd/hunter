import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs_keys.dart';
import '../models/hunting_record.dart';
import '../services/notification_service.dart';
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
  bool _hasRemoteChange = false;

  List<HuntingRecord> get records => List.unmodifiable(_records);
  bool get loaded => _loaded;
  bool get syncing => _syncing;
  DateTime? get lastUpdated => _lastUpdated;
  bool get hasRemoteChange => _hasRemoteChange;

  SeasonsProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadCache();
    _loaded = true;
    notifyListeners();
    // Тянем данные один раз при старте — дальше только по требованию.
    await _fetchRemote();
    // Планируем уведомления о сезонах.
    unawaited(checkSeasonNotifications());
  }

  /// Ручное обновление (pull-to-refresh) — игнорирует троттлинг.
  Future<void> refresh() => _fetchRemote(force: true);

  void consumeRemoteChange() {
    _hasRemoteChange = false;
    notifyListeners();
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

  Future<void> _fetchRemote({bool force = false}) async {
    if (!SupabaseService.isReady) return;
    // Троттлинг: не чаще раза в 1 минуту (для защиты от двойного tap).
    if (!force && _lastUpdated != null && DateTime.now().difference(_lastUpdated!) < const Duration(minutes: 1)) {
      return;
    }
    if (_syncing) return;
    _syncing = true;
    _hasRemoteChange = false;
    notifyListeners();
    try {
      final res = await SupabaseService.client!
          .from('hunting_seasons')
          .select();
      final list = (res as List).cast<Map<String, dynamic>>()
          .map(HuntingRecord.fromJson)
          .toList();
      // Если данные не изменились — не пишем кэш лишний раз.
      if (list.length == _records.length && jsonEncode(list) == jsonEncode(_records.map((e) => e.toJson()).toList())) {
        _lastUpdated = DateTime.now();
        notifyListeners();
        return;
      }
      _records = list;
      _lastUpdated = DateTime.now();
      await _saveCache(list);
      // Планируем уведомления о сезонах.
      unawaited(checkSeasonNotifications());
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

  /// Проверка и планирование уведомлений о сезонах (за 7 и 3 дня).
  Future<void> checkSeasonNotifications() async {
    if (!NotificationService.isReady) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(PrefsKeys.notificationsSeasons) ?? true;
      if (!enabled) return;

      final svc = NotificationService.instance;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (final record in _records) {
        if (record.openDate == null || record.openDate!.isEmpty) continue;

        final openParts = record.openDate!.split('.');
        final closeParts = record.closeDate?.split('.') ?? [];
        final openDay = int.tryParse(openParts[0]) ?? 0;
        final openMonth = int.tryParse(openParts[1]) ?? 0;
        final closeDay = closeParts.isNotEmpty ? (int.tryParse(closeParts[0]) ?? 0) : 0;
        final closeMonth = closeParts.length > 1 ? (int.tryParse(closeParts[1]) ?? 0) : 0;

        // Открытие — текущий год.
        final openDate = DateTime(now.year, openMonth, openDay);
        // Закрытие — если дата меньше открытия, значит следующий год.
        DateTime closeDate;
        if (closeMonth > 0 && closeDay > 0) {
          final candidate = DateTime(now.year, closeMonth, closeDay);
          closeDate = candidate.isBefore(openDate)
              ? candidate.add(const Duration(days: 365))
              : candidate;
        } else {
          continue;
        }

        // Уведомления за 7 и 3 дня до открытия.
        for (final days in [7, 3]) {
          final notify = openDate.subtract(Duration(days: days));
          final diff = notify.difference(today).inDays;
          if (diff == 0) {
            final id = _seasonNotifId(record, 'open', days);
            await svc.scheduleNotification(
              id: id,
              title: 'Сезон открывается завтра',
              body: '${record.resource} / ${record.season} / ${record.species} — открытие через $days дней (${_fmtShort(openDate)}).',
              scheduledAt: notify,
            );
          }
        }

        // Уведомления за 7 и 3 дня до закрытия.
        for (final days in [7, 3]) {
          final notify = closeDate.subtract(Duration(days: days));
          final diff = notify.difference(today).inDays;
          if (diff == 0) {
            final id = _seasonNotifId(record, 'close', days);
            await svc.scheduleNotification(
              id: id,
              title: 'Сезон заканчивается',
              body: '${record.resource} / ${record.season} / ${record.species} — конец через $days дней (${_fmtShort(closeDate)}).',
              scheduledAt: notify,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Season notifications error: $e');
    }
  }

  static int _seasonNotifId(HuntingRecord record, String type, int days) {
    final hash = '${record.regionId}_${record.resource}_${record.season}_${record.species}'.hashCode;
    return (hash.abs() % 100000) * 100 + (type == 'open' ? 10 : 20) + days;
  }

  static String _fmtShort(DateTime d) {
    const months = [
      '', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return '${d.day} ${months[d.month]}';
  }

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