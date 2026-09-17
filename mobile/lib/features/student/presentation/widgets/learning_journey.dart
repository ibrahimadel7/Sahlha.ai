import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/sahlha_colors.dart';
import '../journey_presentation.dart';

const _teal = SahlhaColors.tealDark;

class StudentCanvas extends StatelessWidget {
  const StudentCanvas({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style?.copyWith(
            shape: WidgetStatePropertyAll(shape),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: theme.outlinedButtonTheme.style?.copyWith(
            shape: WidgetStatePropertyAll(shape),
          ),
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: child,
        ),
      ),
    );
  }
}

class JourneyEyebrow extends StatelessWidget {
  const JourneyEyebrow(this.text, {super.key, this.color = _teal});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: color,
      letterSpacing: 1.5,
      fontWeight: FontWeight.w700,
    ),
  );
}

class UnitProgressBar extends StatelessWidget {
  const UnitProgressBar({
    super.key,
    required this.completed,
    required this.total,
  });
  final int completed;
  final int total;
  @override
  Widget build(BuildContext context) {
    final value = total > 0 ? (completed / total).clamp(0, 1) : 0.0;
    return Semantics(
      label: '$completed of $total skills mastered',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value.toDouble()),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          builder: (context, animated, _) => LinearProgressIndicator(
            value: animated,
            minHeight: 8,
            color: _teal,
            backgroundColor: SahlhaColors.tealSoft,
          ),
        ),
      ),
    );
  }
}

/// A small original book graphic, built with Flutter shapes (no motion).
class LearningMark extends StatelessWidget {
  const LearningMark({super.key, this.size = 62});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SahlhaColors.sunSoft,
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Icon(Icons.auto_stories_rounded, size: size * .54, color: _teal),
    ),
  );
}

class LearningUnitHeader extends StatelessWidget {
  const LearningUnitHeader({super.key, required this.unit, this.subject = ''});
  final JourneyUnit unit;

  /// Free-text subject used for the meaningful unit visual. Empty falls
  /// back to the book mark.
  final String subject;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: SahlhaColors.borderSubtle),
          boxShadow: SahlhaShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: SahlhaColors.aquaSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.route_rounded,
                    color: SahlhaColors.joyTealDark,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        unit.title,
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Unit ${unit.number} · ${unit.mastered} / ${unit.steps.length} skills completed',
                        style: text.bodySmall?.copyWith(
                          color: SahlhaColors.joyTealDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            UnitProgressBar(completed: unit.mastered, total: unit.steps.length),
          ],
        ),
      ),
    );
  }
}

