import 'package:flutter_test/flutter_test.dart';
import 'package:pomoshchnik_okhotnika/models/diary_entry.dart';
import 'package:pomoshchnik_okhotnika/services/analytics_service.dart';

void main() {
  group('AnalyticsService — Summary metrics', () {
    test('totalEntries returns correct count', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Заяц'),
        DiaryEntry(date: DateTime(2024, 1, 3), species: 'Кабан'),
      ];
      expect(AnalyticsService.totalEntries(entries), 3);
    });

    test('speciesCount returns unique species count', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Заяц'),
        DiaryEntry(date: DateTime(2024, 1, 3), species: 'Кабан'),
      ];
      expect(AnalyticsService.speciesCount(entries), 2);
    });

    test('entriesWithLocation counts entries with location', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан', location: 'Лес 1'),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Заяц'),
        DiaryEntry(date: DateTime(2024, 1, 3), species: 'Кабан', location: 'Лес 2'),
      ];
      expect(AnalyticsService.entriesWithLocation(entries), 2);
    });

    test('entriesWithPhoto counts entries with photo', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан', photoPath: '/photo1.jpg'),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Заяц'),
        DiaryEntry(date: DateTime(2024, 1, 3), species: 'Кабан', photoPath: '/photo2.jpg'),
      ];
      expect(AnalyticsService.entriesWithPhoto(entries), 2);
    });
  });

  group('AnalyticsService — Trend calculation', () {
    test('returns zero trend for empty entries', () {
      final trend = AnalyticsService.calculateTrend([]);
      expect(trend.currentCount, 0);
      expect(trend.previousCount, 0);
      expect(trend.percentChange, 0);
    });

    test('calculates growing trend', () {
      final now = DateTime.now();
      final entries = [
        DiaryEntry(date: now.subtract(const Duration(days: 30)), species: 'Кабан'),
        DiaryEntry(date: now.subtract(const Duration(days: 20)), species: 'Кабан'),
        DiaryEntry(date: now.subtract(const Duration(days: 10)), species: 'Заяц'),
        DiaryEntry(date: now.subtract(const Duration(days: 5)), species: 'Кабан'),
      ];
      final trend = AnalyticsService.calculateTrend(entries);
      expect(trend.isGrowing, true);
      expect(trend.percentChange, greaterThan(0));
    });

    test('calculates declining trend', () {
      final now = DateTime.now();
      // Больше записей в предыдущем периоде (3-6 месяцев назад), чем в текущем
      final entries = [
        DiaryEntry(date: now.subtract(const Duration(days: 150)), species: 'Кабан'),
        DiaryEntry(date: now.subtract(const Duration(days: 140)), species: 'Кабан'),
        DiaryEntry(date: now.subtract(const Duration(days: 130)), species: 'Заяц'),
        DiaryEntry(date: now.subtract(const Duration(days: 120)), species: 'Кабан'),
        DiaryEntry(date: now.subtract(const Duration(days: 110)), species: 'Кабан'),
        DiaryEntry(date: now.subtract(const Duration(days: 100)), species: 'Кабан'),
        DiaryEntry(date: now.subtract(const Duration(days: 90)), species: 'Заяц'),
        DiaryEntry(date: now.subtract(const Duration(days: 80)), species: 'Кабан'),
        DiaryEntry(date: now.subtract(const Duration(days: 70)), species: 'Кабан'),
        DiaryEntry(date: now.subtract(const Duration(days: 60)), species: 'Кабан'),
      ];
      final trend = AnalyticsService.calculateTrend(entries);
      expect(trend.isDeclining, true);
      expect(trend.percentChange, lessThan(0));
    });

    test('calculates stable trend', () {
      // Тестируем с фиксированными датами — 2 записей в предыдущем периоде, 2 в текущем
      final now = DateTime.now();
      final currentPeriodStart = DateTime(now.year, now.month - 2, 1);
      final previousPeriodStart = DateTime(now.year, now.month - 5, 1);
      
      // Создаём записи, которые точно попадают в периоды
      final prevDate1 = previousPeriodStart.add(const Duration(days: 10));
      final prevDate2 = previousPeriodStart.add(const Duration(days: 30));
      final currDate1 = currentPeriodStart.add(const Duration(days: 10));
      final currDate2 = currentPeriodStart.add(const Duration(days: 30));
      
      final entries = [
        DiaryEntry(date: prevDate1, species: 'Кабан'),
        DiaryEntry(date: prevDate2, species: 'Заяц'),
        DiaryEntry(date: currDate1, species: 'Кабан'),
        DiaryEntry(date: currDate2, species: 'Заяц'),
      ];
      final trend = AnalyticsService.calculateTrend(entries);
      expect(trend.isStable, true);
      expect(trend.percentChange, 0);
    });
  });

  group('AnalyticsService — Month distribution', () {
    test('returns correct month distribution', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 15), species: 'Заяц'),
        DiaryEntry(date: DateTime(2024, 3, 1), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 3, 15), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 3, 20), species: 'Заяц'),
      ];
      final distribution = AnalyticsService.monthDistribution(entries);
      expect(distribution['Янв'], 2);
      expect(distribution['Мар'], 3);
      expect(distribution.length, 2);
    });

    test('returns empty map for empty entries', () {
      final distribution = AnalyticsService.monthDistribution([]);
      expect(distribution, isEmpty);
    });
  });

  group('AnalyticsService — Species distribution', () {
    test('returns correct species distribution', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Заяц'),
        DiaryEntry(date: DateTime(2024, 1, 3), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 4), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 5), species: 'Заяц'),
      ];
      final distribution = AnalyticsService.speciesDistribution(entries);
      expect(distribution['Кабан'], 3);
      expect(distribution['Заяц'], 2);
    });

    test('skips empty species', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 2), species: ''),
        DiaryEntry(date: DateTime(2024, 1, 3), species: 'Заяц'),
      ];
      final distribution = AnalyticsService.speciesDistribution(entries);
      expect(distribution.containsKey(''), false);
      expect(distribution.length, 2);
    });
  });

  group('AnalyticsService — Weight stats', () {
    test('returns zero stats when no weights', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Заяц'),
      ];
      final stats = AnalyticsService.calculateWeightStats(entries);
      expect(stats.hasData, false);
      expect(stats.total, 0);
      expect(stats.average, 0);
      expect(stats.max, null);
      expect(stats.entriesWithWeight, 0);
    });

    test('calculates correct weight stats', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан', weight: 85.5),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Заяц', weight: 5.0),
        DiaryEntry(date: DateTime(2024, 1, 3), species: 'Кабан', weight: 92.0),
      ];
      final stats = AnalyticsService.calculateWeightStats(entries);
      expect(stats.hasData, true);
      expect(stats.total, 182.5);
      expect(stats.average, 60.833333333333336);
      expect(stats.max, 92.0);
      expect(stats.entriesWithWeight, 3);
    });
  });

  group('AnalyticsService — Top species', () {
    test('returns sorted top species', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 3), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 4), species: 'Заяц'),
        DiaryEntry(date: DateTime(2024, 1, 5), species: 'Заяц'),
        DiaryEntry(date: DateTime(2024, 1, 6), species: 'Лось'),
      ];
      final top = AnalyticsService.getTopSpecies(entries, limit: 3);
      expect(top.length, 3);
      expect(top[0].species, 'Кабан');
      expect(top[0].count, 3);
      expect(top[0].percentage, 50.0);
      expect(top[1].species, 'Заяц');
      expect(top[1].count, 2);
      expect(top[2].species, 'Лось');
      expect(top[2].count, 1);
    });

    test('respects limit parameter', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Заяц'),
        DiaryEntry(date: DateTime(2024, 1, 3), species: 'Лось'),
      ];
      final top = AnalyticsService.getTopSpecies(entries, limit: 2);
      expect(top.length, 2);
    });

    test('returns empty list for empty entries', () {
      final top = AnalyticsService.getTopSpecies([]);
      expect(top, isEmpty);
    });
  });

  group('AnalyticsService — Season distribution', () {
    test('returns correct season distribution', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 3, 15), species: 'Кабан'), // Весна
        DiaryEntry(date: DateTime(2024, 4, 1), species: 'Заяц'),   // Весна
        DiaryEntry(date: DateTime(2024, 6, 20), species: 'Кабан'), // Лето
        DiaryEntry(date: DateTime(2024, 9, 10), species: 'Кабан'), // Осень
        DiaryEntry(date: DateTime(2024, 10, 5), species: 'Заяц'),  // Осень
        DiaryEntry(date: DateTime(2024, 12, 25), species: 'Кабан'), // Зима
      ];
      final distribution = AnalyticsService.seasonDistribution(entries);
      expect(distribution['Весна'], 2);
      expect(distribution['Лето'], 1);
      expect(distribution['Осень'], 2);
      expect(distribution['Зима'], 1);
    });

    test('returns zero counts for empty entries', () {
      final distribution = AnalyticsService.seasonDistribution([]);
      expect(distribution['Весна'], 0);
      expect(distribution['Лето'], 0);
      expect(distribution['Осень'], 0);
      expect(distribution['Зима'], 0);
    });
  });

  group('AnalyticsService — Smart insights', () {
    test('returns empty list for empty entries', () {
      final insights = AnalyticsService.generateInsights([]);
      expect(insights, isEmpty);
    });

    test('generates top species insight', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 3), species: 'Заяц'),
      ];
      final insights = AnalyticsService.generateInsights(entries);
      expect(insights.any((i) => i.title == 'Любимая добыча'), true);
    });

    test('generates weight insight when weights exist', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан', weight: 85.5),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Заяц', weight: 5.0),
      ];
      final insights = AnalyticsService.generateInsights(entries);
      expect(insights.any((i) => i.title == 'Статистика по весу'), true);
    });

    test('generates season insight', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 9, 10), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 10, 5), species: 'Заяц'),
        DiaryEntry(date: DateTime(2024, 10, 15), species: 'Кабан'),
      ];
      final insights = AnalyticsService.generateInsights(entries);
      expect(insights.any((i) => i.title == 'Лучший сезон'), true);
    });

    test('generates location insight for multiple locations', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан', location: 'Лес 1'),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Заяц', location: 'Лес 2'),
        DiaryEntry(date: DateTime(2024, 1, 3), species: 'Кабан', location: 'Лес 3'),
      ];
      final insights = AnalyticsService.generateInsights(entries);
      expect(insights.any((i) => i.title == 'Исследователь'), true);
    });

    test('generates photo insight', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан', photoPath: '/photo1.jpg'),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Заяц', photoPath: '/photo2.jpg'),
        DiaryEntry(date: DateTime(2024, 1, 3), species: 'Кабан'),
      ];
      final insights = AnalyticsService.generateInsights(entries);
      expect(insights.any((i) => i.title == 'Фотоотчёт'), true);
    });

    test('generates warning for inactivity', () {
      final entries = [
        DiaryEntry(date: DateTime.now().subtract(const Duration(days: 60)), species: 'Кабан'),
      ];
      final insights = AnalyticsService.generateInsights(entries);
      expect(insights.any((i) => i.type == InsightType.warning), true);
    });

    test('limits insights to 5', () {
      final entries = List.generate(20, (i) {
        return DiaryEntry(
          date: DateTime(2024, (i % 12) + 1, 1),
          species: i % 3 == 0 ? 'Кабан' : i % 3 == 1 ? 'Заяц' : 'Лось',
          weight: 50.0 + i,
          location: 'Лес $i',
          photoPath: i % 2 == 0 ? '/photo$i.jpg' : null,
        );
      });
      final insights = AnalyticsService.generateInsights(entries);
      expect(insights.length, lessThanOrEqualTo(5));
    });
  });

  group('AnalyticsService — Achievements', () {
    test('unlocks first achievement at 1 entry', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан'),
      ];
      final achievements = AnalyticsService.checkAchievements(entries);
      expect(achievements.first.unlocked, true);
      expect(achievements.first.title, 'Первый шаг');
    });

    test('unlocks weight achievement when weight exists', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан', weight: 85.5),
      ];
      final achievements = AnalyticsService.checkAchievements(entries);
      expect(achievements.any((a) => a.title == 'Первый трофей' && a.unlocked), true);
    });

    test('unlocks species achievements at thresholds', () {
      final entries = [
        DiaryEntry(date: DateTime(2024, 1, 1), species: 'Кабан'),
        DiaryEntry(date: DateTime(2024, 1, 2), species: 'Заяц'),
        DiaryEntry(date: DateTime(2024, 1, 3), species: 'Лось'),
        DiaryEntry(date: DateTime(2024, 1, 4), species: 'Косуля'),
        DiaryEntry(date: DateTime(2024, 1, 5), species: 'Олень'),
        DiaryEntry(date: DateTime(2024, 1, 6), species: 'Медведь'),
        DiaryEntry(date: DateTime(2024, 1, 7), species: 'Рысь'),
        DiaryEntry(date: DateTime(2024, 1, 8), species: 'Собака'),
        DiaryEntry(date: DateTime(2024, 1, 9), species: 'Кошка'),
        DiaryEntry(date: DateTime(2024, 1, 10), species: 'Кролик'),
      ];
      final achievements = AnalyticsService.checkAchievements(entries);
      expect(achievements.any((a) => a.title == 'Коллекционер видов' && a.unlocked), true);
      expect(achievements.any((a) => a.title == 'Знаток природы' && a.unlocked), true);
    });

    test('unlocks location achievements at thresholds', () {
      final entries = List.generate(10, (i) {
        return DiaryEntry(
          date: DateTime(2024, 1, i + 1),
          species: 'Кабан',
          location: 'Лес $i',
        );
      });
      final achievements = AnalyticsService.checkAchievements(entries);
      expect(achievements.any((a) => a.title == 'Исследователь' && a.unlocked), true);
      expect(achievements.any((a) => a.title == 'Путешественник' && a.unlocked), true);
    });

    test('unlocks photo achievement at 10 photos', () {
      final entries = List.generate(10, (i) {
        return DiaryEntry(
          date: DateTime(2024, 1, i + 1),
          species: 'Кабан',
          photoPath: '/photo$i.jpg',
        );
      });
      final achievements = AnalyticsService.checkAchievements(entries);
      expect(achievements.any((a) => a.title == 'Фотоохотник' && a.unlocked), true);
    });

    test('returns all locked for empty entries', () {
      final achievements = AnalyticsService.checkAchievements([]);
      expect(achievements.every((a) => !a.unlocked), true);
    });

    test('returns correct number of achievements', () {
      final achievements = AnalyticsService.checkAchievements([]);
      expect(achievements.length, 10);
    });
  });
}
