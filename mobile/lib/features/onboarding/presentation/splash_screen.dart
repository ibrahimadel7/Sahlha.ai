import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_decide);
  }

  Future<void> _decide() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final auth = ref.read(authControllerProvider);
    final user = auth.value;
    if (user == null) {
      context.go('/onboarding');
    } else {
      context.go(user.homeRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SahlhaFullLogo(width: 240),
              const SizedBox(height: SahlhaSpacing.xl),
              Text(
                'Same curriculum.',
                style: text.titleMedium?.copyWith(color: SahlhaColors.muted),
              ),
              Text(
                'Different path to mastery.',
                style: text.titleMedium?.copyWith(color: SahlhaColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