class CurrentSkillCard extends StatelessWidget {
  const CurrentSkillCard({
    super.key,
    required this.title,
    required this.onContinue,
    this.contextLabel = 'Continue learning',
    this.subtitle = '',
    this.started = false,
    this.onTap,
    this.progress,
    this.effort,
    this.questions = 0,
    this.minutes,
  });
  final String title, contextLabel, subtitle;
  final bool started;
  final VoidCallback onContinue;
  final VoidCallback? onTap;
  final double? progress;
  final String? effort;
  final int questions;
  final int? minutes;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      borderRadius: BorderRadius.circular(26),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? onContinue,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFDFFBF6), Color(0xFFB9EEE5)],
            ),
            border: Border.all(
              color: SahlhaColors.aqua.withValues(alpha: 0.55),
            ),
            boxShadow: SahlhaShadows.soft,
          ),
          child: Stack(
            children: [
              Positioned(
                right: -28,
                top: -28,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                right: 36,
                bottom: -36,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: SahlhaColors.warmYellow.withValues(alpha: 0.28),
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
                            if (effort != null)
                              Text(
                                effort!,
                                style: text.bodySmall?.copyWith(
                                  color: SahlhaColors.joyTealDark,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: SahlhaColors.joyTeal,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                  if (minutes != null || questions > 0) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (minutes != null)
                          _MetaPill(Icons.schedule_outlined, '~$minutes min'),
                        if (questions > 0)
                          _MetaPill(
                            Icons.assignment_outlined,
                            '$questions questions',
                          ),
                        if (started)
                          const _MetaPill(
                            Icons.bolt_outlined,
                            'In progress',
                            highlight: true,
                          ),
                      ],
                    ),
                  ],
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
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill(this.icon, this.label, {this.highlight = false});
  final IconData icon;
  final String label;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: highlight
          ? SahlhaColors.warmYellowSoft
          : Colors.white.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(12),
      border: highlight
          ? Border.all(color: SahlhaColors.warmYellow.withValues(alpha: 0.6))
          : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: highlight ? SahlhaColors.warmYellowDeep : _teal,
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class SkillStatusIndicator extends StatelessWidget {
  const SkillStatusIndicator({super.key, required this.state});
  final JourneyState state;
  @override
  Widget build(BuildContext context) => Text(switch (state) {
    JourneyState.completed => 'Completed',
    JourneyState.current => 'Your next step',
    JourneyState.available => 'Explore',
    JourneyState.locked => 'Coming later',
  }, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _teal));
}

class LearningPathNode extends StatelessWidget {
  const LearningPathNode({
    super.key,
    required this.step,
    required this.onTap,
    this.selected = false,
  });
  final JourneyStep step;
  final VoidCallback? onTap;

  /// Presentation-only emphasis. Independent from progression state:
  /// a completed node can be completed + selected, a locked one locked +
  /// selected. Selecting never changes backend mastery.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final completed = step.state == JourneyState.completed;
    final locked = step.state == JourneyState.locked;
    final current = step.state == JourneyState.current;
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final node = AnimatedContainer(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 300),
      width: current ? 60 : 54,
      height: current ? 60 : 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: completed
            ? SahlhaColors.joyTeal
            : current
            ? SahlhaColors.warmYellow
            : locked
            ? const Color(0xFFF1F5F9)
            : Colors.white,
        border: Border.all(
          color: completed
              ? SahlhaColors.joyTealDark
              : current
              ? SahlhaColors.joyTeal
              : selected
              ? SahlhaColors.joyTeal
              : const Color(0xFFDEE2E5),
          width: current ? 3.5 : 2.2,
        ),
        boxShadow: current && !reduced
            ? [
                BoxShadow(
                  color: SahlhaColors.warmYellow.withValues(alpha: 0.55),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
                ...SahlhaShadows.soft,
              ]
            : selected
            ? SahlhaShadows.soft
            : null,
      ),
      child: AnimatedSwitcher(
        duration: reduced ? Duration.zero : const Duration(milliseconds: 280),
        child: Icon(
          key: ValueKey('${step.state.name}-$selected'),
          completed
              ? Icons.check_rounded
              : locked
              ? Icons.lock_outline_rounded
              : current
              ? Icons.lightbulb_rounded
              : Icons.lightbulb_outline_rounded,
          color: completed
              ? Colors.white
              : current
              ? SahlhaColors.warmYellowDeep
              : locked
              ? SahlhaColors.muted
              : SahlhaColors.joyTealDark,
          size: current ? 28 : 24,
        ),
      ),
    );

    Widget circle = node;
    // Gentle pulse for the current skill only (disabled with reduced motion).
    if (current && !reduced) {
      circle = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 1800),
        builder: (_, v, child) {
          // Subtle repeating glow via parent Stateful? Use static glow here;
          // the LearningPath rebuilds on selection so this stays calm.
          return child!;
        },
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: SahlhaColors.joyTeal.withValues(alpha: 0.25),
              width: 3,
            ),
          ),
          child: node,
        ),
      );
    }

    return Semantics(
      selected: selected,
      button: true,
      label: '${step.title}, ${step.state.name}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : const Duration(milliseconds: 280),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white
                : current
                ? SahlhaColors.warmYellowSoft.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: selected
                ? Border.all(color: SahlhaColors.tealSoft, width: 1.5)
                : null,
            boxShadow: selected ? SahlhaShadows.soft : null,
          ),
          child: Row(
            children: [
              circle,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: current || selected
                            ? FontWeight.w800
                            : FontWeight.w700,
                        color: locked ? SahlhaColors.muted : SahlhaColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (current)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: SahlhaColors.joyTeal,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'Next up',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      )
                    else
                      SkillStatusIndicator(state: step.state),
                    if (step.skill.practiceQuestions > 0 &&
                        (current || selected))
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '${step.skill.practiceQuestions} questions',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: SahlhaColors.muted,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detail card for the currently selected path step. The content follows
/// the step's progression state; selection itself never changes mastery.
class LearningPathSkillBlock extends StatelessWidget {
  const LearningPathSkillBlock({
    super.key,
    required this.step,
    required this.prerequisiteTitle,
    required this.onPrimary,
  });

  final JourneyStep step;

  /// Title of the step to finish first (locked steps). Empty when unknown.
  final String prerequisiteTitle;

  /// Opens the lesson (completed/current/available). Null for locked steps.
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final (eyebrow, message, cta, ctaIcon) = switch (step.state) {
      JourneyState.completed => (
        'COMPLETED',
        'You\u2019ve completed this skill.',
        'Review skill',
        Icons.refresh_rounded,
      ),
      JourneyState.current => (
        'YOUR NEXT STEP',
        'One small step. Take it at your pace.',
        'Continue',
        Icons.arrow_forward_rounded,
      ),
      JourneyState.available => (
        'READY WHEN YOU ARE',
        'Build on what you have learned.',
        'Start skill',
        Icons.arrow_forward_rounded,
      ),
      JourneyState.locked => (
        'COMING UP',
        prerequisiteTitle.isEmpty
            ? 'Finish the earlier steps to open this one.'
            : 'Complete \u201C$prerequisiteTitle\u201D first.',
        null,
        Icons.lock_outline_rounded,
      ),
    };
    final accent = switch (step.state) {
      JourneyState.completed => SahlhaColors.joyTeal,
      JourneyState.current => SahlhaColors.joyTeal,
      JourneyState.available => SahlhaColors.skyDark,
      JourneyState.locked => SahlhaColors.muted,
    };
    return AnimatedSize(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: reduced ? Duration.zero : const Duration(milliseconds: 280),
        width: double.infinity,
        margin: const EdgeInsets.only(left: 64),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: step.state == JourneyState.current
              ? SahlhaColors.warmYellowSoft.withValues(alpha: 0.6)
              : SahlhaColors.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: step.state == JourneyState.current
                ? SahlhaColors.warmYellow
                : SahlhaColors.tealSoft,
            width: 1.5,
          ),
          boxShadow: SahlhaShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: JourneyEyebrow(eyebrow, color: accent)),
                AnimatedSwitcher(
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  child: Icon(
                    key: ValueKey(step.state.name),
                    switch (step.state) {
                      JourneyState.completed => Icons.check_circle_rounded,
                      JourneyState.locked => Icons.lock_outline_rounded,
                      _ => Icons.play_circle_outline_rounded,
                    },
                    color: accent,
                    size: 28,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              step.title,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: text.bodyMedium?.copyWith(
                color: SahlhaColors.muted,
                height: 1.5,
              ),
            ),
            if (step.state == JourneyState.current &&
                step.skill.practiceQuestions > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    _MetaPill(
                      Icons.assignment_outlined,
                      '${step.skill.practiceQuestions} questions',
                    ),
                    _MetaPill(
                      Icons.schedule_outlined,
                      '~${((step.skill.description.split(RegExp(r'\s+')).length / 150) + step.skill.practiceQuestions * .6).ceil().clamp(1, 60)} min',
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (cta != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onPrimary,
                  icon: Icon(ctaIcon, size: 20),
                  label: Text(cta),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 52),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: Icon(ctaIcon, size: 20),
                  label: const Text('Locked for now'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LearningPathConnector extends StatelessWidget {
  const LearningPathConnector({
    super.key,
    required this.from,
    required this.to,
    required this.state,
  });
  final double from;
  final double to;
  final JourneyState state;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 20,
      width: double.infinity,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          end: state == JourneyState.completed
              ? _teal
              : const Color(0xFFDDD8CE),
        ),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 350),
        builder: (_, color, _) =>
            CustomPaint(painter: _ConnectorPainter(from, to, color ?? _teal)),
      ),
    ),
  );
}

