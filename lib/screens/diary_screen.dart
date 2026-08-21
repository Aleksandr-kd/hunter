import 'package:flutter/material.dart';

/// Экран «Дневник» — учёт добычи и наблюдений.
class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Дневник')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Здесь будут записи дневника\n(10 записей бесплатно)',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}