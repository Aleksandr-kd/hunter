import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/glass_card.dart';

/// Dev-экран переключения тарифа (только для автора).
class TierSwitchScreen extends StatelessWidget {
  const TierSwitchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isDev) {
      return Scaffold(
        appBar: AppBar(title: const Text('Тариф (тест)')),
        body: const Center(child: Text('Этот раздел доступен только разработчику')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Тариф (тест)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Тестовое переключение тарифа. '
            'Моментально меняет уровень для проверки функций.',
            style: TextStyle(color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 20),
          _TierSwitchButton(
            label: 'Бесплатная версия',
            active: auth.tier == 'none',
            onTap: () => auth.setTier('none'),
            features: const [
              'Сроки охоты в 1 регионе',
              'Дневник: до 10 записей',
              'Напоминания (базовые)',
              'Реклама',
            ],
          ),
          const SizedBox(height: 14),
          _TierSwitchButton(
            label: 'Версия Premium',
            active: auth.tier == 'premium',
            onTap: () => auth.setTier('premium'),
            features: const [
              'Без рекламы',
              'Безлимитный дневник',
              'Экспорт в PDF/CSV',
              'Резервная копия',
              'Тёмная тема',
            ],
          ),
          const SizedBox(height: 14),
          _TierSwitchButton(
            label: 'Версия Premium +',
            active: auth.tier == 'max',
            onTap: () => auth.setTier('max'),
            features: const [
              'Всё из Premium',
              'Все регионы сразу',
              'Калькулятор законности',
              'Расширенная статистика',
            ],
          ),
        ],
      ),
    );
  }
}

class _TierSwitchButton extends StatelessWidget {
  final String label;
  final bool active;
  final List<String> features;
  final VoidCallback onTap;

  const _TierSwitchButton({
    required this.label,
    required this.active,
    required this.features,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = active ? scheme.onPrimary : null;
    return GlassCard(
      radius: 14,
      tint: active ? scheme.primary : scheme.surfaceContainerHighest,
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg),
                    ),
                  ),
                  Text(
                    active ? 'Вкл' : 'Выкл',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: active ? fg : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (!active) ...[
                const SizedBox(height: 10),
                ...features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('•  ', style: TextStyle(color: scheme.onSurfaceVariant)),
                          Expanded(
                            child: Text(f, style: TextStyle(color: scheme.onSurfaceVariant)),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
    );
  }
}