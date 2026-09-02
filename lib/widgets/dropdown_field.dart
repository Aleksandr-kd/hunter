import 'package:flutter/material.dart';

/// Выпадающее поле-пилюля (один-в-один как в фильтрах «Сроки охоты»).
///
/// Название фильтра рисуется своим рядком сверху, само поле — округлая
/// пилюля с `DropdownButton`. Адаптивно: растягивается на всю доступную
/// ширину родителя (`isExpanded`).
class DropdownField extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String> onSelectName;

  const DropdownField({
    super.key,
    this.label = '',
    required this.value,
    required this.items,
    required this.onSelectName,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Название фильтра — своим рядком сверху, один цвет для всех.
          // Пустой label не рисуем (заголовок задан снаружи).
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                label,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          // Пилюля — один-в-один как инпут Дневника.
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                isDense: true,
                dropdownColor: scheme.surfaceContainerLowest,
                hint: Text('Выберите',
                    style:
                        TextStyle(color: scheme.onSurfaceVariant, fontSize: 15)),
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 15,
                ),
                icon: Icon(Icons.arrow_drop_down,
                    color: scheme.onSurfaceVariant),
                items: items
                    .map((item) => DropdownMenuItem(
                          value: item,
                          child: Text(item,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onSelectName(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}