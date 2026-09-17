import 'sahlha_companion.dart';
export 'sahlha_companion.dart';

import 'package:flutter/material.dart';

import '../../../../core/theme/sahlha_colors.dart';
import '../../../../core/theme/sahlha_spacing.dart';

// ---------------------------------------------------------------------------
// Student engagement helpers + components.
//
// Calm, non-gamified motivation built from REAL backend data: mastery states,
// practice scores, submitted-practice timestamps. No XP, coins, hearts,
// leaderboards, or streaks — effort and understanding are the whole story.
// Everything pure here is unit-tested (see test/engagement_test.dart).
// ---------------------------------------------------------------------------

// ------------------------------------------------------------- effort labels

/// Calm effort label for a backend mastery state. Never judgmental.
String effortLabelForMastery(String state) => switch (state) {
  'mastered' => 'Solid understanding',
  'developing' => 'Growing steadily',
  'needs_practice' => 'Needs a little more time',
  'locked' => 'Coming later',
  _ => 'Not started yet',
};

/// Calm effort label for a practice score in 0..1. Praises effort, not talent.
String effortLabelForScore(double score) {
  if (score >= 0.8) return 'Careful, steady work';
  if (score >= 0.5) return 'Good effort — keep going';
  if (score > 0) return 'Every try counts';
  return 'A brave first try';
}

// ------------------------------------------------------------------- dates

/// Parse a backend ISO timestamp defensively (null when unusable).
DateTime? tryParseStamp(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso)?.toLocal();
}

bool _isSameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whether [iso] (backend ISO timestamp) falls on the device-local [now] day.
bool practicedToday(String? iso, {DateTime? now}) {
  final when = tryParseStamp(iso);
  if (when == null) return false;
  return _isSameLocalDay(when, (now ?? DateTime.now()).toLocal());
}

/// 'Today' / 'Yesterday' / 'N days ago' for a backend timestamp.
/// Empty string when unknown — callers render nothing instead of guessing.
String relativeDayLabel(String? iso, {DateTime? now}) {
  final when = tryParseStamp(iso);
  if (when == null) return '';
  final today = (now ?? DateTime.now()).toLocal();
  final a = DateTime(today.year, today.month, today.day);
  final b = DateTime(when.year, when.month, when.day);
  final days = a.difference(b).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return '$days days ago';
}

// ---------------------------------------------------------------- daily goal

/// One small, honest daily goal derived from real backend data.
class DailyGoal {
  const DailyGoal({
    required this.doneToday,
    required this.hasStep,
    required this.title,
    required this.message,
  });

  final bool doneToday;
  final bool hasStep;
  final String title;
  final String message;
}

/// The goal is always "one learning step". Done when real submitted
/// practice exists for today — never invented, never a streak.
DailyGoal dailyGoalFor({
  required bool hasStep,
  String? recentPracticedAt,
  String? stepTitle,
  DateTime? now,
}) {
  final done = practicedToday(recentPracticedAt, now: now);
  if (!hasStep) {
    return const DailyGoal(
      doneToday: false,
      hasStep: false,
      title: 'Your path is being prepared',
      message: 'New steps will appear here when they are ready.',
    );
  }
  if (done) {
    return const DailyGoal(
      doneToday: true,
      hasStep: true,
      title: 'Today’s step is done',
      message: 'Nice, steady work. Rest, or explore your path a little more.',
    );
  }
  final clean = (stepTitle ?? '').trim();
  return DailyGoal(
    doneToday: false,
    hasStep: true,
    title: 'Today’s goal: one learning step',
    message: clean.isEmpty
        ? 'A few focused minutes at your own pace.'
        : '“$clean” is waiting — a few focused minutes.',
  );
}

/// Latest usable backend timestamp out of many (home cards carry one per
/// classroom). Null when nothing was ever practiced — a first-day state.
String? mostRecentStamp(Iterable<String?> stamps) {
  DateTime? best;
  String? raw;
  for (final stamp in stamps) {
    final parsed = tryParseStamp(stamp);
    if (parsed == null) continue;
    if (best == null || parsed.isAfter(best)) {
      best = parsed;
      raw = stamp;
    }
  }
  return raw;
}

// ---------------------------------------------------------- subject visuals

