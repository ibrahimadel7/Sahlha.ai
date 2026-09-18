import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/sound_effects.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../../learning_profile/data/learning_profile_repository.dart';
import 'journey_presentation.dart';
import 'widgets/learning_journey.dart' show StudentCanvas;
import 'widgets/playful_background.dart';
import 'widgets/sahlha_avatar.dart';

/// Student profile: clean, same joyful language. Secondary features live
/// here, not in the bottom nav.
class StudentProfileScreen extends ConsumerWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider);
    final profile = ref.watch(learningProfileProvider);
    final name = cleanStudentText(user?.name ?? '');
    final initial = name.isEmpty
        ? 'S'
        : name.trim().characters.first.toUpperCase();

    return Scaffold(
      appBar: const SahlhaAppBar(title: 'Profile'),
      body: PlayfulBackground(
        variant: PlayfulVariant.profile,
        child: StudentCanvas(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                // Decorative header with avatar + name + role.
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFDFFBF6), Color(0xFFFFF3D1)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: SahlhaColors.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: const BoxDecoration(
                          color: SahlhaColors.joyTeal,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initial,
                          style: text.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? 'Student' : name,
                              style: text.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                'Student',
                                style: text.labelSmall?.copyWith(
                                  color: SahlhaColors.joyTealDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SahlhaAvatar(size: 56),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                profile.whenOrNull(
                      data: (p) => SahlhaCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Parent link code',
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Share this code with a parent so they can follow your progress.',
                              style: text.bodySmall?.copyWith(
                                color: SahlhaColors.muted,
                              ),
                            ),
                            const SizedBox(height: SahlhaSpacing.sm),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: SahlhaColors.tealFaint,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: SahlhaColors.tealSoft,
                                      ),
                                    ),
                                    child: Text(
                                      p.linkCode.isEmpty ? '—' : p.linkCode,
                                      style: text.titleLarge?.copyWith(
                                        letterSpacing: 3,
                                        color: SahlhaColors.tealDark,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy_outlined),
                                  onPressed: p.linkCode.isEmpty
                                      ? null
                                      : () {
                                          HapticFeedback.lightImpact();
                                          Clipboard.setData(
                                            ClipboardData(text: p.linkCode),
                                          );
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Code copied — share it with your parent.',
                                                  ),
                                                ),
                                              );
                                        },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ) ??
                    const SizedBox.shrink(),
                const SizedBox(height: 12),
                const _SoundEffectsTile(),
                _Tile(
                  icon: Icons.class_outlined,
                  color: SahlhaColors.skySoft,
                  iconColor: SahlhaColors.skyDark,
                  title: 'My classroom',
                  subtitle: 'See your learning path',
                  onTap: () => context.go('/student/learn'),
                ),
                _Tile(
                  icon: Icons.psychology_outlined,
                  color: SahlhaColors.warmYellowSoft,
                  iconColor: SahlhaColors.warmYellowDeep,
                  title: 'How I learn best',
                  subtitle: 'Review your learning preferences',
                  onTap: () => context.push('/student/setup'),
                ),
                _Tile(
                  icon: Icons.accessibility_new_rounded,
                  color: SahlhaColors.aquaSoft,
                  iconColor: SahlhaColors.joyTealDark,
                  title: 'Accessibility',
                  subtitle: 'Calm motion, larger text',
                  onTap: () => showSahlhaSheet<void>(
                    context,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Comfortable for you',
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sahlha follows your device settings: reduced motion calms the avatar and path, text scales with your system size, and every action stays a large, predictable tap.',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tip: turn on Reduce Motion or larger text in your device settings — Sahlha adapts right away.',
                          style: text.bodySmall?.copyWith(
                            color: SahlhaColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _Tile(
                  icon: Icons.help_outline_rounded,
                  color: SahlhaColors.lavenderSoft,
                  iconColor: SahlhaColors.lavenderDark,
                  title: 'Help & support',
                  subtitle: 'We\u2019re here when you need us',
                  onTap: () => showSahlhaSheet<void>(
                    context,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Help & support',
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Stuck on a step? Try “Help me” inside any lesson, or ask your teacher for a nudge. Learning is better together.',
                        ),
                      ],
                    ),
                  ),
                ),
                _Tile(
                  icon: Icons.settings_outlined,
                  color: const Color(0xFFF1F5F9),
                  iconColor: SahlhaColors.muted,
                  title: 'Settings',
                  subtitle: 'Your learning, your way',
                  onTap: () => context.push('/student/setup'),
                ),
                _Tile(
                  icon: Icons.group_add_outlined,
                  color: SahlhaColors.tealSoft,
                  iconColor: SahlhaColors.joyTealDark,
                  title: 'Join a classroom',
                  onTap: () => context.push('/student/join'),
                ),
                _Tile(
                  icon: Icons.logout_outlined,
                  color: const Color(0xFFFFE8E4),
                  iconColor: const Color(0xFFB63752),
                  title: 'Logout',
                  onTap: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SoundEffectsTile extends ConsumerWidget {
  const _SoundEffectsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(soundEnabledProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: SahlhaSpacing.sm),
      child: SahlhaCard(
        padding: const EdgeInsets.all(SahlhaSpacing.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: SahlhaColors.tealSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                enabled
                    ? Icons.volume_up_outlined
                    : Icons.volume_off_outlined,
                color: SahlhaColors.joyTealDark,
                size: 22,
              ),
            ),
            const SizedBox(width: SahlhaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sound effects',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    enabled
                        ? 'Gentle sounds for answers and celebrations'
                        : 'All sound effects are off',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: enabled,
              onChanged: (value) => ref
                  .read(soundEnabledProvider.notifier)
                  .setEnabled(value),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.color = SahlhaColors.tealSoft,
    this.iconColor = SahlhaColors.teal,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SahlhaSpacing.sm),
      child: SahlhaCard(
        onTap: onTap,
        padding: const EdgeInsets.all(SahlhaSpacing.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: SahlhaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: SahlhaColors.muted),
          ],
        ),
      ),
    );
  }
}
