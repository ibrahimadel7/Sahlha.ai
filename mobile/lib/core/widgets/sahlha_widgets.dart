import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/sahlha_colors.dart';
import '../theme/sahlha_spacing.dart';

/// Reusable Sahlha components. One obvious primary action per screen,
/// consistent placement, calm language, large touch targets.

// ---------------------------------------------------------------- buttons
class SahlhaPrimaryButton extends StatelessWidget {
  const SahlhaPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Text(label),
    );
  }
}

class SahlhaSecondaryButton extends StatelessWidget {
  const SahlhaSecondaryButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(onPressed: onPressed, child: Text(label));
  }
}

// ------------------------------------------------------------------- card
class SahlhaCard extends StatelessWidget {
  const SahlhaCard({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(SahlhaSpacing.lg),
        child: child,
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SahlhaRadius.lg),
      child: card,
    );
  }
}

// ----------------------------------------------------------------- appbar
class SahlhaAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SahlhaAppBar({
    super.key,
    required this.title,
    this.actions,
    this.onBack,
  });

  final String title;
  final List<Widget>? actions;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: onBack == null ? null : BackButton(onPressed: onBack),
      title: Text(title, style: Theme.of(context).textTheme.titleLarge),
      actions: actions,
    );
  }
}

// ---------------------------------------------------------------- progress
class SahlhaProgressBar extends StatelessWidget {
  const SahlhaProgressBar({super.key, required this.value, this.height = 10});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SahlhaRadius.pill),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: SahlhaColors.tealSoft,
        valueColor: const AlwaysStoppedAnimation<Color>(SahlhaColors.teal),
      ),
    );
  }
}

class MasteryRing extends StatelessWidget {
  const MasteryRing({
    super.key,
    required this.mastered,
    required this.total,
    this.size = 96,
  });

  final int mastered;
  final int total;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = total == 0 ? 0.0 : mastered / total;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: total == 0 ? 0 : value,
              strokeWidth: 10,
              backgroundColor: SahlhaColors.tealSoft,
              valueColor: const AlwaysStoppedAnimation<Color>(
                SahlhaColors.teal,
              ),
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(value * 100).round()}%',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text('mastered', style: text.bodySmall?.copyWith(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ badges
String masteryLabel(String state) {
  return switch (state) {
    'mastered' => 'Mastered',
    'developing' => 'Developing',
    'needs_practice' => 'Needs practice',
    _ => 'Not started',
  };
}

class SkillStatusBadge extends StatelessWidget {
  const SkillStatusBadge({super.key, required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final bg = SahlhaColors.masterySoft(state);
    final fg = SahlhaColors.mastery(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SahlhaRadius.pill),
      ),
      child: Text(
        masteryLabel(state),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w800),
      ),
    );
  }
}

// --------------------------------------------------------------- questions
class QuestionOptionCard extends StatelessWidget {
  const QuestionOptionCard({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.correct,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool? correct; // null = not yet revealed

  @override
  Widget build(BuildContext context) {
    Color border = SahlhaColors.line;
    Color bg = SahlhaColors.surface;
    if (correct == true) {
      border = SahlhaColors.success;
      bg = SahlhaColors.successSoft;
    } else if (correct == false && selected) {
      border = SahlhaColors.danger;
      bg = SahlhaColors.dangerSoft;
    } else if (selected) {
      border = SahlhaColors.teal;
      bg = SahlhaColors.tealFaint;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SahlhaRadius.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: SahlhaSpacing.lg,
          vertical: SahlhaSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(SahlhaRadius.md),
          border: Border.all(color: border, width: selected ? 2 : 1.2),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class InlineFeedback extends StatelessWidget {
  const InlineFeedback({
    super.key,
    required this.correct,
    required this.message,
  });

  final bool correct;
  final String message;

  @override
  Widget build(BuildContext context) {
    final bg = correct ? SahlhaColors.successSoft : SahlhaColors.sunSoft;
    final fg = correct ? SahlhaColors.success : const Color(0xFFB45309);
    final icon = correct ? Icons.check_circle : Icons.info;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SahlhaSpacing.lg),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SahlhaRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: SahlhaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  correct ? 'Correct.' : 'Not yet.',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: fg, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: SahlhaColors.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ states
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message = 'Loading…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SahlhaSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: SahlhaColors.teal),
            const SizedBox(height: SahlhaSpacing.lg),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SahlhaSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: SahlhaColors.tealSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_stories_outlined,
                color: SahlhaColors.teal,
                size: 34,
              ),
            ),
            const SizedBox(height: SahlhaSpacing.lg),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: SahlhaSpacing.sm),
            Text(
              message,
              style: text.bodyMedium?.copyWith(color: SahlhaColors.muted),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: SahlhaSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SahlhaSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: SahlhaColors.muted,
              size: 40,
            ),
            const SizedBox(height: SahlhaSpacing.lg),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: SahlhaSpacing.lg),
              SahlhaSecondaryButton(label: 'Try again', onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- bottom sheet
Future<T?> showSahlhaSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: SahlhaSpacing.page,
          right: SahlhaSpacing.page,
          top: SahlhaSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: SahlhaColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: SahlhaSpacing.lg),
            Flexible(child: SingleChildScrollView(child: child)),
            const SizedBox(height: SahlhaSpacing.lg),
          ],
        ),
      ),
    ),
  );
}

