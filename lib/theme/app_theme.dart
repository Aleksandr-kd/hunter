import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Платформо-зависимые темы приложения.
///
/// - **Android** — Material 3: нативные переходы, системные акценты.
/// - **iOS** — «Liquid Glass»-эстетика: прозрачные поверхности,
///   Cupertino-переходы (свайп-назад), крупные закругления.
///
/// Выбор темы происходит по `defaultTargetPlatform`.
class AppTheme {
  AppTheme._();

  static const Color _seed = Color(0xFF2E7D32); // лесной зелёный

  static bool get _isIOS =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  static ThemeData get light => _build(
        Brightness.light,
        isIOS: _isIOS,
      );

  static ThemeData get dark => _build(
        Brightness.dark,
        isIOS: _isIOS,
      );

  static ThemeData _build(Brightness brightness, {required bool isIOS}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    // Крупнее закругления и воздух на iOS.
    final radius = isIOS ? 22.0 : 12.0;

    // Лёгкий, но ощутимый фон вместо чисто-белого: на нём инпуты и карточки
    // читаемее и не сливаются. Светлая тема тоже не «выпадает».
    final isDark = brightness == Brightness.dark;
    final background = isDark
        ? scheme.surface
        : const Color(0xFFEDEFEA);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        surface: background,
      ),
      // На iOS фон непрозрачный — убираем «эффект стекла» при жесте свайпа назад.
      scaffoldBackgroundColor: background,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: const ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: isIOS ? 0 : 2,
        // Компактная высота. На Android статус-бар добавляет свою высоту сверху,
        // поэтому тулбар делаем ещё ниже, чтобы суммарная полоса была небольшой.
        toolbarHeight: isIOS ? 46 : 36,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: isIOS ? 24 : 18,
          fontWeight: FontWeight.w800,
          letterSpacing: isIOS ? -0.4 : 0,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        elevation: isIOS ? 0 : 3,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: isIOS ? 0 : 1,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius * 0.7),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isIOS ? 14 : 8),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: isIOS ? 0.5 : 1,
      ),
    );
  }
}