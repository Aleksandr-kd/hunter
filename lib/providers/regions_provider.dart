import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/regions_repository.dart';
import '../models/region.dart';

/// Управляет включёнными регионами.
/// Бесплатно — 1 регион (свободно переключаемый), по подписке — все.
class RegionsProvider extends ChangeNotifier {
  static const _key = 'enabled_regions';

  final RegionsRepository _repository = RegionsRepository();

  List<String> _enabledRegionIds = const [];
  bool _hasUnlimited = false; // true, когда активна подписка Max (300₽)

  List<String> get enabledRegionIds => List.unmodifiable(_enabledRegionIds);
  bool get hasUnlimited => _hasUnlimited;
  int get maxRegions => _hasUnlimited ? 999 : 1;

  RegionsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabledRegionIds = prefs.getStringList(_key) ?? const [];
    if (_enabledRegionIds.isEmpty) {
      // Первый запуск — включаем Краснодарский край по умолчанию.
      _enabledRegionIds = ['krasnodar'];
      await prefs.setStringList(_key, _enabledRegionIds);
    }
    notifyListeners();
  }

  List<Region> getRegions() => _repository.getRegions();

  bool isEnabled(String id) => _enabledRegionIds.contains(id);

  /// Включает регион. Возвращает предупреждение, если надо отключить другой
  /// (бесплатная версия) или выйти на премиум.
  /// Возвращает true, если включение выполнено.
  Future<bool> toggleRegion(String id) async {
    final prefs = await SharedPreferences.getInstance();
    if (isEnabled(id)) {
      _enabledRegionIds = _enabledRegionIds.where((e) => e != id).toList();
    } else if (_enabledRegionIds.length < maxRegions) {
      _enabledRegionIds = [..._enabledRegionIds, id];
    } else {
      return false; // лимит достигнут — обработка в UI (переключение/премиум)
    }
    await prefs.setStringList(_key, _enabledRegionIds);
    notifyListeners();
    return true;
  }

  Future<void> setUnlimited(bool value) async {
    _hasUnlimited = value;
    notifyListeners();
  }

  /// Первый включённый регион (для показа в Сезонах).
  Region? get activeRegion {
    if (_enabledRegionIds.isEmpty) return null;
    return _repository.getRegion(_enabledRegionIds.first);
  }
}