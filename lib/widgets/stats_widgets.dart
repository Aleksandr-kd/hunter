import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../services/analytics_service.dart';
import '../widgets/glass_card.dart';

// ============================================================
// AnimatedStatCard — анимированная карточка статистики
// ============================================================

/// Карточка с анимацией числа и индикатором тренда.
class AnimatedStatCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final int endValue;
  final TrendInfo? trend;
  final Color? color;

  const AnimatedStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.endValue,
    this.trend,
    this.color,
  });

  @override
  State<AnimatedStatCard> createState() => _AnimatedStatCardState();
}

class _AnimatedStatCardState extends State<AnimatedStatCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedStatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endValue != widget.endValue) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.color ?? scheme.primary;

    return Expanded(
      child: Column(
        children: [
          Icon(widget.icon, color: color, size: 28),
          const SizedBox(height: 6),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: widget.endValue),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOut,
            builder: (context, value, _) {
              return Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              );
            },
          ),
          if (widget.trend != null) ...[
            const SizedBox(height: 2),
            Text(
              '${widget.trend!.arrow} ${widget.trend!.percentText}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: widget.trend!.isGrowing
                    ? Colors.green.shade600
                    : widget.trend!.isDeclining
                        ? Colors.red.shade600
                        : scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(widget.label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

// ============================================================
// ActivityLineChart — линейный график активности
// ============================================================

/// Линейный график распределения записей по месяцам.
class ActivityLineChart extends StatelessWidget {
  final Map<String, int> data;

  const ActivityLineChart({super.key, required this.data});

  /// Маппинг названий месяцев на номера 1-12.
  static int _monthIndex(String key) {
    const months = {
      'Янв': 1, 'Фев': 2, 'Мар': 3, 'Апр': 4, 'Май': 5, 'Июн': 6,
      'Июл': 7, 'Авг': 8, 'Сен': 9, 'Окт': 10, 'Ноя': 11, 'Дек': 12,
      'January': 1, 'February': 2, 'March': 3, 'April': 4, 'May': 5, 'June': 6,
      'July': 7, 'August': 8, 'September': 9, 'October': 10, 'November': 11, 'December': 12,
    };
    return months[key] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (data.isEmpty) {
      return _emptyChartCard(context, 'Нет данных для графика');
    }

    final spots = data.entries
        .map((e) {
          final idx = _monthIndex(e.key);
          if (idx < 1 || idx > 12) return null;
          return FlSpot(idx.toDouble(), e.value.toDouble());
        })
        .whereType<FlSpot>()
        .toList();

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Активность по месяцам',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                mainChartData(spots, scheme),
                duration: const Duration(milliseconds: 250),
              ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData mainChartData(List<FlSpot> spots, ColorScheme scheme) {
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 1,
        getDrawingHorizontalLine: (value) => FlLine(
          color: scheme.onSurface.withValues(alpha: 0.1),
          strokeWidth: 1,
        ),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (value, meta) {
              return Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                ),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            getTitlesWidget: (value, meta) {
              const months = [
                '', 'Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн',
                'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек',
              ];
              final index = value.toInt();
              if (index >= 1 && index <= 12 && months[index].isNotEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    months[index],
                    style: TextStyle(
                      fontSize: 9,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.2,
          color: scheme.primary,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                scheme.primary.withValues(alpha: 0.3),
                scheme.primary.withValues(alpha: 0.05),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(
        enabled: true,
        handleBuiltInTouches: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final monthIndex = spot.x.toInt();
              const monthNames = [
                '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
                'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
              ];
              final monthName = (monthIndex >= 1 && monthIndex <= 12)
                  ? monthNames[monthIndex]
                  : '';
              return LineTooltipItem(
                '$monthName\n',
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                children: [
                  TextSpan(
                    text: '${spot.y.toInt()} записей',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                ],
              );
            }).toList();
          },
        ),
      ),
    );
  }

  Widget _emptyChartCard(BuildContext context, String message) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(message,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ),
    );
  }
}

// ============================================================
// SpeciesPieChart — круговая диаграмма видов
// ============================================================

/// Круговая диаграмма распределения записей по видам.
class SpeciesPieChart extends StatelessWidget {
  final Map<String, int> data;

  const SpeciesPieChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (data.isEmpty) {
      return _emptyChartCard(context, 'Нет данных для диаграммы');
    }

    final total = data.values.fold<int>(0, (sum, v) => sum + v);
    final sections = data.entries.map((entry) {
      final percentage = entry.value / total * 100;
      return PieChartSectionData(
        value: entry.value.toDouble(),
        title: '${percentage.toStringAsFixed(0)}%',
        color: _getSpeciesColor(entry.key, scheme),
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Распределение по видам',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pie chart
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 180,
                    child: PieChart(
                      PieChartData(
                        sections: sections,
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        startDegreeOffset: -90,
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Legend
                Expanded(
                  flex: 2,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: data.entries
                        .take(6)
                        .map((entry) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _getSpeciesColor(entry.key, scheme),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${entry.key} ${entry.value}',
                                  style: const TextStyle(fontSize: 10),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                        })
                        .toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getSpeciesColor(String species, ColorScheme scheme) {
    // Deterministic color based on species name hash
    final hash = species.hashCode.abs();
    final colors = [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.surfaceContainerHighest,
      scheme.primaryContainer,
      scheme.secondaryContainer,
    ];
    return colors[hash % colors.length];
  }

  Widget _emptyChartCard(BuildContext context, String message) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(message,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ),
    );
  }
}

// ============================================================
// TopSpeciesList — рейтинг видов
// ============================================================

/// Список топ-видов с прогресс-барами.
class TopSpeciesList extends StatelessWidget {
  final List<TopSpecies> species;

  const TopSpeciesList({super.key, required this.species});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (species.isEmpty) {
      return const SizedBox.shrink();
    }

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Топ видов',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(height: 12),
            ...species.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.pets,
                            size: 16, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.species,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text('${item.count} (${item.percentage.toStringAsFixed(0)}%)',
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: item.percentage / 100,
                      minHeight: 4,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        scheme.primary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SeasonComparisonCard — сравнение сезонов
// ============================================================

/// Карточка сравнения активности по сезонам.
class SeasonComparisonCard extends StatelessWidget {
  final Map<String, int> seasons;

  const SeasonComparisonCard({super.key, required this.seasons});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (seasons.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxCount = seasons.values.fold<int>(0, (m, v) => v > m ? v : m);

    // Иконки и цвета для сезонов
    final seasonConfig = {
      'Весна': (icon: Icons.local_florist, color: Colors.green.shade600),
      'Лето': (icon: Icons.wb_sunny, color: Colors.orange.shade600),
      'Осень': (icon: Icons.nature, color: Colors.brown.shade600),
      'Зима': (icon: Icons.snowing, color: Colors.blue.shade400),
    };

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Активность по сезонам',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: seasons.entries.map((entry) {
                final config = seasonConfig[entry.key] ??
                    (icon: Icons.calendar_today, color: scheme.primary);
                final isMax = entry.value == maxCount && maxCount > 0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        Icon(
                          config.icon,
                          color: isMax
                              ? config.color
                              : scheme.onSurfaceVariant,
                          size: 28,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.value.toString(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: isMax
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isMax
                                ? config.color
                                : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 10,
                            color: isMax
                                ? config.color
                                : scheme.onSurfaceVariant,
                            fontWeight:
                                isMax ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (maxCount > 0)
                          LinearProgressIndicator(
                            value: entry.value / maxCount,
                            minHeight: 3,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                            backgroundColor: scheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isMax ? config.color : scheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SmartInsightsCard — блок умных инсайтов
// ============================================================

/// Карточка с умными инсайтами.
class SmartInsightsCard extends StatelessWidget {
  final List<Insight> insights;

  const SmartInsightsCard({super.key, required this.insights});

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) {
      return const SizedBox.shrink();
    }

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Умные подсказки',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 12),
            ...insights.map((insight) {
              final iconColor = _insightTypeColor(insight.type, context);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(insight.icon,
                        size: 20, color: iconColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            insight.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            insight.description,
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Color _insightTypeColor(InsightType type, BuildContext context) {
    switch (type) {
      case InsightType.info:
        return Theme.of(context).colorScheme.primary;
      case InsightType.achievement:
        return Colors.amber.shade700;
      case InsightType.tip:
        return Colors.green.shade700;
      case InsightType.warning:
        return Colors.red.shade700;
    }
  }
}

// ============================================================
// SkeletonStatsCard — skeleton loading
// ============================================================

/// Skeleton-экран для состояния загрузки.
class SkeletonStatsScreen extends StatelessWidget {
  const SkeletonStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SkeletonCard(
          child: Column(
            children: [
              _SkeletonLine(height: 16, width: 120),
              const SizedBox(height: 12),
              Row(
                children: List.generate(
                  4,
                  (i) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          _SkeletonCircle(size: 28),
                          const SizedBox(height: 6),
                          _SkeletonLine(height: 20, width: 40),
                          const SizedBox(height: 2),
                          _SkeletonLine(height: 10, width: 30),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SkeletonCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _SkeletonLine(height: 14, width: 140),
                const SizedBox(height: 16),
                _SkeletonBar(height: 160),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  final Widget child;

  const _SkeletonCard({required this.child});

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      reverseDuration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          return ColorFiltered(
            colorFilter: ColorFilter.mode(
              Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: _animation.value * 0.6 + 0.2),
              BlendMode.srcATop,
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  final double height;
  final double width;

  const _SkeletonLine({required this.height, required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _SkeletonCircle extends StatelessWidget {
  final double size;

  const _SkeletonCircle({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  final double height;

  const _SkeletonBar({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
