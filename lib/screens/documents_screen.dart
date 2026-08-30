import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../providers/document_provider.dart';
import '../providers/settings_sync_provider.dart';
import '../services/notification_service.dart';
import '../widgets/glass_card.dart';
import 'auth_gate.dart';

/// Экран «Документы» — контроль сроков действия документов и разрешений.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  @override
  void initState() {
    super.initState();
    // Загружаем провайдер при первом открытии экрана.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<DocumentProvider>();
      if (!provider.loaded) {
        // Provider инициализируется в конструкторе — это safeguard.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Документы')),
      body: Consumer<DocumentProvider>(
        builder: (ctx, provider, _) {
          return !provider.loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
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
                    ...provider.documents.map(
                      (d) => _DocTile(
                        doc: d,
                        onTap: () => _pickDate(context, d),
                        onClear: () => _clear(context, d),
                      ),
                    ),
                  ],
                );
        },
      ),
    );
  }

  Future<void> _pickDate(BuildContext context, Document doc) async {
    final authed = await requireAuth(context);
    if (!authed || !context.mounted) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: doc.expiryDate ?? now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked == null) return;
    if (!context.mounted) return;
    final provider = context.read<DocumentProvider>();
    await provider.updateExpiry(doc, picked);
    final fresh = _freshDoc(provider, doc);
    await _schedule(fresh);
  }

  Future<void> _clear(BuildContext context, Document doc) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Сбросить дату?'),
            content: const Text('Это действие нельзя отменить.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Отмена')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Сбросить')),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    final provider = context.read<DocumentProvider>();
    await provider.updateExpiry(doc, null);
    await _cancelNotifications(_freshDoc(provider, doc));
  }

  /// Возвращает актуальный объект документа из провайдера.
  /// Провайдер заменяет объект через copyWith при мутации, поэтому ссылка
  /// `doc`, переданная из _DocTile, после updateExpiry устаревает.
  Document _freshDoc(DocumentProvider provider, Document doc) {
    return provider.documents.firstWhere(
      (d) => d.title == doc.title,
      orElse: () => doc,
    );
  }

  Future<void> _schedule(Document doc) async {
    if (!mounted) return;
    final expiry = doc.expiryDate;
    if (expiry == null) return;
    // Баг 3: уважаем переключатель «Уведомления о документах».
    final enabled =
        context.read<SettingsSyncProvider>().notificationsDocuments;
    final svc = NotificationService.instance;
    if (!enabled) {
      // Планировать нечего — гасим любые ранее запланированные пуши по документу.
      await _cancelNotifications(doc);
      return;
    }
    // Сначала снимаем старые, чтобы перенос даты не оставил уведомления
    // по прежнему сроку (баг 6).
    await _cancelNotifications(doc);

    // Напоминание за 30, 14 и 3 дня.
    for (final (days, label) in [(30, '30 дней'), (14, '2 недели'), (3, '3 дня')]) {
      final when = expiry.subtract(Duration(days: days));
      if (when.isAfter(DateTime.now())) {
        await svc.scheduleNotification(
          id: NotificationService.docNotifId(doc.title, days),
          title: 'Документ истекает',
          body: '${doc.title} истекает через $label (${expiry.day}.${expiry.month}).',
          scheduledAt: when,
        );
      }
    }
  }

  Future<void> _cancelNotifications(Document doc) async {
    final svc = NotificationService.instance;
    for (final days in [30, 14, 3]) {
      await svc.cancel(NotificationService.docNotifId(doc.title, days));
    }
  }
}

class _DocTile extends StatelessWidget {
  final Document doc;
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
    final hasExpiry = doc.expiryDate != null;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.assignment_outlined),
        title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          hasExpiry
              ? 'Действует до: ${_fmt(doc.expiryDate!)}'
              : 'Дата не задана',
        ),
        trailing: hasExpiry
            ? TextButton(
                onPressed: onClear,
                child: const Text('Сбросить'),
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
