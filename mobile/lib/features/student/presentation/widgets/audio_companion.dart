import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/audio_service.dart';
import 'sahlha_companion.dart';

CompanionMood companionMoodFor(ReadAloudState state) => switch (state) {
  ReadAloudState.playing => CompanionMood.speaking,
  ReadAloudState.loading || ReadAloudState.ready => CompanionMood.listening,
  ReadAloudState.idle ||
  ReadAloudState.paused ||
  ReadAloudState.stopped ||
  ReadAloudState.error => CompanionMood.idle,
};

/// Observes the single authenticated player; never starts or downloads audio.
///
/// While this URL plays, a ticker polls the playback position and maps it
/// through the cached lip-sync envelope ([AudioService.lipSyncLevel]), so the
/// mouth follows the actual words: true speech energy for WAV, word-timed
/// levels for MP3. Attack is fast, release is gentle — the mouth snaps open
/// on speech and relaxes into pauses. Seeks, pauses and speed changes stay
/// correct because every frame re-derives openness from position.
///
/// Missing envelope (offline/unavailable) or reduced motion keeps
/// [SahlhaCompanion.mouthOpen] null, which falls back to the local cadence
/// animation — the lesson never breaks.
class AudioCompanion extends ConsumerStatefulWidget {
  const AudioCompanion({super.key, required this.url, this.size = 64});
  final String url;
  final double size;
  @override
  ConsumerState<AudioCompanion> createState() => _AudioCompanionState();
}

class _AudioCompanionState extends ConsumerState<AudioCompanion>
    with SingleTickerProviderStateMixin {
  StreamSubscription<ReadAloudState>? _sub;
  late final Ticker _ticker;
  ReadAloudState _state = ReadAloudState.idle;

  /// Smoothed openness in [0, 1]; null = no signal (cadence fallback).
  double? _mouth;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    try {
      final audio = ref.read(audioServiceProvider);
      _state = _effective(audio.state);
      _sub = audio.stateStream.listen(_onState);
    } catch (_) {
      _state = ReadAloudState.idle;
    }
  }

  @override
  void didUpdateWidget(AudioCompanion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _mouth = null;
      try {
        _state = _effective(ref.read(audioServiceProvider).state);
      } catch (_) {
        _state = ReadAloudState.idle;
      }
      _syncTicker();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  /// The stream state, scoped to this URL: another lesson playing reads idle.
  ReadAloudState _effective(ReadAloudState state) {
    try {
      return ref.read(audioServiceProvider).activeUrl == widget.url
          ? state
          : ReadAloudState.idle;
    } catch (_) {
      return ReadAloudState.idle;
    }
  }

  bool get _reducedMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  bool get _shouldTick {
    if (_state != ReadAloudState.playing) return false;
    try {
      if (_reducedMotion) return false;
      return ref.read(audioServiceProvider).activeUrl == widget.url;
    } catch (_) {
      return false;
    }
  }

  void _syncTicker() {
    if (!mounted) return;
    try {
      if (_shouldTick) {
        if (!_ticker.isActive) _ticker.start();
      } else if (_ticker.isActive) {
        _ticker.stop();
      }
    } catch (_) {}
  }

  void _onState(ReadAloudState state) {
    if (!mounted) return;
    setState(() {
      _state = _effective(state);
      if (_state != ReadAloudState.playing) _mouth = null;
    });
    _syncTicker();
  }

  void _onTick(Duration _) {
    if (!mounted || _state != ReadAloudState.playing) return;
    double? target;
    try {
      final audio = ref.read(audioServiceProvider);
      if (audio.activeUrl == widget.url) {
        target = audio.lipSyncLevel(widget.url, audio.position, audio.duration);
      }
    } on NoSuchMethodError {
      target = null; // Test fakes / minimal services: cadence fallback.
    } catch (_) {
      target = null;
    }
    if (target == null) {
      if (_mouth != null) setState(() => _mouth = null);
      return;
    }
    final current = _mouth ?? 0.0;
    // Fast attack (mouth snaps open on speech), gentle release (relaxes
    // into pauses instead of chattering).
    var next = current + (target - current) * (target > current ? 0.5 : 0.28);
    if ((next - target).abs() < 0.004) next = target;
    if (next != current) setState(() => _mouth = next);
  }

  @override
  Widget build(BuildContext context) {
    final mood = companionMoodFor(_state);
    return SahlhaCompanion(
      size: widget.size,
      mood: mood,
      mouthOpen: mood == CompanionMood.speaking ? _mouth : null,
    );
  }
}
