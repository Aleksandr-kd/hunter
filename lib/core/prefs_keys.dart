/// Общие ключи SharedPreferences для синхронизируемых настроек.
/// Единый источник — чтобы исключить рассинхрон ключей-строк между
/// провайдерами (SettingsSyncProvider пишет, SeasonsProvider читает).
class PrefsKeys {
  PrefsKeys._();

  static const notificationsSeasons = 'notifications_seasons';
  static const notificationsDocuments = 'notifications_documents';

  /// «Мой регион» для уведомлений о сезонах (пустая строка = не выбран).
  static const seasonsMyRegion = 'seasons_my_region';

  /// Список id запланированных уведомлений о сезонах (для отмены устаревших).
  static const seasonNotifIds = 'seasons_notif_ids';
}
