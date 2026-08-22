/// Единый источник текущего тарифа (должен быть в провайдере).
/// Позволяет Diary/Regions читать уровень без циклических зависимостей.
class TierManager {
  static String tier = 'none'; // none | premium | max

  static bool get isUnlimited => tier != 'none';
  static bool get isMax => tier == 'max';
  static bool get isPremium => tier == 'premium' || tier == 'max';
}