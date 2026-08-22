import 'package:flutter/material.dart';

/// Карточка с полупрозрачной подложкой (лёгкий намёк на «стекло»).
///
/// Примечание: на физических iOS-устройствах настоящий blur
/// ([BackdropFilter] / [glass_kit]) на iOS 27 давал пустой рендер
/// контента, поэтому используется обычная Material-карточка
/// с полупрозрачным цветом — безопасно на всех платформах.
class GlassCard extends StatelessWidget {
  /// Подложка под карточкой: цвет (более прозрачный — сильнее «стекло»).
  final Color? tint;

  /// Радиус скругления (по умолчанию берётся из темы).
  final double? radius;

  /// Толщина границы «стекла».
  final double borderWidth;

  /// Цвет границы (по умолчанию — outlineVariant из темы).
  final Color? borderColor;

  /// Тень карточки (по умолчанию — лёгкая).
  final List<BoxShadow>? boxShadow;

  /// Внешний отступ (пробрасывается как margin в Card).
  final EdgeInsetsGeometry? margin;

  final VoidCallback? onTap;
  final Widget child;

  const GlassCard({
    super.key,
    this.tint,
    this.radius,
    this.borderWidth = 0.6,
    this.borderColor,
    this.boxShadow,
    this.margin,
    this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseRadius = radius ?? 12.0;
    final baseTint = tint ?? scheme.surfaceContainerLow;
    final shadow = boxShadow ??
        [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ];
    final border = borderColor ?? scheme.outlineVariant.withValues(alpha: 0.6);

    final card = Card(
      elevation: 0,
      margin: margin,
      color: baseTint.withValues(alpha: 0.92),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(baseRadius),
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: border, width: borderWidth),
      ),
      child: onTap == null ? child : InkWell(onTap: onTap, child: child),
    );

    if (shadow.isEmpty) return card;
    return DecoratedBox(
      decoration: BoxDecoration(boxShadow: shadow),
      child: card,
    );
  }
}