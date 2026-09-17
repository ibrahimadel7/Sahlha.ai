import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/sahlha_colors.dart';

/// Subtle joyful background: soft blobs, bubbles, tiny stars and leaf-like
/// shapes at very low opacity. Never interferes with reading.
/// Respects reduced motion (static when animations are disabled).
class PlayfulBackground extends StatelessWidget {
  const PlayfulBackground({
    super.key,
    required this.child,
    this.variant = PlayfulVariant.home,
  });

  final Widget child;
  final PlayfulVariant variant;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            child: CustomPaint(painter: _PlayfulPainter(variant: variant)),
          ),
        ),
        if (!reduced)
          Positioned.fill(
            child: ExcludeSemantics(child: _FloatingDots(variant: variant)),
          ),
        child,
      ],
    );
  }
}

enum PlayfulVariant {
  home,
  path,
  lesson,
  practice,
  completion,
  progress,
  profile,
}

class _PlayfulPainter extends CustomPainter {
  const _PlayfulPainter({required this.variant});
  final PlayfulVariant variant;

  @override
  void paint(Canvas canvas, Size size) {
    // Very light warm wash.
    final wash = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFBF2), Color(0xFFFBFAF7)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), wash);

    void blob(Offset c, double r, Color color) {
      canvas.drawCircle(c, r, Paint()..color = color.withValues(alpha: 0.10));
      canvas.drawCircle(
        c.translate(r * 0.25, r * 0.2),
        r * 0.55,
        Paint()..color = color.withValues(alpha: 0.07),
      );
    }

    void leaf(Offset c, double s, Color color, double angle) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(angle);
      final path = Path()
        ..moveTo(0, -s)
        ..quadraticBezierTo(s * 0.9, -s * 0.2, 0, s)
        ..quadraticBezierTo(-s * 0.9, -s * 0.2, 0, -s);
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.10));
      canvas.restore();
    }

    void star(Offset c, double s, Color color) {
      final path = Path();
      for (var i = 0; i < 5; i++) {
        final a = -math.pi / 2 + i * 2 * math.pi / 5;
        final p = Offset(c.dx + math.cos(a) * s, c.dy + math.sin(a) * s);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
        final a2 = a + math.pi / 5;
        path.lineTo(
          c.dx + math.cos(a2) * s * 0.45,
          c.dy + math.sin(a2) * s * 0.45,
        );
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.14));
    }

    final w = size.width;
    // Shared gentle decor, tuned per variant.
    blob(Offset(w * 0.88, 90), 90, SahlhaColors.aqua);
    blob(Offset(w * 0.08, 220), 60, SahlhaColors.warmYellow);
    blob(Offset(w * 0.92, 420), 70, SahlhaColors.sky);
    leaf(Offset(w * 0.06, 120), 22, SahlhaColors.joyTeal, 0.5);
    leaf(Offset(w * 0.94, 300), 18, SahlhaColors.joyTeal, -0.6);
    star(Offset(w * 0.16, 70), 9, SahlhaColors.warmYellow);
    star(Offset(w * 0.80, 190), 7, SahlhaColors.lavender);

    switch (variant) {
      case PlayfulVariant.completion:
        blob(Offset(w * 0.5, 60), 120, SahlhaColors.warmYellow);
        star(Offset(w * 0.22, 150), 10, SahlhaColors.softCoral);
        star(Offset(w * 0.78, 130), 10, SahlhaColors.sky);
        break;
      case PlayfulVariant.path:
        blob(Offset(w * 0.12, 520), 80, SahlhaColors.lavender);
        leaf(Offset(w * 0.88, 620), 20, SahlhaColors.joyTeal, 0.4);
        break;
      case PlayfulVariant.lesson:
        blob(Offset(w * 0.15, 320), 70, SahlhaColors.sky);
        break;
      case PlayfulVariant.practice:
        blob(Offset(w * 0.85, 180), 60, SahlhaColors.aqua);
        break;
      case PlayfulVariant.progress:
        blob(Offset(w * 0.5, 120), 100, SahlhaColors.aquaSoft);
        break;
      case PlayfulVariant.profile:
        blob(Offset(w * 0.85, 60), 110, SahlhaColors.aquaSoft);
        leaf(Offset(w * 0.90, 120), 26, SahlhaColors.joyTeal, -0.4);
        break;
      case PlayfulVariant.home:
        break;
    }
  }

  @override
  bool shouldRepaint(_PlayfulPainter old) => old.variant != variant;
}

class _FloatingDots extends StatefulWidget {
  const _FloatingDots({required this.variant});
  final PlayfulVariant variant;
  @override
  State<_FloatingDots> createState() => _FloatingDotsState();
}

class _FloatingDotsState extends State<_FloatingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(painter: _DotsPainter(_c.value)),
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final spots = [
      (0.12, 0.18, SahlhaColors.warmYellow),
      (0.88, 0.32, SahlhaColors.aqua),
      (0.78, 0.62, SahlhaColors.lavender),
    ];
    for (var i = 0; i < spots.length; i++) {
      final (fx, fy, color) = spots[i];
      final dy = math.sin((t + i * 0.33) * math.pi * 2) * 6;
      canvas.drawCircle(
        Offset(w * fx, size.height * fy + dy),
        5,
        Paint()..color = color.withValues(alpha: 0.18),
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.t != t;
}

/// Joyful skeleton: rounded placeholders, no harsh spinners.
class JoyfulSkeleton extends StatelessWidget {
  const JoyfulSkeleton({super.key, this.lines = 3});
  final int lines;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading your learning',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: SahlhaColors.aquaSoft,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: SahlhaColors.borderSubtle),
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < lines; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                height: 18,
                decoration: BoxDecoration(
                  color: SahlhaColors.borderSubtle.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
