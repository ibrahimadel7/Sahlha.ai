import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/student/presentation/widgets/avatar_motion.dart';

/// Drives [advance] in fixed steps, collecting one sample per step.
List<bool> blinkTrace(BlinkScheduler scheduler, double seconds, double step) {
  final trace = <bool>[];
  var t = 0.0;
  while (t < seconds) {
    trace.add(scheduler.advance(step));
    t += step;
  }
  return trace;
}

/// Indices where a blink starts (false → true transitions).
List<int> blinkStarts(List<bool> trace) {
  final starts = <int>[];
  for (var i = 0; i < trace.length; i++) {
    if (trace[i] && (i == 0 || !trace[i - 1])) starts.add(i);
  }
  return starts;
}

void main() {
  group('BlinkScheduler', () {
    test('starts open and blinks periodically, never constantly', () {
      final scheduler = BlinkScheduler(random: Random(7));
      final trace = blinkTrace(scheduler, 12, 0.05);
      expect(trace.first, isFalse);
      final starts = blinkStarts(trace);
      // Gaps of 2.8–5.5s over 12s yield 2–4 blinks.
      expect(starts.length, inInclusiveRange(2, 4));
      // Blinks are brief (~0.12s = 2–3 frames at 0.05s steps).
      for (final s in starts) {
        var length = 0;
        while (s + length < trace.length && trace[s + length]) {
          length++;
        }
        expect(length, inInclusiveRange(1, 4));
      }
    });

    test('gaps vary and stay in a natural range', () {
      final scheduler = BlinkScheduler(random: Random(7));
      final trace = blinkTrace(scheduler, 30, 0.05);
      final starts = blinkStarts(trace);
      expect(starts.length, greaterThan(3));
      final gaps = <double>[];
      for (var i = 1; i < starts.length; i++) {
        gaps.add((starts[i] - starts[i - 1]) * 0.05);
      }
      for (final gap in gaps) {
        expect(gap, greaterThanOrEqualTo(2.5));
        expect(gap, lessThanOrEqualTo(6.0));
      }
      // Not metronomic: at least two distinct gap lengths.
      expect(gaps.toSet().length, greaterThan(1));
    });

    test('same seed reproduces the same sequence', () {
      final a = blinkTrace(BlinkScheduler(random: Random(42)), 10, 0.05);
      final b = blinkTrace(BlinkScheduler(random: Random(42)), 10, 0.05);
      expect(a, b);
    });

    test('handles bad timesteps without throwing', () {
      final scheduler = BlinkScheduler(random: Random(1));
      expect(() => scheduler.advance(0), returnsNormally);
      expect(() => scheduler.advance(-1), returnsNormally);
      expect(() => scheduler.advance(double.nan), returnsNormally);
      expect(() => scheduler.advance(99), returnsNormally);
    });
  });

  group('GestureScheduler', () {
    test('stays neutral while silent', () {
      final scheduler = GestureScheduler(random: Random(7));
      for (var i = 0; i < 100; i++) {
        final pose = scheduler.advance(0.1, speaking: false);
        expect(pose.maxAbs, 0);
      }
      expect(scheduler.gesturesPerformed, 0);
    });

    test('gestures while speaking with neutral gaps between them', () {
      final scheduler = GestureScheduler(random: Random(7));
      var peak = 0.0;
      var neutralFrames = 0;
      for (var i = 0; i < 300; i++) {
        final pose = scheduler.advance(0.1, speaking: true);
        peak = max(peak, pose.maxAbs);
        if (pose.maxAbs < 0.5) neutralFrames++;
      }
      expect(scheduler.gesturesPerformed, greaterThanOrEqualTo(3));
      // Gestures are small (<= 7 units) but clearly visible (> 2 units).
      expect(peak, greaterThan(2));
      expect(peak, lessThanOrEqualTo(7.5));
      // Mixture of gesture and neutral: not constantly moving.
      expect(neutralFrames, greaterThan(50));
    });

    test('cycles varied gesture patterns, not one repetition', () {
      final scheduler = GestureScheduler(random: Random(7));
      for (var i = 0; i < 600; i++) {
        scheduler.advance(0.1, speaking: true);
      }
      expect(scheduler.gesturesPerformed, greaterThanOrEqualTo(5));
      expect(scheduler.kindsUsed.length, greaterThanOrEqualTo(2));
    });

    test('pausing settles smoothly to neutral, never stuck mid-gesture', () {
      final scheduler = GestureScheduler(random: Random(7));
      // Speak until a gesture is visibly underway.
      HandOffsets pose = HandOffsets.zero;
      for (var i = 0; i < 300 && pose.maxAbs < 2; i++) {
        pose = scheduler.advance(0.05, speaking: true);
      }
      expect(pose.maxAbs, greaterThan(2));
      // Pause: decay back to neutral without snapping.
      var previous = pose.maxAbs;
      for (var i = 0; i < 20; i++) {
        pose = scheduler.advance(0.1, speaking: false);
        // Monotonic-ish decay: never jumps back up mid-settle.
        expect(pose.maxAbs, lessThanOrEqualTo(previous + 0.05));
        previous = pose.maxAbs;
      }
      expect(pose.maxAbs, lessThan(0.3));
      // And no new gesture starts while silent.
      final count = scheduler.gesturesPerformed;
      for (var i = 0; i < 50; i++) {
        scheduler.advance(0.1, speaking: false);
      }
      expect(scheduler.gesturesPerformed, count);
    });

    test('resume starts neutral, without an immediate big gesture', () {
      final scheduler = GestureScheduler(random: Random(7));
      for (var i = 0; i < 200; i++) {
        scheduler.advance(0.1, speaking: true);
      }
      for (var i = 0; i < 20; i++) {
        scheduler.advance(0.1, speaking: false);
      }
      // First half-second after resume stays calm.
      for (var i = 0; i < 5; i++) {
        final pose = scheduler.advance(0.1, speaking: true);
        expect(pose.maxAbs, lessThan(1.0));
      }
    });

    test('same seed reproduces the same sequence', () {
      List<HandOffsets> run() {
        final scheduler = GestureScheduler(random: Random(42));
        return [
          for (var i = 0; i < 100; i++)
            scheduler.advance(0.1, speaking: true),
        ];
      }

      expect(run(), run());
    });
  });
}
