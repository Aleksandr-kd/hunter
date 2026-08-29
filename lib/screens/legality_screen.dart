import 'package:flutter/material.dart';

import '../widgets/glass_card.dart';

/// Упрощённый калькулятор законности добычи.
class LegalityScreen extends StatefulWidget {
  const LegalityScreen({super.key});

  @override
  State<LegalityScreen> createState() => _LegalityScreenState();
}

class _LegalityScreenState extends State<LegalityScreen> {
  final _speciesCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool? _result;
  String _regionId = 'krasnodar';

  @override
  void dispose() {
    _speciesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _check() {
    final species = _speciesCtrl.text.trim().toLowerCase();
    if (species.isEmpty) {
      setState(() => _result = null);
      return;
    }
    final month = _date.month;
    bool allowed = true;

    // Правила зависят от региона.
    if (_regionId == 'krasnodar') {
      if (species.contains('кабан')) {
        allowed = month >= 6 || month <= 2;
      } else if (species.contains('заяц')) {
        allowed = month == 11 || month == 12 || month == 1;
      } else if (species.contains('утк') || species.contains('гус') ||
          species.contains('водопл')) {
        allowed = month >= 9;
      } else if (species.contains('олен')) {
        allowed = month >= 6 || month == 1;
      } else if (species.contains('косул')) {
        allowed = month >= 6 && month <= 10;
      }
    } else {
      // Для других регионов — заглушка (правила нужно добавить).
      allowed = true;
    }
    setState(() => _result = allowed);
  }

  String _regionName() {
    switch (_regionId) {
      case 'krasnodar':
        return 'Краснодарского края';
      default:
        return 'выбранного региона';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const months = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Калькулятор законности')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            tint: scheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Упрощённая проверка по срокам ${_regionName()}.\n'
                'Сверяйтесь с официальными документами перед охотой.',
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _regionId,
            decoration: const InputDecoration(
              labelText: 'Регион',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'krasnodar', child: Text('Краснодарский край')),
            ],
            onChanged: (v) => setState(() => _regionId = v ?? 'krasnodar'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _speciesCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Вид (кабан, заяц, утка…)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(
                'Дата: ${_date.day} ${months[_date.month]} ${_date.year}'),
            onTap: _pickDate,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _check,
            child: const Text('Проверить'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: _result!
                  ? scheme.primaryContainer
                  : scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _result! ? Icons.check_circle : Icons.cancel,
                      color: _result!
                          ? scheme.onPrimaryContainer
                          : scheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _result!
                            ? 'По упрощённой модели охота допустима.'
                            : 'По упрощённой модели охота не предусмотрена.',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
