import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'avatar_motion.dart';

/// Reusable Sahlha avatar moods. `idle/speaking/celebrating` are the core
/// states; `happy/thinking/encouraging` are gentle expressive variants for
/// the joyful Student world. `listening/retry` are kept for compatibility.
enum CompanionMood {
  idle,
  listening,
  speaking,
  celebrating,
  retry,
  happy,
  thinking,
  encouraging,
}

/// Friendly teal robot. Blinks, breathes, sways its antenna and gestures
/// with its hands while speaking; only speech moves the mouth. Meaningful
/// reactions only — no constant bouncing. Reduced motion stops the ticker
/// completely.
enum SahlhaAvatarState {
  idle,
  speaking,
  happy,
  thinking,
  encouraging,
  celebrating,
}

/// Maps the joyful avatar API onto the underlying companion moods.
CompanionMood companionMoodFromAvatar(SahlhaAvatarState state) =>
    switch (state) {
      SahlhaAvatarState.idle => CompanionMood.idle,
      SahlhaAvatarState.speaking => CompanionMood.speaking,
      SahlhaAvatarState.happy => CompanionMood.happy,
      SahlhaAvatarState.thinking => CompanionMood.thinking,
      SahlhaAvatarState.encouraging => CompanionMood.encouraging,
      SahlhaAvatarState.celebrating => CompanionMood.celebrating,
    };

class SahlhaCompanion extends StatefulWidget {
  const SahlhaCompanion({
    super.key,
    this.size = 64,
    this.label,
    this.mood = CompanionMood.idle,
    this.mouthOpen,
  });
  final double size;
  final String? label;
  final CompanionMood mood;

  /// True lip-sync signal in [0, 1] (0 closed, 1 fully open), driven by the
  /// actual playback position via [AudioCompanion]. Null keeps the local
  /// speech-like cadence (previews, MP3 without envelope, tests).
  final double? mouthOpen;
  @override
  State<SahlhaCompanion> createState() => _SahlhaCompanionState();
}

class _SahlhaCompanionState extends State<SahlhaCompanion>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  /// Pure-Dart motion schedulers (no timers/controllers/listeners of their
  /// own): advanced once per ticker frame below, so gestures and blinks ride
  /// the existing animation without extra rebuilds. Nothing to dispose.
  final _blink = BlinkScheduler();
  final _gestures = GestureScheduler();
  DateTime? _lastFrame;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      _motion.stop();
      _motion.value = 0;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = AnimatedBuilder(
      animation: _motion,
      builder: (_, _) {
        // Wall-clock delta between frames drives the schedulers; clamped so
        // jank or backgrounding can never teleport a gesture.
        final now = DateTime.now();
        var dt = 0.016;
        final last = _lastFrame;
        if (last != null) {
          dt = now.difference(last).inMicroseconds / 1e6;
        }
        _lastFrame = now;
        if (dt < 0) dt = 0;
        if (dt > 0.1) dt = 0.1;
        // The speaking mood comes from the existing audio-state mapping in
        // AudioCompanion (playing → speaking, paused/stopped → idle): no
        // second audio-state system is introduced here.
        final speaking = widget.mood == CompanionMood.speaking;
        final blink = _blink.advance(dt);
        final hands = _gestures.advance(dt, speaking: speaking);
        return SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _CompanionPainter(
              _motion.value,
              widget.mood,
              mouthOpen: widget.mouthOpen,
              blink: blink,
              hands: hands,
            ),
          ),
        );
      },
    );
    return widget.label == null
        ? ExcludeSemantics(child: face)
        : Semantics(image: true, label: widget.label, child: face);
  }
}

class _CompanionPainter extends CustomPainter {
  const _CompanionPainter(
    this.phase,
    this.mood, {
    this.mouthOpen,
    this.blink = false,
    this.hands = HandOffsets.zero,
  });
  final double phase;
  final CompanionMood mood;

