import 'package:flutter/material.dart';

/// Адаптивная обёртка для вложенных (открываемых) экранов.
///
/// На больших экранах (планшет/широкий) ограничивает ширину контента
/// и центрирует его, чтобы не было «простыни» на всю ширину.
/// На телефонах (`< [_phoneMaxWidth]`) обёртка не ограничивает ничего.
class ResponsivePage extends StatelessWidget {
  /// Максимальная ширина контента на широких экранах.
  static const double maxWidth = 700;

  /// Порог, до которого считаем экран «телефоном» (без ограничения ширины).
  static const double _phoneMaxWidth = 600;

  final Widget child;

  const ResponsivePage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= _phoneMaxWidth) {
          return child;
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
      },
    );
  }
}