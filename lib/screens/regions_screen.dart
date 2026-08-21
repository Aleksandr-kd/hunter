import 'package:flutter/material.dart';

/// Экран «Регионы» — выбор и управление регионами охоты.
class RegionsScreen extends StatelessWidget {
  const RegionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Регионы')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Здесь будет выбор регионов\n(1 бесплатно, все по подписке)',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}