import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/sahlha_colors.dart';
import 'lesson_content.dart';
import 'sahlha_avatar.dart';

bool _reduced(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    MediaQuery.accessibleNavigationOf(context);

// ---------------------------------------------------------------------------
// ContinueLearningCard — large hero, strongest action on Home.
// Teal/aqua gradient, decorative shapes, real question count + time.
// ---------------------------------------------------------------------------
class ContinueLearningCard extends StatelessWidget {
  const ContinueLearningCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.contextLabel,
    required this.questions,
    this.minutes,
    this.started = false,
    this.progress,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String contextLabel;
  final int questions;
  final int? minutes;
  final bool started;
  final double? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$contextLabel: $title',
      child: Material(
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(26),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFDFFBF6), Color(0xFFBFF0E8)],
              ),
              border: Border.all(
                color: SahlhaColors.aqua.withValues(alpha: 0.5),
              ),
              boxShadow: SahlhaShadows.soft,
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -30,
                  top: -30,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  right: 30,
                  bottom: -40,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: SahlhaColors.warmYellow.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            contextLabel,
                            style: text.titleSmall?.copyWith(
                              color: SahlhaColors.joyTealDark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: SahlhaColors.joyTealDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: SahlhaColors.joyTeal,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.auto_stories_outlined,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  style: text.bodySmall?.copyWith(
                                    color: SahlhaColors.ink.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            color: SahlhaColors.joyTeal,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            started
                                ? Icons.play_arrow_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (minutes != null)
                          QuestionCountChip(
                            icon: Icons.schedule_outlined,
                            label: '~$minutes min',
                          ),
                        if (questions > 0)
                          QuestionCountChip(
                            icon: Icons.assignment_outlined,
                            label: '$questions questions',
                          ),
                        if (started)
                          const QuestionCountChip(
                            icon: Icons.bolt_outlined,
                            label: 'In progress',
                          ),
                      ],
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progress!.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: Colors.white.withValues(alpha: 0.7),
                          valueColor: const AlwaysStoppedAnimation(
                            SahlhaColors.joyTeal,
                          ),
                        ),
                      ),
                    ],
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

class QuestionCountChip extends StatelessWidget {
  const QuestionCountChip({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: SahlhaColors.joyTealDark),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// RecentActivityTile — max 3, colorful meaningful icons, real backend data.
// ---------------------------------------------------------------------------
class RecentActivityTile extends StatelessWidget {
  const RecentActivityTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.state,
    this.onTap,
  });
  final String title;
  final String subtitle;
  final String state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (state) {
      'mastered' => (
        SahlhaColors.successSoft,
        SahlhaColors.success,
        Icons.check_circle_rounded,
      ),
      'developing' => (
        SahlhaColors.aquaSoft,
        SahlhaColors.joyTealDark,
        Icons.auto_stories_outlined,
      ),
      'needs_practice' => (
        SahlhaColors.softCoralSoft,
        SahlhaColors.softCoralDark,
        Icons.refresh_rounded,
      ),
      _ => (
        SahlhaColors.skySoft,
        SahlhaColors.skyDark,
        Icons.lightbulb_outline_rounded,
      ),
    };
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: SahlhaColors.borderSubtle),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: fg, size: 22),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: state == 'mastered'
            ? const Icon(Icons.check, color: SahlhaColors.success)
            : const Icon(
                Icons.chevron_right_rounded,
                color: SahlhaColors.muted,
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SkillConceptPanel — large colorful visual card for lessons.
// ---------------------------------------------------------------------------
class SkillConceptPanel extends StatelessWidget {
  const SkillConceptPanel({
    super.key,
    required this.title,
    required this.child,
    this.accent = SahlhaColors.skySoft,
  });
  final String title;
  final Widget child;
  final Color accent;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, accent.withValues(alpha: 0.6)],
        ),
        border: Border.all(color: SahlhaColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SelectedSkillCard — joyful detail block inside the path.
// Presentation state only; never mutates mastery.
// ---------------------------------------------------------------------------
class SelectedSkillCard extends StatelessWidget {
  const SelectedSkillCard({
    super.key,
    required this.eyebrow,
    required this.message,
    this.cta,
    this.ctaIcon = Icons.arrow_forward_rounded,
    this.onPrimary,
    this.accent = SahlhaColors.joyTeal,
  });
  final String eyebrow;
  final String message;
  final String? cta;
  final IconData ctaIcon;
  final VoidCallback? onPrimary;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final reduced = _reduced(context);
    return AnimatedContainer(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 280),
      width: double.infinity,
      margin: const EdgeInsets.only(left: 64),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SahlhaColors.tealSoft, width: 1.5),
        boxShadow: SahlhaShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  eyebrow,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: accent,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.play_circle_outline_rounded, color: accent, size: 26),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: SahlhaColors.muted, height: 1.5),
          ),
          const SizedBox(height: 10),
          if (cta != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPrimary,
                icon: Icon(ctaIcon, size: 20),
                label: Text(cta!),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.lock_outline_rounded, size: 20),
                label: const Text('Locked for now'),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QuickCheckNode / UnitMasteryNode — joyful wrappers (lavender / trophy).
