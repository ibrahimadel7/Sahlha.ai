import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';

class TeacherProfileScreen extends ConsumerWidget {
  const TeacherProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: const SahlhaAppBar(title: 'Profile'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SahlhaSpacing.page),
          children: [
            SahlhaCard(
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: SahlhaColors.tealSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.present_to_all_outlined,
                      color: SahlhaColors.teal,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: SahlhaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.name ?? '', style: text.titleLarge),
                        Text(
                          user?.email ?? '',
                          style: text.bodySmall?.copyWith(
                            color: SahlhaColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SahlhaSpacing.lg),
            SahlhaCard(
              onTap: () => context.push('/teacher/classrooms/new'),
              padding: const EdgeInsets.all(SahlhaSpacing.md),
              child: const Row(
                children: [
                  Icon(Icons.add_circle_outline, color: SahlhaColors.teal),
                  SizedBox(width: SahlhaSpacing.md),
                  Expanded(child: Text('Create classroom')),
                  Icon(Icons.chevron_right, color: SahlhaColors.muted),
                ],
              ),
            ),
            const SizedBox(height: SahlhaSpacing.sm),
            SahlhaCard(
              onTap: () async =>
                  ref.read(authControllerProvider.notifier).logout(),
              padding: const EdgeInsets.all(SahlhaSpacing.md),
              child: const Row(
                children: [
                  Icon(Icons.logout_outlined, color: SahlhaColors.teal),
                  SizedBox(width: SahlhaSpacing.md),
                  Expanded(child: Text('Log out')),
                  Icon(Icons.chevron_right, color: SahlhaColors.muted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
