import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs_keys.dart';
import '../services/supabase_service.dart';
import '../theme/theme_provider.dart';
import 'auth_provider.dart';
import 'diary_provider.dart';
import 'document_provider.dart';
import 'regions_provider.dart';
import 'seasons_provider.dart';

/// Синхронизация настроек (тема, регионы, уведомления) с сервером
/// для мульти-устройств.
class SettingsSyncProvider extends ChangeNotifier {
  final ThemeProvider theme;
  final RegionsProvider regions;
  final AuthProvider auth;

  bool _notificationsSeasons = true;
  bool _notificationsDocuments = true;
  bool get notificationsSeasons => _notificationsSeasons;
  bool get notificationsDocuments => _notificationsDocuments;

  SettingsSyncProvider({
    required this.theme,
    required this.regions,
    required this.auth,
  }) {
    auth.addListener(_onAuthChanged);
    theme.addListener(_onSettingsChanged);
    regions.addListener(_onSettingsChanged);
    _loadNotifications();
  }

  bool _applying = false;
  // M3: debounce записи настроек на сервер — быстрые переключения темы /
  // регионов / уведомлений не должны спамить upsert (по одному на каждое
  // изменение). Таймер сбрасывается при новом изменении — сервер пишется
  // один раз после серии изменений.
  Timer? _pushDebounce;
  static const _pushDebounceDuration = Duration(milliseconds: 400);

  @override
  void dispose() {
    auth.removeListener(_onAuthChanged);
    theme.removeListener(_onSettingsChanged);
    regions.removeListener(_onSettingsChanged);
    _pushDebounce?.cancel();
    _pushDebounce = null;
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _notificationsSeasons = prefs.getBool(PrefsKeys.notificationsSeasons) ?? true;
      _notificationsDocuments = prefs.getBool(PrefsKeys.notificationsDocuments) ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.notificationsSeasons, _notificationsSeasons);
      await prefs.setBool(PrefsKeys.notificationsDocuments, _notificationsDocuments);
    } catch (_) {}
  }

  void setNotifications({
    bool? seasons,
    bool? documents,
  }) {
    if (seasons != null) _notificationsSeasons = seasons;
    if (documents != null) _notificationsDocuments = documents;
    _saveNotifications();
    notifyListeners();
    if (auth.isSignedIn) _schedulePush();
  }

  void _onAuthChanged() {
    if (auth.isSignedIn) {
      applyFromServer();
    }
  }

  void _onSettingsChanged() {
    if (_applying) return;
    if (auth.isSignedIn) {
      _schedulePush();
    }
  }

  /// Планирует запись настроек на сервер с debounce (M3) — серия быстрых
  /// изменений схлопывается в один upsert.
  void _schedulePush() {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(_pushDebounceDuration, () {
      unawaited(pushToServer());
    });
  }

  /// Тянет настройки с сервера и применяет локально.
  Future<void> applyFromServer() async {
    final client = SupabaseService.client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      _applying = true;
      // Тема и регионы — в одном запросе (эти колонки есть всегда).
      final base = await client
          .from('user_settings')
          .select('theme_mode,enabled_regions')
          .eq('user_id', user.id)
          .maybeSingle();
      if (base != null) {
        final themeMode = _parseTheme(base['theme_mode'] as String?);
        await theme.setMode(themeMode);
        final regs = _parseRegions(base['enabled_regions']);
        // Применяем только если с сервера пришла валидная настройка списка
        // регионов (в т.ч. пустая — когда все регионы выключены на другом
        // устройстве). Если данных нет (null/не JSON) — не трогаем локальную.
        if (regs != null) {
          await regions.replaceAll(regs);
        }
      }
      // Колонки уведомлений появились миграцией 0006 и могут отсутствовать
      // на сервере, поэтому читаем их отдельно и устойчиво (fallback).
      try {
        final notif = await client
            .from('user_settings')
            .select('notifications_seasons,notifications_documents')
            .eq('user_id', user.id)
            .maybeSingle();
        if (notif != null) {
          final seasons = notif['notifications_seasons'];
          final documents = notif['notifications_documents'];
          _notificationsSeasons =
              seasons is bool ? seasons : (notif['notifications_seasons'] as bool? ?? _notificationsSeasons);
          _notificationsDocuments = documents is bool
              ? documents
              : (notif['notifications_documents'] as bool? ?? _notificationsDocuments);
        }
      } catch (e) {
        debugPrint('Apply notifications settings skipped (migration 0006?): $e');
      }
      await _saveNotifications();
      notifyListeners();
    } catch (e) {
      debugPrint('Apply settings error: $e');
    } finally {
      _applying = false;
      notifyListeners();
    }
  }

  /// Пишет текущие настройки на сервер.
  Future<void> pushToServer() async {
    final client = SupabaseService.client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      // Единый upsert: все настройки одной строкой за один вызов — исключает
      // частичную синхронизацию (тема обновилась, уведомления — нет).
      try {
        await client.from('user_settings').upsert({
          'user_id': user.id,
          'theme_mode': theme.mode.name,
          'enabled_regions': jsonEncode(regions.enabledRegionIds),
          'notifications_seasons': _notificationsSeasons,
          'notifications_documents': _notificationsDocuments,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id');
      } catch (e) {
        // Колонок уведомлений может не быть на старом сервере (до миграции 0006) —
        // пишем базовые поля отдельно, уведомления — устойчиво с fallback.
        debugPrint('push settings (single upsert) failed, fallback: $e');
        await client.from('user_settings').upsert({
          'user_id': user.id,
          'theme_mode': theme.mode.name,
          'enabled_regions': jsonEncode(regions.enabledRegionIds),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id');
        try {
          await client.from('user_settings').upsert({
            'user_id': user.id,
            'notifications_seasons': _notificationsSeasons,
            'notifications_documents': _notificationsDocuments,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id');
        } catch (e2) {
          debugPrint('push notifications settings skipped (migration 0006?): $e2');
        }
      }
    } catch (e) {
      debugPrint('push settings error: $e');
    }
  }

  static ThemeMode _parseTheme(String? v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// Разбирает список регионов с сервера.
  /// Возвращает null, если данных нет (колонка null или не JSON) — в этом
  /// случае локальную настройку трогать не нужно.
  static List<String>? _parseRegions(dynamic v) {
    if (v is String) {
      try {
        return (jsonDecode(v) as List).map((e) => e.toString()).toList();
      } catch (_) {}
      return null; // не JSON — данных нет
    }
    if (v is List) {
      return v.map((e) => e.toString()).toList();
    }
    return null;
  }

  /// Глобальная синхронизация всех данных приложения.
  static Future<void> syncAll({
    required DiaryProvider diary,
    required DocumentProvider documents,
    required SeasonsProvider seasons,
    required AuthProvider auth,
    required ThemeProvider theme,
    required RegionsProvider regions,
    required SettingsSyncProvider settings,
  }) async {
    // Синхронизируем дневник (pull + push).
    if (auth.isSignedIn) {
      await diary.syncWithServer();
    }

    // Синхронизируем документы (даты истечения).
    if (auth.isSignedIn) {
      await documents.syncWithServer();
    }

    // Обновляем сроки охоты.
    await seasons.refresh();

    // Обновляем подписку.
    await auth.loadSubscription();

    // Применяем настройки с сервера (тема, регионы, уведомления).
    if (auth.isSignedIn) {
      await settings.applyFromServer();
    }
  }
}
