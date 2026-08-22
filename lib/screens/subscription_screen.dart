import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'auth_gate.dart';

/// Экран «Подписка» — тарифы Premium/Max и текущий статус.
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Подписка')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Статус текущего уровня.
          Card(
            elevation: 0,
            color: scheme.secondaryContainer,
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
              'Экспорт в PDF/CSV',
              'Резервная копия',
              'Тёмная тема',
            ],
            active: auth.isPremium,
            buttonLabel: auth.isPremium ? 'Активна' : 'Подключить Premium',
            onPressed: auth.isPremium
                ? null
                : () async {
                    final ok = await requireAuth(context);
                    if (ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Покупка Premium появится после подключения RuStore')),
                      );
                    }
                  },
          ),
          const SizedBox(height: 12),

          // Тариф Max 300.
          _Plan(
            title: 'Premium +',
            price: '299 ₽ / год',
            features: const [
              'Всё из Premium',
              'Все регионы сразу',
              'Калькулятор законности',
              'Расширенная статистика',
            ],
            active: auth.isMax,
            buttonLabel: auth.isMax ? 'Активна' : 'Подключить Premium +',
            onPressed: auth.isSignedIn
                ? null
                : () async {
                    final ok = await requireAuth(context);
                    if (ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Покупка Max появится после подключения RuStore')),
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

class _Plan extends StatelessWidget {
  final String title;
  final String price;
  final List<String> features;
  final bool active;
  final String buttonLabel;
  final VoidCallback? onPressed;

  const _Plan({
    required this.title,
    required this.price,
    required this.features,
    required this.active,
    required this.buttonLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: active
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide.none,
      ),
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPressed,
                child: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}