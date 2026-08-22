import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../widgets/glass_card.dart';
import 'auth_gate.dart';

/// Экран «Документы» — контроль сроков действия документов и разрешений.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _Document {
  final String title;
  DateTime? expiry;

  _Document(this.title, this.expiry);
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final List<_Document> _documents = [
    _Document('Охотничий билет', null),
    _Document('Разрешение на оружие (РСОА)', null),
    _Document('Договор / путёвка охотхозяйства', null),
    _Document('Разрешение на добычу (текущий сезон)', null),
  ];

  Future<void> _pickDate(_Document doc) async {
    final ctx = context;
    final authed = await requireAuth(ctx);
    if (!authed || !ctx.mounted) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: ctx,
      initialDate: doc.expiry ?? now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked == null) return;
    setState(() {
      doc.expiry = picked;
      _schedule(doc);
    });
  }

  Future<void> _schedule(_Document doc) async {
    final expiry = doc.expiry;
    if (expiry == null) return;
    final svc = NotificationService.instance;
    final id = _documents.indexOf(doc) + 1;

    // Напоминание за 30, 14 и 3 дня.
    for (final (days, label) in [(30, '30 дней'), (14, '2 недели'), (3, '3 дня')]) {
      final when = expiry.subtract(Duration(days: days));
      if (when.isAfter(DateTime.now())) {
        await svc.scheduleNotification(
          id: id * 100 + days,
          title: 'Документ истекает',
          body: '${doc.title} истекает через $label (${doc.expiry?.day}.${doc.expiry?.month}).',
          scheduledAt: when,
        );
      }
    }
  }

  Future<void> _clear(_Document doc) async {
    final id = _documents.indexOf(doc) + 1;
    final svc = NotificationService.instance;
    for (final days in [30, 14, 3]) {
      await svc.cancel(id * 100 + days);
    }
    setState(() => doc.expiry = null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Документы')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          GlassCard(
            tint: scheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.verified_user_outlined),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Задайте дату окончания документа — '
                      'пришлём напоминание за 30, 14 и 3 дня.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ..._documents.map((d) => _DocTile(
                doc: d,
                onTap: () => _pickDate(d),
                onClear: () => _clear(d),
              )),
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  final _Document doc;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DocTile({
    required this.doc,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasExpiry = doc.expiry != null;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.assignment_outlined),
        title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          hasExpiry
              ? 'Действует до: ${_fmt(doc.expiry!)}'
              : 'Дата не задана',
        ),
        trailing: hasExpiry
            ? IconButton(
                icon: const Icon(Icons.check_circle),
                onPressed: onClear,
                tooltip: 'Сбросить',
              )
            : Icon(Icons.add_circle_outline, color: scheme.primary),
        onTap: onTap,
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