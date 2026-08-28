import 'package:flutter/material.dart';

import '../models/diary_entry.dart';

// ============================================================
// AnalyticsService — расчёт всех метрик для статистики
// ============================================================

/// Информация о тренде (сравнение двух периодов).
class TrendInfo {
  final int currentCount;
  final int previousCount;
  final double percentChange; // положительный = рост, отрицательный = падение

  const TrendInfo({
    required this.currentCount,
    required this.previousCount,
    required this.percentChange,
  });

  bool get isGrowing => percentChange > 0;
  bool get isDeclining => percentChange < 0;
  bool get isStable => percentChange == 0;

  String get arrow => isGrowing ? '↑' : isDeclining ? '↓' : '—';
  String get percentText => '${percentChange.abs().toStringAsFixed(0)}%';
}

/// Статистика по весу.
class WeightStats {
  final double total;
  final double average;
  final double? max;
  final int entriesWithWeight;

  const WeightStats({
    required this.total,
    required this.average,
    required this.max,
    required this.entriesWithWeight,
  });

  bool get hasData => entriesWithWeight > 0;
}

/// Элемент рейтинга видов.
class TopSpecies {
  final String species;
  final int count;
  final double percentage;

  const TopSpecies({
    required this.species,
    required this.count,
    required this.percentage,
  });
}

/// Элемент рейтинга локаций.
class TopLocation {
  final String location;
  final int count;

  const TopLocation({
    required this.location,
    required this.count,
  });
}

/// Тип инсайта для определения цвета иконки.
enum InsightType {
  info,      // синий
  achievement, // янтарный
  tip,       // зелёный
  warning,   // красный
}

/// Один умный инсайт.
class Insight {
  final String title;
  final String description;
  final IconData icon;
  final InsightType type;

  const Insight({
    required this.title,
    required this.description,
    required this.icon,
    required this.type,
  });
}

/// Достижение (бейдж).
class Achievement {
  final String title;
  final String description;
  final IconData icon;
  final bool unlocked;

  const Achievement({
    required this.title,
    required this.description,
    required this.icon,
    required this.unlocked,
  });
}

class AnalyticsService {
  AnalyticsService._(); // static-only

  // ============================================================
  // Summary metrics
  // ============================================================

  static int totalEntries(List<DiaryEntry> entries) => entries.length;

  static int speciesCount(List<DiaryEntry> entries) =>
      entries.map((e) => e.species).where((s) => s.isNotEmpty).toSet().length;

  static int entriesWithLocation(List<DiaryEntry> entries) =>
      entries.where((e) => e.location != null).length;

  static int entriesWithPhoto(List<DiaryEntry> entries) =>
      entries.where((e) => e.photoPath != null).length;

  // ============================================================
  // Trend calculation (last 3 months vs previous 3 months)
  // ============================================================

  static TrendInfo calculateTrend(List<DiaryEntry> entries) {
    if (entries.isEmpty) {
      return const TrendInfo(
        currentCount: 0,
        previousCount: 0,
        percentChange: 0,
      );
    }

    final now = DateTime.now();
    final currentPeriodStart = DateTime(now.year, now.month - 2, 1);
    final previousPeriodStart =
        DateTime(now.year, now.month - 5, 1);
    final previousPeriodEnd = DateTime(now.year, now.month - 3, 0);

    int currentCount = 0;
    int previousCount = 0;

    for (final entry in entries) {
      if (entry.date.isAfter(currentPeriodStart.subtract(const Duration(days: 1)))) {
        currentCount++;
      } else if (entry.date.isAfter(previousPeriodStart.subtract(const Duration(days: 1))) &&
          entry.date.isBefore(previousPeriodEnd)) {
        previousCount++;
      }
    }

    double percentChange = 0;
    if (previousCount > 0) {
      percentChange = ((currentCount - previousCount) / previousCount) * 100;
    } else if (currentCount > 0) {
      percentChange = 100.0;
    }

    return TrendInfo(
      currentCount: currentCount,
      previousCount: previousCount,
      percentChange: percentChange.roundToDouble(),
    );
  }

  // ============================================================
  // Month distribution (for line chart)
  // ============================================================

  static Map<String, int> monthDistribution(List<DiaryEntry> entries) {
    const monthNames = [
      '', 'Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн',
      'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек',
    ];
    final Map<String, int> map = {};

    for (final entry in entries) {
      final key = monthNames[entry.date.month];
      map[key] = (map[key] ?? 0) + 1;
    }

    // Упорядочиваем по месяцу (только заполненные, в хронологическом порядке).
    final ordered = <String, int>{};
    for (final name in monthNames.skip(1)) {
      if (map.containsKey(name)) ordered[name] = map[name]!;
    }
    return ordered;
  }