// ---------------------------------------------------------------------------
class QuickCheckNode extends StatelessWidget {
  const QuickCheckNode({
    super.key,
    this.onTap,
    this.title = 'Quick check',
    this.subtitle = 'A short pause to remember.',
  });
  final VoidCallback? onTap;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return AnimatedContainer(
      duration: _reduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: enabled ? SahlhaColors.lavenderSoft : SahlhaColors.lavenderFaint,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: enabled
              ? SahlhaColors.lavender.withValues(alpha: 0.4)
              : SahlhaColors.borderSubtle,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: enabled ? SahlhaColors.lavender : Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            enabled ? Icons.quiz_outlined : Icons.lock_outline_rounded,
            color: enabled ? Colors.white : SahlhaColors.lavenderDark,
          ),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(subtitle),
        trailing: enabled
            ? const Icon(
                Icons.arrow_forward_rounded,
                color: SahlhaColors.lavenderDark,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

class UnitMasteryNode extends StatelessWidget {
  const UnitMasteryNode({
    super.key,
    required this.ready,
    this.onTap,
    this.mastered = 0,
    this.total = 0,
  });
  final bool ready;
  final VoidCallback? onTap;
  final int mastered;
  final int total;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    margin: const EdgeInsets.only(top: 20),
    decoration: BoxDecoration(
      color: ready ? SahlhaColors.warmYellowSoft : Colors.white,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(
        color: ready ? SahlhaColors.warmYellow : SahlhaColors.borderSubtle,
      ),
      boxShadow: SahlhaShadows.soft,
    ),
    child: Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: ready ? SahlhaColors.warmYellow : SahlhaColors.tealSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(
            ready
                ? Icons.workspace_premium_outlined
                : Icons.lock_outline_rounded,
            color: ready
                ? SahlhaColors.warmYellowDeep
                : SahlhaColors.joyTealDark,
            size: 30,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'MASTERY CHECK',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: SahlhaColors.joyTealDark,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Bring it all together',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          ready
              ? 'Revisit this unit in one calm session.'
              : total > 0
              ? '$mastered of $total skills at mastery — keep going one step at a time.'
              : 'Ready when these skills are mastered and practice is prepared.',
          textAlign: TextAlign.center,
        ),
        if (ready) ...[
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onTap,
            child: const Text('Review this unit'),
          ),
        ],
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Practice: header, answer option, feedback.
// ---------------------------------------------------------------------------
class PracticeProgressHeader extends StatelessWidget {
  const PracticeProgressHeader({
    super.key,
    required this.title,
    required this.index,
    required this.total,
  });
  final String title;
  final int index;
  final int total;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: SahlhaColors.skySoft,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${index + 1} / $total',
                style: text.labelLarge?.copyWith(
                  color: SahlhaColors.skyDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: total == 0 ? 0.0 : (index + 1) / total),
            duration: _reduced(context)
                ? Duration.zero
                : const Duration(milliseconds: 350),
            builder: (_, v, _) => LinearProgressIndicator(
              value: v.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: SahlhaColors.skySoft,
              valueColor: const AlwaysStoppedAnimation(SahlhaColors.joyTeal),
            ),
          ),
        ),
      ],
    );
  }
}

class AnswerOptionCard extends StatelessWidget {
  const AnswerOptionCard({
    super.key,
    required this.label,
    required this.selected,
    this.correct,
    this.onTap,
    this.index = 0,
  });
  final String label;
  final bool selected;
  final bool? correct;
  final VoidCallback? onTap;
  final int index;

