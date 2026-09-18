import 'dart:math';

/// Pure, framework-free motion logic for the Sahlha avatar.
///
/// Extracted so the timing rules (blink gaps, gesture variety, smooth
/// settling) are unit-testable without pumping widgets. The widget layer
/// ([SahlhaCompanion]) advances these from its existing ticker frames — no
/// extra timers, controllers, or listeners are created.
///
/// Determinism: both schedulers take an injectable [Random]. Production
/// passes an unseeded one (natural variety); tests pass a seeded one, so
/// sequences are exactly reproducible.

// ---------------------------------------------------------------- blink ---

/// Natural blinking with slightly randomized 2.8–5.5s gaps, independent of
/// audio playback. Each blink lasts ~0.12s.
class BlinkScheduler {
  BlinkScheduler({Random? random, double initialDelay = 2.0})
    : _random = random ?? Random(),
      _nextAt = initialDelay;

  final Random _random;
  double _t = 0;
  double _nextAt;
  double _blinkLeft = 0;

  /// Visible lid state right now (call [advance] first each frame).
  bool get blinking => _blinkLeft > 0;

  /// Advances the clock by [dtSeconds] (clamped to >= 0). Returns whether
  /// the eyes are closed on this frame.
  bool advance(double dtSeconds) {
    var dt = dtSeconds;
    if (dt.isNaN || dt < 0) dt = 0;
    if (dt > 0.25) dt = 0.25;
    _t += dt;
    if (_blinkLeft > 0) {
      _blinkLeft -= dt;
      if (_blinkLeft <= 0) {
        _blinkLeft = 0;
        _nextAt = _t + 2.8 + _random.nextDouble() * 2.7;
      }
      return true;
    }
    if (_t >= _nextAt) {
      _blinkLeft = _blinkDuration;
      return true;
    }
    return false;
  }

  static const double _blinkDuration = 0.12;
}

// --------------------------------------------------------------- gestures ---

/// The three subtle teaching gestures, cycled with pseudo-random variety.
enum GestureKind { alternate, bothUp, emphasis }

/// Pixel offset (in the painter's 100-unit space) for the single animated
/// hand. Zero means resting against the body. The left channel is kept at
/// zero for compatibility (the extra static hand was removed).
class HandOffsets {
  const HandOffsets(this.leftDx, this.leftDy, this.rightDx, this.rightDy);
  final double leftDx;
  final double leftDy;
  final double rightDx;
  final double rightDy;

  static const HandOffsets zero = HandOffsets(0, 0, 0, 0);

  double get maxAbs => [
    leftDx.abs(),
    leftDy.abs(),
    rightDx.abs(),
    rightDy.abs(),
  ].reduce(max);

  @override
  bool operator ==(Object other) =>
      other is HandOffsets &&
      other.leftDx == leftDx &&
      other.leftDy == leftDy &&
      other.rightDx == rightDx &&
      other.rightDy == rightDy;

  @override
  int get hashCode => Object.hash(leftDx, leftDy, rightDx, rightDy);

  @override
  String toString() => 'Hands($leftDx,$leftDy / $rightDx,$rightDy)';
}

/// Schedules occasional small hand gestures while speaking, with neutral
/// gaps between them (idle → gesture → neutral → gesture → neutral).
///
/// Pause/completion behavior: when [speaking] is false, no new gesture ever
/// starts and the current pose eases back to neutral — the avatar settles
/// smoothly instead of snapping, and is never left mid-gesture. Resume
/// always begins with a neutral gap, so no huge gesture fires immediately.
class GestureScheduler {
  GestureScheduler({Random? random}) : _random = random ?? Random();

  final Random _random;

  double _gapLeft = _initialGap;
  double _gestureLeft = 0;
  GestureKind _kind = GestureKind.alternate;
  bool _alternateSide = false;
  bool _wasSpeaking = false;

  HandOffsets _current = HandOffsets.zero;
  HandOffsets _target = HandOffsets.zero;

  /// Number of gestures started so far (useful for tests).
  int gesturesPerformed = 0;

  /// Distinct gesture kinds used so far (useful for tests).
  final Set<GestureKind> kindsUsed = {};

  /// Current (smoothed) pose. Call [advance] first each frame.
  HandOffsets get current => _current;

  bool get inGesture => _gestureLeft > 0;

  /// Advances the clock by [dtSeconds]. Returns the smoothed pose.
  HandOffsets advance(double dtSeconds, {required bool speaking}) {
    var dt = dtSeconds;
    if (dt.isNaN || dt < 0) dt = 0;
    if (dt > 0.25) dt = 0.25;

    if (!speaking) {
      // Settle: no new gestures, ease back to neutral. Reset the schedule
      // so resuming starts from a calm neutral gap.
      _wasSpeaking = false;
      _gestureLeft = 0;
      _gapLeft = _initialGap;
      _target = HandOffsets.zero;
    } else {
      if (!_wasSpeaking) {
        // Fresh resume: begin neutral, never with an instant gesture.
        _wasSpeaking = true;
        _gestureLeft = 0;
        _gapLeft = _initialGap;
        _target = HandOffsets.zero;
      } else if (_gestureLeft > 0) {
        _gestureLeft -= dt;
        if (_gestureLeft <= 0) {
          _gestureLeft = 0;
          _target = HandOffsets.zero;
          _gapLeft = 1.8 + _random.nextDouble() * 2.4;
          _kind = GestureKind.values[_random.nextInt(3)];
        }
      } else {
        _gapLeft -= dt;
        if (_gapLeft <= 0) {
          _gestureLeft = 0.9 + _random.nextDouble() * 0.5;
          gesturesPerformed++;
          kindsUsed.add(_kind);
          if (_kind == GestureKind.alternate) {
            _alternateSide = !_alternateSide;
          }
          _target = _poseFor(_kind, _alternateSide);
        }
      }
    }

    // Critically-damped-ish smoothing: fast attack, gentle release, no snap.
    final rate = _target.maxAbs > _current.maxAbs ? 8.0 : 5.5;
    final k = 1 - exp(-dt * rate);
    _current = HandOffsets(
      _lerp(_current.leftDx, _target.leftDx, k),
      _lerp(_current.leftDy, _target.leftDy, k),
      _lerp(_current.rightDx, _target.rightDx, k),
      _lerp(_current.rightDy, _target.rightDy, k),
    );
    return _current;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Small teaching poses in the painter's 100-unit space (max ~7 units).
  /// Single animated (right) hand only — the extra static hand was removed,
  /// so the left channel always stays at rest.
  static HandOffsets _poseFor(GestureKind kind, bool alternateSide) {
    switch (kind) {
      case GestureKind.alternate:
        // One animated hand slightly up or slightly down; the height swaps
        // each time this gesture recurs.
        return alternateSide
            ? const HandOffsets(0, 0, 2, 3)
            : const HandOffsets(0, 0, 2, -6);
      case GestureKind.bothUp:
        // Explanation gesture: animated hand outward/upward.
        return const HandOffsets(0, 0, 3, -5);
      case GestureKind.emphasis:
        // Small one-hand upward emphasis.
        return const HandOffsets(0, 0, 2, -7);
    }
  }

  static const double _initialGap = 1.2;
}