  // ============================================================
  // Species distribution (for pie chart)
  // ============================================================

  static Map<String, int> speciesDistribution(List<DiaryEntry> entries) {
    final Map<String, int> map = {};
    for (final entry in entries) {
      if (entry.species.isEmpty) continue;
      map[entry.species] = (map[entry.species] ?? 0) + 1;
    }
    return map;
  }

  // ============================================================
  // Weight stats
  // ============================================================

  static WeightStats calculateWeightStats(List<DiaryEntry> entries) {
    final weights =
        entries.map((e) => e.weight).whereType<double>().toList();

    if (weights.isEmpty) {
      return const WeightStats(
        total: 0,
        average: 0,
        max: null,
        entriesWithWeight: 0,
      );
    }

    final total = weights.fold<double>(0, (sum, w) => sum + w);
    final average = total / weights.length;
    final max = weights.reduce((a, b) => a > b ? a : b);

    return WeightStats(
      total: total,
      average: average,
      max: max,
      entriesWithWeight: weights.length,
    );
  }

  // ============================================================
  // Top species leaderboard
  // ============================================================

  static List<TopSpecies> getTopSpecies(
    List<DiaryEntry> entries, {
    int limit = 5,
  }) {
    final speciesMap = speciesDistribution(entries);
    if (speciesMap.isEmpty) return [];

    final total = entries.length;
    final sorted = speciesMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(limit).map((entry) {
      return TopSpecies(
        species: entry.key,
        count: entry.value,
        percentage: total > 0 ? (entry.value / total * 100) : 0,
      );
    }).toList();
  }

  // ============================================================
  // Season comparison
  // ============================================================

  static Map<String, int> seasonDistribution(List<DiaryEntry> entries) {
    final Map<String, int> map = {
      'Весна': 0,
      'Лето': 0,
      'Осень': 0,
      'Зима': 0,
    };

    for (final entry in entries) {
      final month = entry.date.month;
      if (month >= 3 && month <= 5) {
        map['Весна'] = (map['Весна']!) + 1;
      } else if (month >= 6 && month <= 8) {
        map['Лето'] = (map['Лето']!) + 1;
      } else if (month >= 9 && month <= 11) {
        map['Осень'] = (map['Осень']!) + 1;
      } else {
        map['Зима'] = (map['Зима']!) + 1;
      }
    }

    return map;
  }

  // ============================================================
  // Top locations
  // ============================================================

  static List<TopLocation> getTopLocations(
    List<DiaryEntry> entries, {
    int limit = 5,
  }) {
    final Map<String, int> map = {};
    for (final entry in entries) {
      if (entry.location == null || entry.location!.isEmpty) continue;
      map[entry.location!] = (map[entry.location!] ?? 0) + 1;
    }

    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(limit).map((entry) {
      return TopLocation(
        location: entry.key,
        count: entry.value,
      );
    }).toList();
  }

  // ============================================================
  // Smart insights generation
  // ============================================================

  static List<Insight> generateInsights(List<DiaryEntry> entries) {
    final List<Insight> insights = [];

    if (entries.isEmpty) return insights;

    // 1. Top species insight
    final topSpeciesMap = speciesDistribution(entries);
    if (topSpeciesMap.isNotEmpty) {
      final topEntry = topSpeciesMap.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );
      insights.add(const Insight(
        title: 'Любимая добыча',
        description:
            'Вы чаще всего охотитесь на «${topEntry.key}» — ${topEntry.value} записей.',
        icon: Icons.pets,
        type: InsightType.info,
      ));
    }

    // 2. Weight insight
    final weightStats = calculateWeightStats(entries);
    if (weightStats.hasData) {
      insights.add(Insight(
        title: 'Статистика по весу',
        description:
            'Средний вес — ${weightStats.average.toStringAsFixed(1)} кг, '
            'максимальный — ${weightStats.max!.toStringAsFixed(0)} кг. '
            'Общий улов — ${weightStats.total.toStringAsFixed(0)} кг.',
        icon: Icons.scale,
        type: InsightType.info,
      ));
    }