  @override
  Widget build(BuildContext context) {
    Color border = SahlhaColors.line;
    Color bg = Colors.white;
    IconData icon = Icons.radio_button_unchecked_rounded;
    Color iconColor = SahlhaColors.muted;
    if (correct == true) {
      border = SahlhaColors.success;
      bg = SahlhaColors.successSoft;
      icon = Icons.check_circle_rounded;
      iconColor = SahlhaColors.success;
    } else if (correct == false && selected) {
      border = SahlhaColors.softCoral;
      bg = SahlhaColors.softCoralSoft;
      icon = Icons.cancel_rounded;
      iconColor = SahlhaColors.softCoralDark;
    } else if (selected) {
      border = SahlhaColors.joyTeal;
      bg = SahlhaColors.aquaSoft;
      icon = Icons.check_circle_rounded;
      iconColor = SahlhaColors.joyTealDark;
    }
    return Semantics(
      selected: selected,
      button: true,
      enabled: onTap != null,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: border,
            width: selected || correct == true ? 2 : 1.2,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FeedbackCard extends StatelessWidget {
  const FeedbackCard({
    super.key,
    required this.correct,
    required this.message,
    this.avatarState = SahlhaAvatarState.happy,
  });
  final bool correct;
  final String message;
  final SahlhaAvatarState avatarState;

  @override
  Widget build(BuildContext context) {
    final reduced = _reduced(context);
    final bg = correct ? SahlhaColors.successSoft : SahlhaColors.softCoralSoft;
    final fg = correct ? SahlhaColors.success : SahlhaColors.softCoralDark;
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SahlhaAvatar(
            size: 52,
            state: correct
                ? SahlhaAvatarState.celebrating
                : SahlhaAvatarState.encouraging,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      correct
                          ? Icons.check_circle_rounded
                          : Icons.favorite_rounded,
                      color: fg,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      correct ? 'Correct!' : 'Not quite',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: fg, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LessonContent(source: message),
              ],
            ),
          ),
        ],
      ),
    );
    if (reduced || !correct) return card;
    // Gentle micro-celebration under ~500ms.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Transform.scale(
        scale: v,
        child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
      ),
      child: card,
    );
  }
}

// ---------------------------------------------------------------------------
// Progress + completion summaries.
// ---------------------------------------------------------------------------
class ProgressStatusCard extends StatelessWidget {
  const ProgressStatusCard({
    super.key,
    required this.count,
    required this.label,
    required this.background,
    required this.foreground,
  });
  final int count;
  final String label;
  final Color background;
  final Color foreground;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: foreground.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: foreground, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class RecentlyImprovedTile extends StatelessWidget {
  const RecentlyImprovedTile({
    super.key,
    required this.title,
    required this.status,
    required this.state,
    this.onTap,
  });
  final String title;
  final String status;
  final String state;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (state) {
      'mastered' => (
        SahlhaColors.successSoft,
        SahlhaColors.success,
        Icons.arrow_upward_rounded,
      ),
      'developing' => (
        SahlhaColors.warmYellowSoft,
        SahlhaColors.warmYellowDeep,
        Icons.trending_up_rounded,
      ),
      _ => (
        SahlhaColors.softCoralSoft,
        SahlhaColors.softCoralDark,
        Icons.refresh_rounded,
      ),
    };
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: SahlhaColors.borderSubtle),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: bg,
          child: Icon(icon, color: fg, size: 20),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          status,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: SahlhaColors.muted),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: SahlhaColors.muted,
        ),
      ),
    );
  }
}

class SkillCompletionSummary extends StatelessWidget {
  const SkillCompletionSummary({
    super.key,
    required this.questions,
    required this.correct,
    required this.elapsed,
  });
  final int questions;
  final int correct;
  final Duration elapsed;
  @override
  Widget build(BuildContext context) {
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${elapsed.inMinutes}:${two(elapsed.inSeconds % 60)}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SahlhaColors.borderSubtle),
        boxShadow: SahlhaShadows.soft,
      ),
      child: Row(
        children: [
          _Stat(Icons.assignment_outlined, '$questions', 'Questions'),
          _Stat(Icons.check_circle_rounded, '$correct/$questions', 'Correct'),
          _Stat(Icons.timer_outlined, time, 'Time'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.value, this.label);
  final IconData icon;
  final String value, label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: SahlhaColors.aquaSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: SahlhaColors.joyTealDark, size: 20),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
