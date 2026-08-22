import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/region.dart';
import '../providers/regions_provider.dart';
import '../services/notification_service.dart';
import '../widgets/glass_card.dart';

/// Экран «Сезоны» — сроки охоты выбранного региона.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RegionsProvider>();
    final region = provider.activeRegion;

    return Scaffold(
      appBar: AppBar(title: const Text('Сроки охоты')),
      body: region == null
          ? _EmptyState(onSelectRegion: () => provider.toggleRegion('krasnodar'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _RegionHeader(regionName: region.name),
                const SizedBox(height: 8),
                ...region.species.map(
                  (s) => _SeasonTile(period: s, now: DateTime.now()),
                ),
              ],
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onSelectRegion;

  const _EmptyState({required this.onSelectRegion});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined,
              size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text('Регион не выбран'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: onSelectRegion,
            child: const Text('Выбрать Краснодарский край'),
          ),
        ],
      ),
    );
  }
}

class _RegionHeader extends StatelessWidget {
  final String regionName;

  const _RegionHeader({required this.regionName});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      tint: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.location_on_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    regionName,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Информация справочная. Сверяйтесь с официальными приказами.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSecondaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeasonTile extends StatefulWidget {
  final SeasonPeriod period;
  final DateTime now;

  const _SeasonTile({required this.period, required this.now});

  @override
  State<_SeasonTile> createState() => _SeasonTileState();
}

class _SeasonTileState extends State<_SeasonTile> {
  bool _bellOn = false;
  SeasonPeriod get period => widget.period;
  DateTime get now => widget.now;

  int get _reminderId => period.name.hashCode % 10000;

  void _toggleReminder() {
    final open = period.openDate;
    final messenger = ScaffoldMessenger.of(context);
    // Убираем текущий SnackBar сразу, чтобы следующий показать мгновенно.
    messenger.clearSnackBars();
    if (!_bellOn) {
      if (open == null || open.isBefore(now)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Сезон уже открыт — напоминание не нужно')),
        );
        return;
      }
      setState(() => _bellOn = true);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Напомним ${_fmt(open)} в 9:00'),
          duration: const Duration(seconds: 2),
        ),
      );
      unawaited(_scheduleAsync(open));
    } else {
      setState(() => _bellOn = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Уведомление отключено'),
          duration: Duration(seconds: 2),
        ),
      );
      unawaited(NotificationService.instance.cancel(_reminderId));
    }
  }

  /// Планирование в фоне (не блокирует UI и SnackBar).
  Future<void> _scheduleAsync(DateTime open) async {
    try {
      final when = DateTime(open.year, open.month, open.day, 9, 0);
      await NotificationService.instance.scheduleNotification(
        id: _reminderId,
        title: 'Сезон открывается',
        body: 'Открывается охота: ${period.name}',
        scheduledAt: when,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = period.statusAt(now);

    final (Color color, IconData icon, String label) = switch (status) {
      SeasonStatus.open => (
          scheme.primary,
          Icons.check_circle,
          'Сезон открыт',
        ),
      SeasonStatus.coming => (
          const Color(0xFFF9A825),
          Icons.schedule,
          'Скоро сезон',
        ),
      SeasonStatus.closed => (
          scheme.outline,
          Icons.lock,
          'Закрыт',
        ),
      SeasonStatus.unknown => (
          scheme.outline,
          Icons.help_outline,
          'Уточняется',
        ),
    };

    String dates = '';
    if (period.openDate != null) {
      dates = 'с ${_fmt(period.openDate!)}';
    }
    if (period.closeDate != null) {
      dates += ' по ${_fmt(period.closeDate!)}';
    }

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(period.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(dates),
            if (period.notes != null && period.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  period.notes!,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (period.openDate != null && period.openDate!.isAfter(now))
              IconButton(
                icon: Icon(
                  _bellOn ? Icons.notifications : Icons.notifications_outlined,
                  color: _bellOn ? scheme.primary : null,
                ),
                tooltip: _bellOn ? 'Уведомление включено' : 'Напомнить об открытии',
                onPressed: _toggleReminder,
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime d) {
    const months = [
      '', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return '${d.day} ${months[d.month]}';
  }
}