import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/diary_provider.dart';
import 'calendar_screen.dart';
import 'diary_screen.dart';
import 'profile_screen.dart';
import 'stats_screen.dart';

/// Порог ширины, при котором включается планшетная раскладка (NavigationRail).
const double _wideBreakpoint = 840;

/// Каркас приложения.
///
/// - На телефоне (< [_wideBreakpoint]) — нижняя навигация в стиле маркетплейсов.
/// - На планшете/широких экранах (>= [_wideBreakpoint]) — боковое меню
///   (NavigationRail) и контент в центрированной колонке ограниченной ширины.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _icons = [
    (Icons.calendar_month_outlined, Icons.calendar_month),
    (Icons.menu_book_outlined, Icons.menu_book),
    (Icons.bar_chart_outlined, Icons.bar_chart),
    (Icons.person_outline, Icons.person),
  ];

  static const _labels = ['Сезоны', 'Дневник', 'Статистика', 'Профиль'];

  static const _screens = [
    CalendarScreen(),
    DiaryScreen(),
    StatsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;
        return Scaffold(
          // На широких экранах — боковое меню, на телефоне — нижний бар.
          body: isWide ? _buildWideLayout(context) : _buildPhoneLayout(context),
          bottomNavigationBar:
              isWide ? null : _buildBottomBar(context),
        );
      },
    );
  }

  /// Планшетная раскладка: NavigationRail слева, контент по центру.
  Widget _buildWideLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        NavigationRail(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          labelType: NavigationRailLabelType.all,
          backgroundColor: scheme.surfaceContainerLow,
          selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
          unselectedIconTheme:
              IconThemeData(color: scheme.onSurface),
          selectedLabelTextStyle: TextStyle(
            color: scheme.onSecondaryContainer,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelTextStyle: TextStyle(
            color: scheme.onSurface,
          ),
          destinations: [
            for (int i = 0; i < _labels.length; i++)
              NavigationRailDestination(
                icon: Icon(_icons[i].$1),
                selectedIcon: Icon(_icons[i].$2),
                label: Text(_labels[i]),
              ),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _buildContent(context),
        ),
      ],
    );
  }

  /// Контент (с индикатором синхронизации) в ограниченной по ширине колонке.
  Widget _buildContent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: IndexedStack(
                index: _index,
                children: _screens,
              ),
            ),
          ),
        ),
        Consumer<DiaryProvider>(
          builder: (context, diary, _) {
            if (!diary.syncing) return const SizedBox.shrink();
            return Container(
              color: scheme.primaryContainer.withValues(alpha: 0.25),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text('Синхронизация…',
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  /// Телефонная раскладка: содержимое + индикатор синхронизации.
  Widget _buildPhoneLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(child: _buildIndexedStack()),
        Consumer<DiaryProvider>(
          builder: (context, diary, _) {
            if (!diary.syncing) return const SizedBox.shrink();
            return Container(
              color: scheme.primaryContainer.withValues(alpha: 0.25),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text('Синхронизация…',
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildIndexedStack() => IndexedStack(
        index: _index,
        children: _screens,
      );

  /// Нижний бар (телефон).
  Widget _buildBottomBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = scheme.surfaceContainerHigh;
    return Container(
      decoration: BoxDecoration(
        color: barColor,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 0.8,
          ),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                for (int i = 0; i < _labels.length; i++) ...[
                  Expanded(
                    child: _NavTab(
                      icon: _icons[i].$1,
                      selectedIcon: _icons[i].$2,
                      label: _labels[i],
                      selected: _index == i,
                      onTap: () => setState(() => _index = i),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Вкладка нижнего бара: активная в виде капсулы, как в Авито/hh.
class _NavTab extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Выбранная капсула всегда белая → иконка всегда тёмная для контраста.
    final color = selected ? const Color(0xFF1C1B1F) : scheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        // У активной вкладки капсула выше (выступает) и меньше закругление.
        padding: EdgeInsets.symmetric(
          horizontal: 22,
          vertical: selected ? 6 : 0,
        ),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(selected ? 12 : 12),
        ),
        child: Icon(selected ? selectedIcon : icon,
            color: color, size: selected ? 22 : 16),
      ),
    );
  }
}