  /// True lip-sync signal in [0, 1]; null falls back to cadence animation.
  final double? mouthOpen;

  /// Natural blink from [BlinkScheduler] (randomized gaps, ~0.12s lids).
  final bool blink;

  /// Circular-hand offsets from [GestureScheduler] in the painter's
  /// 100-unit space; zero rests the hands against the body.
  final HandOffsets hands;
  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.scale(size.width / 100, size.height / 100);
    final wave = math.sin(phase * math.pi * 2);
    // Gentle squash & stretch: subtle breathing, stronger when celebrating.
    final celebrating =
        mood == CompanionMood.celebrating || mood == CompanionMood.happy;
    final squash = celebrating
        ? 1 + 0.025 * math.sin(phase * math.pi * 4)
        : 1 + 0.012 * wave;
    c.translate(50, 58);
    c.scale(2 - squash > 1 ? 1 : 1, squash);
    // Tiny tilt; thinking tilts a touch more.
    c.rotate(wave * (mood == CompanionMood.thinking ? 0.03 : 0.012));
    c.translate(-50, -58);
    // Antenna with soft sway + tip light.
    final antenna = Path()
      ..moveTo(60, 24)
      ..quadraticBezierTo(66 + wave * 1.5, 3, 81, 15 + wave * 1.5);
    c.drawPath(
      antenna,
      Paint()
        ..color = const Color(0xFF078B86)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    c.drawCircle(
      Offset(81, 15 + wave * 1.5),
      4.2,
      Paint()..color = const Color(0xFFFFC94A),
    );
    c.drawCircle(
      Offset(81, 15 + wave * 1.5),
      2.0,
      Paint()..color = const Color(0xFFFFF3D1),
    );
    // Circular hands, resting against the body sides. While speaking the
    // scheduler eases them through small teaching gestures; at rest the
    // offsets decay to zero so the hands settle back onto the body.
    // Drawn before the body so the inner edge tucks behind it.
    final handPaint = Paint()..color = const Color(0xFF0A7C76);
    c.drawCircle(Offset(9 + hands.leftDx, 66 + hands.leftDy), 8.5, handPaint);
    c.drawCircle(Offset(91 + hands.rightDx, 68 + hands.rightDy), 8.5, handPaint);
    c.drawOval(
      const Rect.fromLTWH(9, 23, 81, 70),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF6CCFC4), Color(0xFF008F8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(const Rect.fromLTWH(9, 23, 81, 70)),
    );
    c.drawOval(
      const Rect.fromLTWH(16, 30, 65, 56),
      Paint()..color = const Color(0xFF94DFD3),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(24, 40, 51, 35),
        const Radius.circular(18),
      ),
      Paint()..color = const Color(0xFF193B4A),
    );
    // Eye expressions per mood: happy/celebrating = joyful arcs,
    // thinking = slightly narrowed, encouraging = bright.
    // `blink` comes from the randomized scheduler, independent of playback.
    final eyeH = blink
        ? 2.0
        : switch (mood) {
            CompanionMood.celebrating => 6.0,
            CompanionMood.happy => 7.0,
            CompanionMood.encouraging => 11.0,
            CompanionMood.thinking => 8.0,
            _ => 10.0,
          };
    for (final x in [38.0, 61.0]) {
      if ((mood == CompanionMood.happy || mood == CompanionMood.celebrating) &&
          !blink) {
        // Joyful closed-eye arcs.
        c.drawArc(
          Rect.fromCenter(center: Offset(x, 54), width: 11, height: 8),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round,
        );
      } else {
        c.drawOval(
          Rect.fromCenter(center: Offset(x, 53), width: 9, height: eyeH),
          Paint()..color = Colors.white,
        );
        if (!blink) {
          c.drawCircle(
            Offset(x + 1, 51),
            1.7,
            Paint()..color = const Color(0xFFB6F1ED),
          );
        }
      }
    }
    // Mouth: only speaking animates (believable cycle from player state,
    // no extra network). Others are gentle static shapes.
    final double opening;
    final double mouthW;
    switch (mood) {
      case CompanionMood.speaking:
        final signal = mouthOpen?.clamp(0.0, 1.0);
        if (signal != null) {
          // TRUE SYNC: driven by the actual playback position (speech-energy
          // for WAV, word-timed for MP3). Silence closes the mouth.
          opening = 1.6 + 6.2 * signal;
          mouthW = 11 - 2.0 * signal;
          break;
        }
        // Fallback cadence when no envelope is available: ~14 openings per
        // 6s ticker loop (≈2.3/s, real syllable rate) with a slower phrase
        // envelope so the mouth pauses between phrases like real words.
        // All frequencies are whole cycles per loop so the loop is seamless.
        final loop = phase * math.pi * 2; // 0..2π per 6s
        final wobble = math.sin(loop * 5 + 0.7) * 0.35;
        final syll = math.sin(loop * 14 + wobble) * 0.5 + 0.5; // 0..1
        final phrase = math.sin(loop * 2 + 1.1) * 0.5 + 0.5; // 0..1
        final gate = ((phrase - 0.22) / (0.75 - 0.22)).clamp(0.0, 1.0);
        final smooth = gate * gate * (3 - 2 * gate);
        final open01 = syll * (0.25 + 0.75 * smooth);
        opening = 1.6 + 6.2 * open01;
        mouthW = 11 - 2.0 * open01;
        break;
      case CompanionMood.happy:
      case CompanionMood.celebrating:
      case CompanionMood.encouraging:
        opening = 5.5;
        mouthW = 13;
        break;
      case CompanionMood.thinking:
        opening = 2.2;
        mouthW = 7;
        break;
      case CompanionMood.retry:
        opening = 2.0;
        mouthW = 7;
        break;
      case CompanionMood.listening:
      case CompanionMood.idle:
        opening = 2.4;
        mouthW = 10;
        break;
    }
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(49, 66),
        width: mouthW,
        height: opening,
      ),
      Paint()..color = const Color(0xFFD7F9F2),
    );
    // Rosy cheeks for warmth.
    c.drawOval(
      const Rect.fromLTWH(13, 69, 17, 16),
      Paint()..color = const Color(0xFF149C96).withValues(alpha: 0.9),
    );
    c.drawOval(
      const Rect.fromLTWH(68, 71, 17, 15),
      Paint()..color = const Color(0xFF149C96).withValues(alpha: 0.9),
    );
    if (mood == CompanionMood.celebrating ||
        mood == CompanionMood.encouraging) {
      for (final p in [const Offset(9, 15), const Offset(90, 35)]) {
        c.drawPath(
          Path()
            ..moveTo(p.dx, p.dy - 5)
            ..lineTo(p.dx + 2, p.dy - 1)
            ..lineTo(p.dx + 5, p.dy)
            ..lineTo(p.dx + 2, p.dy + 2)
            ..lineTo(p.dx, p.dy + 6)
            ..lineTo(p.dx - 2, p.dy + 2)
            ..lineTo(p.dx - 5, p.dy)
            ..lineTo(p.dx - 2, p.dy - 1)
            ..close(),
          Paint()..color = const Color(0xFFFFBF33),
        );
      }
    }
    if (mood == CompanionMood.thinking) {
      // Thoughtful brow dots.
      c.drawCircle(const Offset(38, 45), 1.6, Paint()..color = Colors.white);
      c.drawCircle(const Offset(61, 45), 1.6, Paint()..color = Colors.white);
    }
    if (mood == CompanionMood.listening) {
      c.drawArc(
        const Rect.fromLTWH(18, 34, 63, 48),
        math.pi,
        math.pi,
        false,
        Paint()
          ..color = const Color(0xFF087D78)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_CompanionPainter old) =>
      old.phase != phase ||
      old.mood != mood ||
      old.mouthOpen != mouthOpen ||
      old.blink != blink ||
      old.hands != hands;
}