class _ConnectorPainter extends CustomPainter {
  const _ConnectorPainter(this.from, this.to, this.color);
  final double from, to;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    const start = 33.0;
    const end = 33.0;
    final path = Path()
      ..moveTo(start, 0)
      ..cubicTo(
        start,
        size.height * .5,
        end,
        size.height * .5,
        end,
        size.height,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) =>
      old.from != from || old.to != to || old.color != color;
}

/// A Quick Check on the path: a short, low-pressure revisit of recent
/// steps once they have real attempts. Locked (null [onTap]) until then.
/// Lavender milestone, visually unique from skill nodes.
class CheckpointNode extends StatelessWidget {
  const CheckpointNode({
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
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: enabled ? SahlhaColors.lavenderSoft : SahlhaColors.lavenderFaint,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: enabled
              ? SahlhaColors.lavender.withValues(alpha: 0.45)
              : SahlhaColors.borderSubtle,
        ),
        boxShadow: enabled ? SahlhaShadows.soft : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: enabled ? SahlhaColors.lavender : Colors.white,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            enabled ? Icons.quiz_outlined : Icons.lock_outline_rounded,
            color: enabled ? Colors.white : SahlhaColors.lavenderDark,
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: SahlhaColors.lavenderDark),
        ),
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

class MasteryNode extends StatelessWidget {
  const MasteryNode({
    super.key,
    required this.ready,
    this.onTap,
    this.mastered = 0,
    this.total = 0,
  });
  final bool ready;
  final VoidCallback? onTap;