    // 3. Season insight
    final seasonMap = seasonDistribution(entries);
    if (seasonMap.isNotEmpty) {
      final topSeason = seasonMap.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );
      if (topSeason.value > 0) {
        insights.add(Insight(
          title: 'Лучший сезон',
          description:
              'Больше всего записей — $topSeason (${topSeason.value} записей).',
          icon: Icons.calendar_month,
          type: InsightType.tip,
        ));
      }
    }

    // 4. Location insight
    final uniqueLocations =
        entries.map((e) => e.location).whereType<String>().toSet();
    if (uniqueLocations.length >= 3) {
      insights.add(Insight(
        title: 'Исследователь',
        description:
            'Вы посетили ${uniqueLocations.length} уникальных мест.',
        icon: Icons.explore,
        type: InsightType.info,
      ));
    }

    // 5. Photo insight
    final withPhoto = entriesWithPhoto(entries);
    if (withPhoto > 0) {
      final percent = (withPhoto / entries.length * 100).toStringAsFixed(0);
      insights.add(Insight(
        title: 'Фотоотчёт',
        description:
            '$withPhoto записей с фото — ${percent}% от всех.',
        icon: Icons.photo_camera,
        type: InsightType.tip,
      ));
    }

    // 6. Inactivity warning
    if (entries.isNotEmpty) {
      final lastEntry = entries.reduce(
        (a, b) => a.date.isAfter(b.date) ? a : b,
      );
      final daysSinceLast = DateTime.now().difference(lastEntry.date).inDays;
      if (daysSinceLast > 30) {
        insights.add(Insight(
          title: 'Время охоты!',
          description:
              'Вы не добавляли записи $daysSinceLast дней. '
              'Сезон открыт — пора!',
          icon: Icons.hunting,
          type: InsightType.warning,
        ));
      }
    }

    // 7. Result insight
    final hunted = entries.where((e) => e.result == 'добыто').length;
    final observed = entries.where((e) => e.result == 'наблюдение').length;
    if (hunted > 0 && observed > 0) {
      insights.add(Insight(
        title: 'Баланс',
        description:
            'Добыто: $hunted, Наблюдений: $observed.',
        icon: Icons.balance,
        type: InsightType.info,
      ));
    }

    return insights.take(5).toList(); // максимум 5 инсайтов
  }

  // ============================================================
  // Achievements check
  // ============================================================

  static List<Achievement> checkAchievements(List<DiaryEntry> entries) {
    final total = entries.length;
    final speciesSet =
        entries.map((e) => e.species).where((s) => s.isNotEmpty).toSet();
    final locations =
        entries.map((e) => e.location).whereType<String>().toSet();
    final withWeight = entries.where((e) => e.weight != null).length;
    final withPhoto = entries.where((e) => e.photoPath != null).length;
    final withLocation =
        entries.where((e) => e.location != null).length;

    return [
      Achievement(
        title: 'Первый шаг',
        description: 'Добавлена первая запись',
        icon: Icons.flag,
        unlocked: total >= 1,
      ),
      Achievement(
        title: 'Охотничий стаж',
        description: '10 записей в дневнике',
        icon: Icons.menu_book,
        unlocked: total >= 10,
      ),
      Achievement(
        title: 'Ветеран охоты',
        description: '50 записей в дневнике',
        icon: Icons.emoji_events,
        unlocked: total >= 50,
      ),
      Achievement(
        title: 'Мастер дикой природы',
        description: '100 записей в дневнике',
        icon: Icons.military_tech,
        unlocked: total >= 100,
      ),
      Achievement(
        title: 'Первый трофей',
        description: 'Добавлена запись с весом',
        icon: Icons.scale,
        unlocked: withWeight >= 1,
      ),
      Achievement(
        title: 'Коллекционер видов',
        description: '5 разных видов',
        icon: Icons.pets,
        unlocked: speciesSet.length >= 5,
      ),
      Achievement(
        title: 'Знаток природы',
        description: '10 разных видов',
        icon: Icons.biotech,
        unlocked: speciesSet.length >= 10,
      ),
      Achievement(
        title: 'Исследователь',
        description: '5 уникальных мест',
        icon: Icons.place,
        unlocked: locations.length >= 5,
      ),
      Achievement(
        title: 'Путешественник',
        description: '10 уникальных мест',
        icon: Icons.flight,
        unlocked: locations.length >= 10,
      ),
      Achievement(
        title: 'Фотоохотник',
        description: '10 записей с фото',
        icon: Icons.photo_camera,
        unlocked: withPhoto >= 10,
      ),
    ];
  }
}
