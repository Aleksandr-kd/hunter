import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/region.dart';
import '../providers/regions_provider.dart';

/// Экран «Регионы» — выбор регионов (1 бесплатно, все по подписке).
class RegionsScreen extends StatelessWidget {
  const RegionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RegionsProvider>();
    final regions = provider.getRegions();

    return Scaffold(
      appBar: AppBar(title: const Text('Регионы')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                provider.hasUnlimited
                    ? 'Все регионы доступны'
                    : 'Бесплатно можно выбрать 1 регион. '
                        'Включите другой — текущий отключится. '
                        'Подписка «Max» открывает все регионы.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...regions.map((r) => _RegionTile(region: r)),
        ],
      ),
    );
  }
}

class _RegionTile extends StatelessWidget {
  final Region region;

  const _RegionTile({required this.region});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RegionsProvider>();
    final enabled = provider.isEnabled(region.id);

    return Card(
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