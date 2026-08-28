import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void dispose() {
    auth.removeListener(_onAuthChanged);
    theme.removeListener(_onSettingsChanged);
    regions.removeListener(_onSettingsChanged);
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _notificationsSeasons = prefs.getBool('notifications_seasons') ?? true;
      _notificationsDocuments = prefs.getBool('notifications_documents') ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_seasons', _notificationsSeasons);
      await prefs.setBool('notifications_documents', _notificationsDocuments);
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
    if (auth.isSignedIn) pushToServer();
  }

  void _onAuthChanged() {
    if (auth.isSignedIn) {
      applyFromServer();
    }
  }

  void _onSettingsChanged() {
    if (_applying) return;
    if (auth.isSignedIn) {
      pushToServer();
    }
  }

  /// Тянет настройки с сервера и применяет локально.
  Future<void> applyFromServer() async {
    final client = SupabaseService.client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      final res = await client
          .from('user_settings')
          .select('theme_mode,enabled_regions,notifications_seasons,notifications_documents')
          .eq('user_id', user.id)
          .maybeSingle();
      if (res == null) return;
      _applying = true;
      final themeMode = _parseTheme(res['theme_mode'] as String?);
      await theme.setMode(themeMode);
      final regs = _parseRegions(res['enabled_regions']);
      if (regs.isNotEmpty) {
        await regions.replaceAll(regs);
      }
      final seasons = res['notifications_seasons'];
      final documents = res['notifications_documents'];
      _notificationsSeasons =
          seasons is bool ? seasons : (res['notifications_seasons'] as bool? ?? _notificationsSeasons);
      _notificationsDocuments = documents is bool
          ? documents
          : (res['notifications_documents'] as bool? ?? _notificationsDocuments);
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
      await client.from('user_settings').upsert({
        'user_id': user.id,
        'theme_mode': theme.mode.name,
        'enabled_regions': jsonEncode(regions.enabledRegionIds),
        'notifications_seasons': _notificationsSeasons,
        'notifications_documents': _notificationsDocuments,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
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

  static List<String> _parseRegions(dynamic v) {
    if (v is String) {
      try {
        return (jsonDecode(v) as List).map((e) => e.toString()).toList();
      } catch (_) {}
    }
    return const [];
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
