import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../domain/app_user.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.role = 'student'});

  final String role;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(authControllerProvider.notifier)
        .register(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          role: widget.role,
        );
    if (!mounted) return;
    final state = ref.read(authControllerProvider);
    state.whenOrNull(
      data: (user) {
        if (user == null) return;
        if (user.isStudent) {
          context.go('/student/setup');
        } else {
          context.go(user.homeRoute);
        }
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
    final roleLabel = switch (widget.role) {
      'teacher' => 'Teacher',
      'parent' => 'Parent',
      _ => 'Student',
    };
    return Scaffold(
      appBar: SahlhaAppBar(title: 'Join as $roleLabel'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SahlhaSpacing.page),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Create your account', style: text.headlineSmall),
                const SizedBox(height: SahlhaSpacing.lg),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter your name'
                      : null,
                ),
                const SizedBox(height: SahlhaSpacing.md),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: SahlhaSpacing.md),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 6 characters',
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
                      ? 'Use at least 6 characters'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: SahlhaSpacing.xl),
                SahlhaPrimaryButton(
                  label: 'Create account',
                  loading: loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: SahlhaSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account? '),
                    TextButton(
                      onPressed: () => context.go('/login?role=${widget.role}'),
                      child: const Text('Log in'),
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
