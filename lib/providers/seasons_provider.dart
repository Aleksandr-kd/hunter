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
  static const String _notifsScheduledKey = 'season_notifs_scheduled_date';
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

  /// Резервный каталог регионов — используется только пока записи с сервера
  /// не загружены (офлайн, первый запуск, пустой кэш). Основной каталог
  /// строится из фактических записей — см. [regions].
  static const List<({String id, String name})> _fallbackRegions = [
    (id: 'krasnodar', name: 'Краснодарский край'),
    (id: 'stavropol', name: 'Ставропольский край'),
    (id: 'adygea', name: 'Республика Адыгея'),
    (id: 'moscow', name: 'Московская область'),
    (id: 'rostov', name: 'Ростовская область'),
  ];

  List<HuntingRecord> _records = [];
  bool _loaded = false;
  bool _syncing = false;
  DateTime? _lastUpdated;
  bool _hasRemoteChange = false;

  /// «Мой регион» для уведомлений о сезонах (null = не выбран).
  String? _myRegionId;

  /// Кэш id запланированных уведомлений о сезонах (null = не загружено).
  Set<int>? _scheduledNotifIds;

  List<HuntingRecord> get records => List.unmodifiable(_records);
  bool get loaded => _loaded;
  bool get syncing => _syncing;
  DateTime? get lastUpdated => _lastUpdated;
  bool get hasRemoteChange => _hasRemoteChange;

  String? get myRegionId => _myRegionId;

  SeasonsProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadMyRegion();
    await _loadCache();
    _loaded = true;
    notifyListeners();
    // Тянем данные один раз при старте — дальше только по требованию.
    await _fetchRemote();
    // Планируем уведомления о сезонах.
    unawaited(checkSeasonNotifications());
    // Если уведомления о сезонах выключены — снимаем всё, что могло остаться
    // от прошлых запусков.
    if (!(await _notificationsEnabled())) {
      unawaited(clearSeasonNotifications());
    }
  }

  Future<bool> _notificationsEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(PrefsKeys.notificationsSeasons) ?? true;
    } catch (_) {
      return true;
    }
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

  Future<void> _loadMyRegion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(PrefsKeys.seasonsMyRegion) ?? '';
      _myRegionId = v.isEmpty ? null : v;
    } catch (_) {}
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

  /// Каталог регионов, доступных для фильтра «Сроки охоты» и выбора
  /// «Мой регион» в уведомлениях.
  ///
  /// Строится из фактических записей `hunting_seasons` (уникальные
  /// `region_id`/`region_name`): как только на бэкенде появляется новый
  /// регион — он автоматически подхватывается клиентом, отдельно «править
  /// в двух местах» не нужно. Пока записи не загружены (офлайн, пустой
  /// кэш) — показываем резервный список [_fallbackRegions].
  List<({String id, String name})> get regions {
    final map = <String, String>{};
    for (final r in _records) {
      if (r.regionId.isEmpty) continue;
      map[r.regionId] = r.regionName.isEmpty ? r.regionId : r.regionName;
    }
    if (map.isEmpty) return _fallbackRegions;
    final list = map.entries
        .map((e) => (id: e.key, name: e.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(list);
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

  /// Выбор «Моего региона» для уведомлений о сезонах.
  ///
  /// [id] — id из каталога; null или пустая строка — «Не выбран» (напоминания
  /// о сезонах не приходят вовсе). После смены уведомления перепланируются:
  /// старые региона снимаются, планируются только по новому.
  Future<void> setMyRegion(String? id) async {
    final normalized = (id == null || id.isEmpty) ? null : id;
    if (_myRegionId == normalized) return;
    _myRegionId = normalized;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (normalized == null) {
        await prefs.remove(PrefsKeys.seasonsMyRegion);
      } else {
        await prefs.setString(PrefsKeys.seasonsMyRegion, normalized);
      }
    } catch (_) {}
    notifyListeners();
    await reschedule();
  }

  /// Перепланирование уведомлений о сезонах «принудительно» — снимает все
  /// ранее запланированные сезонные уведомления (по сохранённому списку id),
  /// сбрасывает гейт «планировали сегодня» и планирует заново по «Моему
  /// региону». Вызывается при смене региона и при включении тумблера.
  Future<void> reschedule() async {
    await _cancelScheduledNotifications();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_notifsScheduledKey);
    } catch (_) {}
    await checkSeasonNotifications();
  }

  /// Снимает все запланированные уведомления о сезонах (при выключении
  /// тумблера в настройках).
  Future<void> clearSeasonNotifications() async {
    await _cancelScheduledNotifications();
  }

  Future<void> _cancelScheduledNotifications() async {
    final scheduled = await _loadedScheduledIds();
    if (scheduled.isNotEmpty) {
      try {
        await NotificationService.instance
            .cancelAllSeasonReminders(scheduled.toList());
      } catch (_) {}
    }
    _scheduledNotifIds = const {};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PrefsKeys.seasonNotifIds);
    } catch (_) {}
  }

  Future<Set<int>> _loadedScheduledIds() async {
    if (_scheduledNotifIds != null) return _scheduledNotifIds!;
    var ids = <int>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(PrefsKeys.seasonNotifIds) ?? const [];
      ids = raw.map(int.tryParse).whereType<int>().toSet();
    } catch (_) {}
    _scheduledNotifIds = ids;
    return ids;
  }

  Future<void> _saveScheduledIds(Set<int> ids) async {
    _scheduledNotifIds = ids;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          PrefsKeys.seasonNotifIds, ids.map((e) => e.toString()).toList());
    } catch (_) {}
  }

  /// Проверка и планирование уведомлений о сезонах (за 7 и 3 дня).
  ///
  /// Уведомления приходят **только по «Моему региону»** ([myRegionId]): без
  /// выбранного региона ничего не планируется. Уведомления планируются один
  /// раз в день — проверяем, не планировались ли уже сегодня, чтобы избежать
  /// дублирования при множественных вызовах.
  ///
  /// Планируются недостающие (id меняется при смене региона), устаревшие id
  /// (другой регион / уже прошедшие) — снимаются по сохранённому списку.
  Future<void> checkSeasonNotifications() async {
    if (!NotificationService.isReady) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(PrefsKeys.notificationsSeasons) ?? true;
      if (!enabled) return;

      // Проверяем, планировались ли уведомления сегодня.
      final todayStr = '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
      final scheduledToday = prefs.getString(_notifsScheduledKey);
      if (scheduledToday == todayStr) return;

      final svc = NotificationService.instance;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Собираем желаемый набор уведомлений по «Моему региону».
      final plans = <int, ({String title, String body, DateTime at})>{};
      final myRegion = _myRegionId;
      if (myRegion != null && myRegion.isNotEmpty) {
        for (final record in _records) {
          if (record.regionId != myRegion) continue;
          final openDate = record.openDateForYear(now.year);
          if (openDate == null) continue;
          final closeDate = record.closeDateForYear(now.year, openDate);
          if (closeDate == null) continue;

          // Уведомления за 7 и 3 дня до открытия.
          // Планируем НАПЕРЁД: если дата напоминания ещё не наступила, ставим
          // уведомление сразу, чтобы оно сработало даже если приложение больше
          // не запустят (баг 12). Повторные вызовы перезаписывают тот же id.
          for (final days in [7, 3]) {
            final notify = openDate.subtract(Duration(days: days));
            if (!notify.isBefore(today)) {
              plans[_seasonNotifId(record, 'open', days)] = (
                title: 'Сезон открывается завтра',
                body: '${record.resource} / ${record.season} / ${record.species} — открытие через $days дней (${_fmtShort(openDate)}).',
                at: notify,
              );
            }
          }

          // Уведомления за 7 и 3 дня до закрытия.
          for (final days in [7, 3]) {
            final notify = closeDate.subtract(Duration(days: days));
            if (!notify.isBefore(today)) {
              plans[_seasonNotifId(record, 'close', days)] = (
                title: 'Сезон заканчивается',
                body: '${record.resource} / ${record.season} / ${record.species} — конец через $days дней (${_fmtShort(closeDate)}).',
                at: notify,
              );
            }
          }
        }
      }

      final scheduled = await _loadedScheduledIds();

      // Планируем только недостающие (уже запланированные не трогаем).
      for (final entry in plans.entries) {
        if (scheduled.contains(entry.key)) continue;
        final p = entry.value;
        await svc.scheduleNotification(
          id: entry.key,
          title: p.title,
          body: p.body,
          scheduledAt: p.at,
        );
      }

      // Снимаем устаревшие: другой регион, сброшенный выбор, прошедшие даты.
      final stale = scheduled.difference(plans.keys.toSet()).toList();
      if (stale.isNotEmpty) {
        await svc.cancelAllSeasonReminders(stale);
      }

      await _saveScheduledIds(plans.keys.toSet());
    } catch (e) {
      debugPrint('Season notifications error: $e');
    } finally {
      // Помечаем, что уведомления спланированы на сегодня — предотвращает
      // дублирование при повторных вызовах checkSeasonNotifications().
      try {
        final prefs = await SharedPreferences.getInstance();
        final todayStr = '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
        await prefs.setString(_notifsScheduledKey, todayStr);
      } catch (_) {}
    }
  }

  static int _seasonNotifId(HuntingRecord record, String type, int days) {
    final hash = '${record.regionId}_${record.resource}_${record.season}_${record.species}'.hashCode;
    // id уведомления должен укладываться в 32-битный signed int
    // ([−2^31, 2^31−1] = [−2147483648, 2147483647]), иначе zonedSchedule
    // бросает Invalid argument. Максимум формулы: base*1000 + 200 + 7.
    // Чтобы гарантированно не превышать 2147483647, сужаем base до 2 000 000:
    // 2 000 000*1000 + 207 = 2 000 000 207 < 2 147 483 647.
    final base = (hash & 0x7FFFFFFF) % 2000000;
    return base * 1000 + (type == 'open' ? 100 : 200) + days;
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