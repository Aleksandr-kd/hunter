import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/lock_provider.dart';
import '../screens/lock_screen.dart';

/// Обёртка над содержимым приложения: блокирует по биометрии при
/// сворачивании (если LockProvider.enabled) и показывает лок-экран.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      context.read<LockProvider>().lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LockProvider>(
      builder: (context, lock, child) => Stack(
        fit: StackFit.expand,
        children: [
          child!,
          if (lock.locked) const LockScreen(),
        ],
      ),
      child: widget.child,
    );
  }
}