  /// Unit progress shown under the title (0/0 hides the line).
  final int mastered;
  final int total;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    margin: const EdgeInsets.only(top: 22),
    decoration: BoxDecoration(
      color: ready ? SahlhaColors.warmYellowSoft : Colors.white,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(
        color: ready ? SahlhaColors.warmYellow : SahlhaColors.borderSubtle,
      ),
      boxShadow: SahlhaShadows.soft,
    ),
    child: Column(
      children: [
        Container(
          width: 62,
          height: 62,
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
        const SizedBox(height: 12),
        const JourneyEyebrow('MASTERY CHECK'),
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
              ? 'Revisit this unit in one calm practice session.'
              : total > 0
              ? '$mastered of $total skills at mastery — keep going one step at a time.'
              : 'Ready when these skills are mastered and practice is prepared.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: SahlhaColors.muted),
        ),
        if (ready) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.auto_awesome_rounded, size: 20),
            label: const Text('Review this unit'),
          ),
        ],
      ],
    ),
  );
}

class LearningPath extends StatefulWidget {
  const LearningPath({
    super.key,
    required this.unit,
    required this.openSkill,
    required this.openCheckpoint,
    required this.openMastery,
  });
  final JourneyUnit unit;
  final ValueChanged<JourneyStep> openSkill, openCheckpoint;
  final VoidCallback openMastery;
  @override
  State<LearningPath> createState() => _LearningPathState();
}

class _LearningPathState extends State<LearningPath> {
  bool _earlier = false;
  int _extra = 0;

  /// Presentation-only selection. Defaults to the backend-recommended
  /// skill; tapping any node moves the detail block there. Selecting
  /// never completes, unlocks, or resets anything server-side.
  String? _selectedId;
  final _blockKey = GlobalKey();

  /// First step worth showing in the detail block when the backend names no
  /// recommended skill (e.g. everything mastered): the first open step,
  /// else the first step, so the block is never empty.
  String? _defaultSelection(JourneyUnit unit) {
    if (unit.steps.isEmpty) return null;
    return unit.current?.skill.skillId ??
        unit.steps
            .where((s) => s.state != JourneyState.locked)
            .firstOrNull
            ?.skill
            .skillId ??
        unit.steps.first.skill.skillId;
  }

  @override
  void initState() {
    super.initState();
    _selectedId = _defaultSelection(widget.unit);
  }

  @override
  void didUpdateWidget(LearningPath oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCurrent = oldWidget.unit.current?.skill.skillId;
    final newCurrent = widget.unit.current?.skill.skillId;
    final stillThere = widget.unit.steps.any(
      (s) => s.skill.skillId == _selectedId,
    );
    if (oldWidget.unit.source.materialId != widget.unit.source.materialId ||
        oldCurrent != newCurrent ||
        !stillThere) {
      _earlier = false;
      _extra = 0;
      // Backend progress changed (e.g. a skill was mastered): follow the
      // new recommendation instead of clinging to a stale selection.
      // An explicit user selection survives plain data refreshes above.
      _selectedId = _defaultSelection(widget.unit);
    }
  }

  double _offset(JourneyStep step) => 0;

