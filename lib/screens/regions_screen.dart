import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/region.dart';
import '../providers/auth_provider.dart';
import '../providers/regions_provider.dart';
import '../widgets/glass_card.dart';
import 'auth_gate.dart';

/// Экран «Регионы» — выбор регионов (1 бесплатно, все по подписке Max).
class RegionsScreen extends StatelessWidget {
  const RegionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Следим и за тарифом, чтобы экран мгновенно обновлялся при его смене.
    context.watch<AuthProvider>();
    final provider = context.watch<RegionsProvider>();
    final regions = provider.getRegions();

    return Scaffold(
      appBar: AppBar(title: const Text('Регионы')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              GlassCard(
                tint: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    provider.hasUnlimited
                        ? 'Все регионы доступны'
                        : 'Бесплатно и на «Premium» можно выбрать 1 регион. '
                            'Включите другой — текущий отключится. '
                            'Подписка «Max» открывает все регионы сразу.',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (wide)
                _RegionsGrid(regions: regions, provider: provider)
              else
                ...regions.map((r) => _RegionTile(region: r)),
            ],
          );
        },
      ),
    );
  }
}

/// Адаптивная сетка регионов: 2 колонки на широких экранах, 1 колонка на телефоне.
class _RegionsGrid extends StatelessWidget {
  final List<Region> regions;
  final RegionsProvider provider;

  const _RegionsGrid({required this.regions, required this.provider});

  @override
  Widget build(BuildContext context) {
    final columns = (regions.length >= 2) ? 2 : 1;
    final rows = <Widget>[];
    for (var i = 0; i < regions.length; i += columns) {
      final row = regions.sublist(
          i, i + columns > regions.length ? regions.length : i + columns);
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < row.length; c++) ...[
              if (c > 0) const SizedBox(width: 8),
              Expanded(child: _RegionTile(region: row[c])),
            ],
            for (var c = row.length; c < columns; c++)
              const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }
}

class _RegionTile extends StatelessWidget {
  final Region region;

  const _RegionTile({required this.region});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RegionsProvider>();
    final enabled = provider.isEnabled(region.id);

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          enabled ? Icons.check_circle : Icons.radio_button_unchecked,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(region.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${region.species.length} видов дичи'),
        trailing: Switch(
          value: enabled,
          onChanged: (_) => _toggle(context, provider),
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, RegionsProvider provider) async {
    final authed = await requireAuth(context);
    if (!authed || !context.mounted) return;
    final wasEnabled = provider.isEnabled(region.id);
    final atLimit = !wasEnabled && provider.enabledRegionIds.length >= provider.maxRegions;

    // Если лимит будет превышен — сначала спросим пользователя.
    var proceed = true;
    if (atLimit) {
      proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Достигнут лимит регионов'),
              content: const Text(
                'В бесплатной версии можно выбрать только 1 регион. '
                'Включить регион, отключив текущий?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Переключить'),
                ),
              ],
            ),
          ) ??
          false;
      if (!context.mounted) return;
    }
    if (!proceed) return;

    if (atLimit) {
      final current = provider.enabledRegionIds;
      if (current.length == 1) await provider.toggleRegion(current.first);
    }
    await provider.toggleRegion(region.id);
  }
}