import 'package:flutter/material.dart';

/// Экран «Документы» — контроль сроков действия документов и разрешений.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _Document {
  final String title;
  final DateTime? expiry;

  const _Document(this.title, this.expiry);
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  // Типовые документы охотника. Даты пользователь задаст позже (этап 3+).
  static const _documents = [
    _Document('Охотничий билет', null),
    _Document('Разрешение на оружие (РСОА)', null),
    _Document('Договор / путёвка охотхозяйства', null),
    _Document('Разрешение на добычу (текущий сезон)', null),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Документы')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            elevation: 0,
            color: scheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.verified_user_outlined),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Контролируйте сроки действия документов, '
                      'чтобы избежать штрафов. Напоминания о сроках появятся '
                      'в следующей версии.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ..._documents.map((d) => _DocTile(doc: d)),
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  final _Document doc;

  const _DocTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.assignment_outlined),
        title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          doc.expiry == null
              ? 'Дата не задана'
              : 'Действует до: ${_fmt(doc.expiry!)}',
        ),
        trailing: Icon(
          doc.expiry == null ? Icons.add_circle_outline : Icons.check_circle,
          color: doc.expiry == null ? scheme.primary : scheme.primary,
        ),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Задание срока — в следующей версии')),
          );
        },
      ),
    );
  }

  static String _fmt(DateTime d) {
    const months = [
      '', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }
}