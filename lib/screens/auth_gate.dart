import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/responsive_page.dart';
import 'auth_screen.dart';

/// Показывает нижнюю панель «Нужен вход» с кнопками.
/// Возвращает true, если пользователь вошёл (или уже был вошёл).
Future<bool> requireAuth(BuildContext context) {
  final auth = context.read<AuthProvider>();
  if (auth.isSignedIn) return Future.value(true);

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _AuthGateSheet(),
  ).then((done) => done ?? false);
}

class _AuthGateSheet extends StatelessWidget {
  const _AuthGateSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
              alignment: Alignment.center,
            ),
            Icon(Icons.lock_outline, size: 44, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              'Нужно зарегистрироваться',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Чтобы добавлять записи и данные, войдите в аккаунт. '
              'Регистрация бесплатная и займёт минуту.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                final ok = await _openAuth(context);
                if (ok && context.mounted) Navigator.pop(context, true);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Зарегистрироваться'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                final ok = await _openAuth(context);
                if (ok && context.mounted) Navigator.pop(context, true);
              },
              child: const Text('У меня уже есть аккаунт — войти'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _openAuth(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ResponsivePage(child: AuthScreen())),
    );
    return auth.isSignedIn;
  }
}