  void _select(JourneyStep step) {
    if (_selectedId == step.skill.skillId) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedId = step.skill.skillId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _blockKey.currentContext;
      if (context == null || !context.mounted) return;
      try {
        Scrollable.ensureVisible(
          context,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: 0.3,
        );
      } catch (_) {
        // Scrolling is a nicety; the block is already visible in-flow.
      }
    });
  }

  /// Nearest earlier step that is not completed yet, for locked explanations.
  String _prerequisiteTitle(JourneyUnit unit, JourneyStep step) {
    for (var i = step.index - 1; i >= 0; i--) {
      final earlier = unit.steps[i];
      if (earlier.state != JourneyState.completed) return earlier.title;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    final steps = unit.steps;
    final selected = steps
        .where((s) => s.skill.skillId == _selectedId)
        .firstOrNull;
    final focus = unit.current?.index ?? 0;
    final start = _earlier ? 0 : (focus - 1).clamp(0, steps.length);
    final end = (focus + 4 + _extra).clamp(0, steps.length);
    final children = <Widget>[];
    var bridgeFromCenter = false;
    JourneyStep? previous = start > 0 ? steps[start - 1] : null;
    for (var i = start; i < end; i++) {
      final step = steps[i];
      final off = _offset(step);
      if (previous != null) {
        // The connector either links two neighbouring nodes, or runs
        // from the selected detail block back onto the journey.
        children.add(
          LearningPathConnector(
            from: bridgeFromCenter ? 0 : _offset(previous),
            to: off,
            state: previous.state,
          ),
        );
      }
      bridgeFromCenter = false;
      children.add(
        Align(
          alignment: Alignment(off, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: LearningPathNode(
              step: step,
              selected: selected?.skill.skillId == step.skill.skillId,
              onTap: () => _select(step),
            ),
          ),
        ),
      );
      if (selected?.skill.skillId == step.skill.skillId) {
        // The detail block lives ON the path: a connector runs into it
        // and another one carries the journey onwards.
        children.add(
          LearningPathConnector(from: off, to: 0, state: step.state),
        );
        // NOTE: no AnimatedSize here on purpose — combining it with the
        // scroll-into-view below mutates layout mid-frame and throws.
        // The fade keeps the change gentle.
        children.add(
          AnimatedSwitcher(
            key: _blockKey,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: LearningPathSkillBlock(
              key: ValueKey('block:${step.skill.skillId}'),
              step: step,
              prerequisiteTitle: _prerequisiteTitle(unit, step),
              onPrimary: step.state == JourneyState.locked
                  ? null
                  : () => widget.openSkill(step),
            ),
          ),
        );
        bridgeFromCenter = true;
      }
      previous = step;
      if ((i + 1) % 3 == 0 && i + 1 < steps.length) {
        children.add(
          CheckpointNode(
            subtitle: unit.checkpointAfter(i + 1) == null
                ? 'After practicing these steps.'
                : 'Mix your practiced skills.',
            onTap: unit.checkpointAfter(i + 1) == null
                ? null
                : () => widget.openCheckpoint(unit.checkpointAfter(i + 1)!),
          ),
        );
      }
    }
    if (bridgeFromCenter) {
      children.add(
        LearningPathConnector(
          from: 0,
          to: 0,
          state: selected?.state ?? JourneyState.available,
        ),
      );
    }
    return Column(
      children: [
        if (start > 0)
          TextButton(
            onPressed: () => setState(() => _earlier = true),
            child: Text('See $start earlier ${start == 1 ? 'step' : 'steps'}'),
          ),
        const SizedBox(height: 16),
        ...children,
        if (end < steps.length)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: TextButton(
              onPressed: () => setState(() => _extra += 3),
              child: const Text('See what comes next'),
            ),
          ),
        MasteryNode(
          ready: unit.masteryReady,
          onTap: widget.openMastery,
          mastered: unit.mastered,
          total: unit.steps.length,
        ),
      ],
    );
  }
}

class JourneyLoading extends StatelessWidget {
  const JourneyLoading({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading your learning path',
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            height: 115,
            decoration: BoxDecoration(
              color: SahlhaColors.tealSoft,
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Getting your next step ready…'),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Align(
                alignment: Alignment(i.isEven ? -.35 : .35, 0),
                child: Container(
                  width: 66,
                  height: 62,
                  decoration: BoxDecoration(
                    color: SahlhaColors.line,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
