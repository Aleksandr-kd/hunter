import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/diary_provider.dart';
import '../services/analytics_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/stats_widgets.dart';

/// Экран «Статистика и данные»: метрики, умные подсказки, графики.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  @override
  Widget build(BuildContext context) {
    final diary = context.watch<DiaryProvider>();
    context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Статистика и данные')),
      body: !diary.loaded
          ? const SkeletonStatsScreen()
          : RefreshIndicator(
              onRefresh: () => diary.load(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _summaryCards(context, diary),
                  const SizedBox(height: 16),
                  SmartInsightsCard(
                    insights: AnalyticsService.generateInsights(diary.entries),
                  ),
                  const SizedBox(height: 16),
                  ..._analyticsSection(context, diary),
                ],
              ),
            ),
    );
  }

  Widget _summaryCards(BuildContext context, DiaryProvider diary) {
    final entries = diary.entries;
    final species =
        entries.map((e) => e.species).where((s) => s.isNotEmpty).toSet();
    final withLocation = entries.where((e) => e.location != null).length;
    final withPhoto = entries.where((e) => e.photoPath != null).length;
    final trend = AnalyticsService.calculateTrend(entries);

    return GlassCard(
      tint: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ваша статистика',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedStatCard(
                  icon: Icons.menu_book,
                  label: 'записей',
                  endValue: entries.length,
                  trend: trend,
                ),
                AnimatedStatCard(
                  icon: Icons.pets,
                  label: 'видов',
                  endValue: species.length,
                ),
                AnimatedStatCard(
                  icon: Icons.place,
                  label: 'с гео',
                  endValue: withLocation,
                ),
                AnimatedStatCard(
                  icon: Icons.photo,
                  label: 'с фото',
                  endValue: withPhoto,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _analyticsSection(BuildContext context, DiaryProvider diary) {
    final entries = diary.entries;
    if (entries.isEmpty) {
      return [
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Добавьте первую запись, чтобы увидеть аналитику',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      ActivityLineChart(
          data: AnalyticsService.monthDistribution(entries)),
      const SizedBox(height: 16),
      SpeciesPieChart(
          data: AnalyticsService.speciesDistribution(entries)),
      const SizedBox(height: 16),
      TopSpeciesList(
          species: AnalyticsService.getTopSpecies(entries)),
      const SizedBox(height: 16),
      SeasonComparisonCard(
          seasons: AnalyticsService.seasonDistribution(entries)),
    ];
  }
}
