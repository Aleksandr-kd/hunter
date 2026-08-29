import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/lock_provider.dart';
import '../services/biometric_service.dart';
import '../widgets/responsive_page.dart';
import 'auth_screen.dart';

/// Полноэкранный лок-экран поверх приложения: вход по биометрии
/// (Face ID / Touch ID / отпечаток) или пароль аккаунта как запасной вариант.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _unlock();
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _hint = null;
    });
    final ok = await BiometricService.instance.authenticate();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      context.read<LockProvider>().unlock();
    } else {
      setState(() =>
          _hint = 'Не получилось. Попробуйте ещё раз или войдите с паролем аккаунта.');
    }
  }

  /// Запасной вход через Supabase (email + пароль).
  Future<void> _loginWithPassword() async {
    final auth = context.read<AuthProvider>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ResponsivePage(child: AuthScreen()),
      ),
    );
    if (!mounted) return;
    if (auth.isSignedIn) {
      context.read<LockProvider>().unlock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 56, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Охотник',
                    style: textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Приложение заблокировано\nРазблокируйте, чтобы продолжить',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.fingerprint),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(_busy ? 'Проверяем…' : 'Разблокировать'),
                      ),
                      onPressed: _busy ? null : _unlock,
                    ),
                  ),
                  if (_hint != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _hint!,
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _loginWithPassword,
                    child: const Text('Войти с паролем аккаунта'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}