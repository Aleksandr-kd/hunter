/// Общие ключи SharedPreferences для синхронизируемых настроек.
/// Единый источник — чтобы исключить рассинхрон ключей-строк между
/// провайдерами (SettingsSyncProvider пишет, SeasonsProvider читает).
class PrefsKeys {
  PrefsKeys._();

  static const notificationsSeasons = 'notifications_seasons';
  static const notificationsDocuments = 'notifications_documents';
}