// -------------------------------------------------------------------- logo
class SahlhaLogo extends StatelessWidget {
  const SahlhaLogo({super.key, this.size = 44, this.showWordmark = true});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/logo/sahlha_mark.svg',
          width: size,
          height: size,
        ),
        if (showWordmark) ...[
          const SizedBox(width: SahlhaSpacing.sm),
          Text(
            'Sahlha',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ],
    );
  }
}

/// Full Sahlha lockup from the brand PNG (robot + "Sahlha" wordmark).
///
/// Expects `assets/logo/sahlha_logo.png` (transparent PNG, ~1024px wide).
/// Falls back to the vector [SahlhaLogo] if the PNG is missing so the app
/// never crashes before the asset is added.
class SahlhaFullLogo extends StatelessWidget {
  const SahlhaFullLogo({super.key, this.width = 220, this.fit = BoxFit.contain});

  final double width;
  final BoxFit fit;

  static const _pngPath = 'assets/logo/sahlha_logo.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _pngPath,
      width: width,
      fit: fit,
      errorBuilder: (_, _, _) => SahlhaLogo(
        size: width * 0.32,
        showWordmark: true,
      ),
    );
  }
}

/// Robot-only mark from the brand PNG (no wordmark).
///
/// Expects `assets/logo/sahlha_icon.png`. Useful for avatars, splash marks,
/// and anywhere the full lockup would be too small to read.
class SahlhaRobotMark extends StatelessWidget {
  const SahlhaRobotMark({super.key, this.size = 84, this.borderRadius = 24});

  final double size;
  final double borderRadius;

  static const _pngPath = 'assets/logo/sahlha_icon.png';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.asset(
        _pngPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => SvgPicture.asset(
          'assets/logo/sahlha_mark.svg',
          width: size,
          height: size,
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- path nodes
enum PathNodeState { completed, current, upcoming, locked }

class LearningPathNode extends StatelessWidget {
  const LearningPathNode({
    super.key,
    required this.state,
    required this.title,
    this.subtitle,
    this.onTap,
    this.isLast = false,
  });

  final PathNodeState state;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final Color ring;
    final Color fill;
    final Widget mark;
    switch (state) {
      case PathNodeState.completed:
        ring = SahlhaColors.teal;
        fill = SahlhaColors.teal;
        mark = const Icon(Icons.check, color: Colors.white, size: 22);
      case PathNodeState.current:
        ring = SahlhaColors.teal;
        fill = Colors.white;
        mark = Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: SahlhaColors.sun,
            shape: BoxShape.circle,
          ),
        );
      case PathNodeState.upcoming:
        ring = SahlhaColors.line;
        fill = Colors.white;
        mark = const Icon(
          Icons.circle_outlined,
          color: SahlhaColors.muted,
          size: 18,
        );
      case PathNodeState.locked:
        ring = SahlhaColors.line;
        fill = const Color(0xFFF1F5F9);
        mark = const Icon(
          Icons.lock_outline,
          color: SahlhaColors.muted,
          size: 18,
        );
    }
    final dimmed =
        state == PathNodeState.upcoming || state == PathNodeState.locked;
    return InkWell(
      onTap: state == PathNodeState.locked ? null : onTap,
      borderRadius: BorderRadius.circular(SahlhaRadius.md),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                    border: Border.all(color: ring, width: 2.5),
                  ),
                  child: Center(child: mark),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 3,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: state == PathNodeState.completed
                            ? SahlhaColors.teal.withValues(alpha: 0.5)
                            : SahlhaColors.line,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: SahlhaSpacing.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: SahlhaSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: text.titleMedium?.copyWith(
                        color: dimmed ? SahlhaColors.muted : SahlhaColors.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: text.bodySmall?.copyWith(
                          color: SahlhaColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
