import 'package:flutter/material.dart';

/// Адаптивная обёртка для подстраниц (формы, детали, справочники).
///
/// На широких экранах (планшет в горизонтальной ориентации, десктоп)
/// подстраница не растягивается на весь экран (это делает обычный
/// `ListView`), а центрируется с ограниченной рабочей шириной, чтобы поля
/// форм и карточки не становились неоправданно широкими. На телефоне
/// контент занимает всю доступную ширину.
///
/// [child] должен быть [Scaffold]: обёртка сама предоставляет Scaffold,
/// чтобы AppBar и контент занимали всю высоту, а внутри центрируется
/// ограниченный по ширине контент.
class ResponsivePage extends StatelessWidget {
  final Widget child;

  /// Максимальная рабочая ширина подстраниц на планшете/десктопе.
  static const double _maxWidth = 760;

  const ResponsivePage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: child,
        ),
      ),
    );
  }
}