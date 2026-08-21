import 'package:flutter/material.dart';

/// Экран «Документы» — контроль и напоминания о документах и разрешениях.
class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Документы')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Здесь будут напоминания\nо документах и разрешениях',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}