import 'package:flutter/material.dart';

/// Экран «Сезоны» — сроки охоты выбранного региона.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сроки охоты')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_month,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Здесь будут сроки охоты\nпо выбранному региону',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}