/// Meaningful visual identity for a subject, drawn from the existing calm
/// palette. Pure data — the widget is [SubjectSpot].
class SubjectVisual {
  const SubjectVisual({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
}

/// Map free-text subject names (any language the backend may carry) to a
/// calm, recognizable visual. Unknown subjects get the book mark.
SubjectVisual subjectVisualFor(String subject) {
  final s = subject.toLowerCase();
  bool hasAny(List<String> keys) => keys.any(s.contains);
  if (hasAny(['math', 'حساب', 'رياض', 'arith', 'fraction', 'geometry'])) {
    return const SubjectVisual(
      icon: Icons.calculate_rounded,
      background: SahlhaColors.tealSoft,
      foreground: SahlhaColors.tealDark,
    );
  }
  if (hasAny(['code', 'program', 'python', 'computer', 'حاسوب', 'برمج'])) {
    return const SubjectVisual(
      icon: Icons.code_rounded,
      background: SahlhaColors.infoSoft,
      foreground: SahlhaColors.info,
    );
  }
  if (hasAny([
    'arab',
    'english',
    'language',
    'read',
    'لغة',
    'عربي',
    'grammar',
    'writing',
  ])) {
    return const SubjectVisual(
      icon: Icons.menu_book_rounded,
      background: SahlhaColors.sunSoft,
      foreground: Color(0xFFB45309),
    );
  }
  if (hasAny(['scien', 'phys', 'chem', 'bio', 'علوم', 'experiment'])) {
    return const SubjectVisual(
      icon: Icons.science_outlined,
      background: SahlhaColors.successSoft,
      foreground: SahlhaColors.success,
    );
  }
  if (hasAny(['art', 'draw', 'رسم', 'color'])) {
    return const SubjectVisual(
      icon: Icons.palette_outlined,
      background: SahlhaColors.surfaceWarm,
      foreground: SahlhaColors.tealDark,
    );
  }
  if (hasAny(['histor', 'geograph', 'تاريخ', 'جغرا', 'civic'])) {
    return const SubjectVisual(
      icon: Icons.public_rounded,
      background: SahlhaColors.tealFaint,
      foreground: SahlhaColors.muted,
    );
  }
  return const SubjectVisual(
    icon: Icons.auto_stories_rounded,
    background: SahlhaColors.tealSoft,
    foreground: SahlhaColors.tealDark,
  );
}

final _programmingEvidence = RegExp(
  r'python|programming|boolean|control flow|\bcode\b|\bloop\b|\blist\b',
);

/// A small concept glyph for programming skills (loops, lists, booleans…),
/// drawn from the skill's own title + description. Null when the skill is
/// not about programming — callers fall back to the subject visual.
IconData? conceptIconFor({required String title, required String context}) {
  if (!_programmingEvidence.hasMatch('$title $context'.toLowerCase())) {
    return null;
  }
  final t = title.toLowerCase();
  final c = context.toLowerCase();
  if (t.contains('loop') || c.contains('loop')) return Icons.loop;
  if (t.contains('list') || c.contains('list')) return Icons.list_alt;
  if (RegExp(r'bool|true|false').hasMatch('$t $c')) return Icons.toggle_on;
  if (RegExp(r'\bif\b|\belse\b|condition').hasMatch('$t $c')) {
    return Icons.account_tree_outlined;
  }
  if (t.contains('function')) return Icons.functions;
  if (t.contains('variable')) return Icons.code;
  return Icons.code;
}

/// Rounded subject mark used in unit headers, home cards, and lessons.
class SubjectSpot extends StatelessWidget {
  const SubjectSpot({
    super.key,
    required this.subject,
    this.size = 52,
    this.conceptTitle = '',
    this.conceptContext = '',
  });

  final String subject;
  final double size;

  /// When set, a programming concept glyph replaces the subject glyph.
  final String conceptTitle;
  final String conceptContext;

  @override
  Widget build(BuildContext context) {
    final visual = subjectVisualFor(subject);
    final concept = conceptTitle.isEmpty && conceptContext.isEmpty
        ? null
        : conceptIconFor(title: conceptTitle, context: conceptContext);
    return Semantics(
      image: true,
      label: subject.isEmpty ? 'Learning visual' : '$subject visual',
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: visual.background,
            borderRadius: BorderRadius.circular(size * .3),
          ),
          child: Icon(
            concept ?? visual.icon,
            size: size * .52,
            color: visual.foreground,
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------- sahlha companion

// --------------------------------------------------- completion animation

/// One gentle, non-gamey celebration for finished practice: a soft check
/// that scales in once. Respects reduced motion. No confetti, no sounds.
class GentleCelebration extends StatelessWidget {
  const GentleCelebration({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: SahlhaColors.successSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.check_rounded,
        size: size * .5,
        color: SahlhaColors.success,
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return Semantics(image: true, label: 'Well done', child: mark);
    }
    return Semantics(
      image: true,
      label: 'Well done',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutBack,
        builder: (context, value, child) => Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.scale(scale: value, child: child),
        ),
        child: mark,
      ),
    );
  }
}

// -------------------------------------------------------------- effort chip

/// Small calm pill naming effort or state ('Growing steadily', …).
class EffortChip extends StatelessWidget {
  const EffortChip({super.key, required this.label, this.state});

  final String label;

  /// Optional backend mastery state, tints the chip from the calm palette.
  final String? state;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: state == null
          ? SahlhaColors.tealSoft
          : SahlhaColors.masterySoft(state!),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: state == null
            ? SahlhaColors.tealDark
            : SahlhaColors.mastery(state!),
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

// --------------------------------------------------------------- daily goal

/// 'One learning step today' — joyful goal card matching the reference.
/// Gentle progress animation, calm supportive copy, reduced-motion safe.
class DailyGoalCard extends StatelessWidget {
  const DailyGoalCard({super.key, required this.goal});

  final DailyGoal goal;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today\u2019s goal",
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Container(
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
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: goal.doneToday
                          ? SahlhaColors.successSoft
                          : SahlhaColors.warmYellowSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      goal.doneToday
                          ? Icons.check_circle_rounded
                          : Icons.track_changes_rounded,
                      color: goal.doneToday
                          ? SahlhaColors.success
                          : SahlhaColors.warmYellowDeep,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.hasStep ? '1 learning step today' : goal.title,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          goal.doneToday
                              ? '1 of 1 completed'
                              : '0 of 1 completed',
                          style: text.bodySmall?.copyWith(
                            color: SahlhaColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: goal.doneToday ? 1.0 : 0.0),
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  builder: (_, v, _) => LinearProgressIndicator(
                    minHeight: 10,
                    value: v,
                    backgroundColor: SahlhaColors.tealSoft,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      goal.doneToday
                          ? SahlhaColors.success
                          : SahlhaColors.joyTeal,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                goal.message,
                style: text.bodySmall?.copyWith(
                  color: SahlhaColors.muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- why practice?

/// Calm, honest reason per practice mode. Pure copy — unit-tested mentors
/// could reuse it; the sheet below presents it.
({String title, String body}) whyPracticeCopy(String mode) {
  if (mode == 'mastery') {
    return (
      title: 'Why this review?',
      body:
          'This brings the whole unit together in one calm session, so you '
          'can see how the ideas connect. Take it one question at a time.',
    );
  }
  if (mode == 'checkpoint') {
    return (
      title: 'Why this quick check?',
      body:
          'A short pause to remember your recent steps before moving on. '
          'Anything wobbly simply shows what to revisit — that is the point.',
    );
  }
  return (
    title: 'Why this practice?',
    body:
        'A few questions on this skill so the idea sticks. Mistakes are '
        'information: they show exactly what to look at again.',
  );
}

/// Bottom-sheet content explaining the current practice session.
class WhyPracticeSheet extends StatelessWidget {
  const WhyPracticeSheet({super.key, required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final copy = whyPracticeCopy(mode);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SahlhaCompanion(size: 44),
            const SizedBox(width: 12),
            Expanded(child: Text(copy.title, style: text.titleLarge)),
          ],
        ),
        const SizedBox(height: SahlhaSpacing.md),
        Text(copy.body, style: text.bodyLarge?.copyWith(height: 1.6)),
        const SizedBox(height: SahlhaSpacing.md),
        Text(
          'There is no timer and no score to protect — just understanding.',
          style: text.bodyMedium?.copyWith(color: SahlhaColors.muted),
        ),
      ],
    );
  }
}
