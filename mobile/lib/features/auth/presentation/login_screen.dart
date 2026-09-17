import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../domain/app_user.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.role = 'student'});

  final String role;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(authControllerProvider.notifier)
        .login(email: _email.text.trim(), password: _password.text);
    if (!mounted) return;
    final state = ref.read(authControllerProvider);
    state.whenOrNull(
      data: (user) {
        if (user != null) context.go(user.homeRoute);
      },
      error: (e, _) =>
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString()))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final loading = ref.watch(authControllerProvider).isLoading;
    return Scaffold(
      appBar: const SahlhaAppBar(title: 'Welcome back'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SahlhaSpacing.page),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SahlhaLogo(size: 52),
                const SizedBox(height: SahlhaSpacing.xl),
                Text('Log in to Sahlha', style: text.headlineSmall),
                const SizedBox(height: SahlhaSpacing.lg),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'you@example.com',
                  ),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Enter your email'
                      : null,
                ),
                const SizedBox(height: SahlhaSpacing.md),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 6)
                      ? 'Enter your password'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: SahlhaSpacing.xl),
                SahlhaPrimaryButton(
                  label: 'Log in',
                  loading: loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: SahlhaSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account? "),
                    TextButton(
                      onPressed: () =>
                          context.go('/register?role=${widget.role}'),
                      child: const Text('Sign up'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
