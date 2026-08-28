import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/diary_provider.dart';
import '../services/supabase_service.dart';

/// Экран входа/регистрации по email + паролю.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _isRegister = false;
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    String? error;
    if (_isRegister) {
      error = await auth.signUp(
        _email.text.trim().toLowerCase(),
        _password.text,
      );
    } else {
      error = await auth.signIn(
        _email.text.trim().toLowerCase(),
        _password.text,
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (error == null) {
      // Синхронизация дневника после входа.
      context.read<DiaryProvider>().syncWithServer();
      Navigator.of(context).pop();
    } else if (error == 'confirm') {
      _showMessage('Проверьте почту для подтверждения регистрации');
    } else {
      _showMessage(error);
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    // Если Supabase не настроен — показать сообщение.
    if (!SupabaseService.isReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('Вход')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Вход временно недоступен'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isRegister ? 'Регистрация' : 'Вход')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: wide ? 520 : constraints.maxWidth,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(20),
                  children: [
                    const SizedBox(height: 8),
                    Form(
                      key: _form,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (v) => v == null || !v.contains('@')
                                ? 'Введите корректный email'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'Пароль',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Введите пароль'
                                : null,
                          ),
                          if (_isRegister) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirm,
                              obscureText: _obscure,
                              decoration: const InputDecoration(
                                labelText: 'Повторите пароль',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              validator: (v) => v != _password.text
                                  ? 'Пароли не совпадают'
                                  : null,
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: _busy
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white),
                                      )
                                    : Text(_isRegister ? 'Зарегистрироваться'
                                        : 'Войти'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(() {
                        _isRegister = !_isRegister;
                        _confirm.clear();
                      }),
                      child: Text(_isRegister
                          ? 'Уже есть аккаунт? Войти'
                          : 'Нет аккаунта? Зарегистрироваться'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}