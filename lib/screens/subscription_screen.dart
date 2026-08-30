import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/glass_card.dart';
import 'auth_gate.dart';

/// Экран «Подписка» — тарифы Premium/Max и текущий статус.
///
/// На старте приложение выходит со «всеми функциями» (подписки выключены),
/// поэтому экран показывает заглушку «максимальная функциональность».
/// Полная логика тарифов ниже сохранена и вернётся, когда включим монетизацию
/// — для этого достаточно переключить [_showSubscription] в `true`.
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  /// Когда `false` — пользователь видит заглушку «всё доступно».
  /// Когда `true` — включается реальный экран тарифов (после монетизации).
  static const bool _showSubscription = false;

  @override
  Widget build(BuildContext context) {
    if (!_showSubscription) {
      return _AllUnlockedPlaceholder();
    }
    return _buildSubscription(context);
  }

  Widget _buildSubscription(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Подписка')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Статус текущего уровня.
          GlassCard(
            tint: scheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium_outlined,
                      color: scheme.onSecondaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ваш тариф:',
                            style: TextStyle(color: scheme.onSecondaryContainer)),
                        Text(
                          _tierLabel(auth.tier),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Тариф Premium 159.
          _Plan(
            title: 'Premium',
            price: '159 ₽ / год',
            features: const [
              'Без рекламы',
              'Безлимитный дневник',
              'Резервная копия',
              'Тёмная тема',
            ],
            active: auth.tier == 'premium',
            buttonLabel: auth.tier == 'premium' ? 'Активна' : 'Подключить Premium',
            showButton: auth.tier != 'premium',
            onPressed: () async {
              final ok = await requireAuth(context);
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Покупка Premium появится после подключения RuStore')),
                );
              }
            },
          ),
          const SizedBox(height: 12),

          // Тариф Premium+.
          _Plan(
            title: 'Premium +',
            price: '299 ₽ / год',
            features: const [
              'Всё из Premium',
              'Все регионы сразу',
              'Калькулятор законности',
              'Расширенная статистика',
            ],
            active: auth.tier == 'max',
            buttonLabel: auth.tier == 'max' ? 'Активна' : 'Подключить Premium +',
            showButton: auth.tier != 'max',
            onPressed: () async {
              final ok = await requireAuth(context);
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Покупка Premium+ появится после подключения RuStore')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  static String _tierLabel(String tier) {
    switch (tier) {
      case 'premium':
        return 'Premium';
      case 'max':
        return 'Max';
      default:
        return 'Бесплатно';
    }
  }
}

/// Временная заглушка: до включения монетизации пользователю показываем,
/// что доступна вся функциональность. Вернётся реальный экран тарифов,
/// когда `_showSubscription` станет `true` (см. [SubscriptionScreen]).
class _AllUnlockedPlaceholder extends StatelessWidget {
  const _AllUnlockedPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Подписка')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.workspace_premium_outlined,
                  size: 64, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                'У вас максимальная функциональность!',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Все функции приложения доступны вам.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Plan extends StatelessWidget {
  final String title;
  final String price;
  final List<String> features;
  final bool active;
  final String buttonLabel;
  final bool showButton;
  final VoidCallback? onPressed;

  const _Plan({
    required this.title,
    required this.price,
    required this.features,
    required this.active,
    required this.buttonLabel,
    this.showButton = true,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      radius: 16,
      tint: active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderColor: active ? scheme.primary : null,
      borderWidth: active ? 2 : 0.6,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(price,
                    style: TextStyle(
                        color: scheme.primary, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            ...features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Icon(Icons.check, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f)),
                  ]),
                )),
            if (showButton) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onPressed,
                  child: Text(buttonLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}