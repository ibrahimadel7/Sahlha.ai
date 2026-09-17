import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';

class ChooseRoleScreen extends StatefulWidget {
  const ChooseRoleScreen({super.key});

  @override
  State<ChooseRoleScreen> createState() => _ChooseRoleScreenState();
}

class _ChooseRoleScreenState extends State<ChooseRoleScreen> {
  String _role = 'student';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const SahlhaAppBar(title: 'I am a…'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SahlhaSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RoleCard(
                role: 'student',
                title: 'Student',
                subtitle: 'Learn and grow',
                icon: Icons.school_outlined,
                selected: _role == 'student',
                onTap: () => setState(() => _role = 'student'),
              ),
              const SizedBox(height: SahlhaSpacing.md),
              _RoleCard(
                role: 'teacher',
                title: 'Teacher',
                subtitle: 'Teach and support',
                icon: Icons.present_to_all_outlined,
                selected: _role == 'teacher',
                onTap: () => setState(() => _role = 'teacher'),
              ),
              const SizedBox(height: SahlhaSpacing.md),
              _RoleCard(
                role: 'parent',
                title: 'Parent',
                subtitle: 'Support my child',
                icon: Icons.favorite_outline,
                selected: _role == 'parent',
                onTap: () => setState(() => _role = 'parent'),
              ),
              const Spacer(),
              SahlhaPrimaryButton(
                label: 'Continue',
                onPressed: () => context.go('/register?role=$_role'),
              ),
              const SizedBox(height: SahlhaSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: () => context.go('/login?role=$_role'),
                  child: Text(
                    'I already have an account',
                    style: text.bodyMedium?.copyWith(
                      color: SahlhaColors.tealDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String role;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(SahlhaSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? SahlhaColors.tealSoft : SahlhaColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? SahlhaColors.teal : SahlhaColors.line,
            width: selected ? 2 : 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? SahlhaColors.teal : SahlhaColors.tealSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : SahlhaColors.teal,
              ),
            ),
            const SizedBox(width: SahlhaSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                Text(
                  subtitle,
                  style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
                ),
              ],
            ),
            const Spacer(),
            if (selected)
              const Icon(Icons.check_circle, color: SahlhaColors.teal),
          ],
        ),
      ),
    );
  }
}
