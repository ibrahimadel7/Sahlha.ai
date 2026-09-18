import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/audio_service.dart';
import '../../../../core/theme/sahlha_colors.dart';
import '../../data/student_repository.dart';
import '../journey_presentation.dart';
import 'audio_companion.dart';
import 'lesson_content.dart';

/// Playback-speed cycle for double-tap on the avatar.
///
/// 1.0 -> 1.25 -> 1.5 -> 2.0 -> 1.0 (frontend only, via just_audio setSpeed).
double nextPlaybackSpeed(double current) {
  if (current >= 2.0) return 1.0;
  if (current >= 1.5) return 2.0;
  if (current >= 1.25) return 1.5;
  if (current >= 1.0) return 1.25;
  return 1.0;
}

/// Index of the subtitle chunk for [position] in [duration].
///
/// Frontend-only proportional estimate: the backend provides no word/sentence
/// timestamps, so progress fraction maps linearly onto chunks. Returns 0 when
/// timing is unavailable; clamps to the last chunk on completion.
int subtitleIndexFor(Duration position, Duration? duration, int count) {
  if (count <= 0) return 0;
  final totalMs = duration?.inMilliseconds ?? 0;
  if (totalMs <= 0) return 0;
  final fraction =
      (position.inMilliseconds / totalMs).clamp(0.0, 1.0).toDouble();
  var index = (fraction * count).floor();
  if (index < 0) index = 0;
  if (index >= count) index = count - 1;
  return index;
}

/// Splits [source] into short readable subtitle chunks.
///
/// Frontend-only: uses the existing explanation text, no backend timestamps.
/// Handles empty input, multiple paragraphs, punctuation, newlines and very
/// long sentences (split at word boundaries to ~120 chars so the UI never
/// overflows). Markdown markers are stripped for one-line readability; the
/// full explanation keeps its formatting via [LessonContent].
List<String> subtitleChunks(String source) {
  final cleaned = cleanStudentText(source).trim();
  if (cleaned.isEmpty) return [];
  // Split paragraphs first, then sentences (Latin + Arabic terminators).
  final paragraphs = cleaned.split(RegExp(r'\n+'));
  final sentences = <String>[];
  final sentenceSplit = RegExp(r'(?<=[.!?؟…])\s+');
  for (final paragraph in paragraphs) {
    final trimmed = paragraph.trim();
    if (trimmed.isEmpty) continue;
    for (final part in trimmed.split(sentenceSplit)) {
      final sentence = part.trim();
      if (sentence.isNotEmpty) sentences.add(sentence);
    }
  }
  if (sentences.isEmpty) return [cleaned];
  final result = <String>[];
  for (final sentence in sentences) {
    if (sentence.length <= 140) {
      result.add(sentence);
    } else {
      result.addAll(_splitLongSentence(sentence));
    }
  }
  return result.isEmpty ? [cleaned] : result;
}

/// Splits a very long sentence at word boundaries into ~120-char pieces.
/// Falls back to hard cuts for words longer than the limit.
List<String> _splitLongSentence(String sentence) {
  const limit = 120;
  final words = sentence.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final parts = <String>[];
  var current = StringBuffer();
  for (final word in words) {
    if (word.length > limit) {
      if (current.isNotEmpty) {
        parts.add(current.toString().trim());
        current = StringBuffer();
      }
      var remaining = word;
      while (remaining.length > limit) {
        parts.add(remaining.substring(0, limit));
        remaining = remaining.substring(limit);
      }
      if (remaining.isNotEmpty) {
        current.write(remaining);
        current.write(' ');
      }
      continue;
    }
    final candidate =
        current.isEmpty ? word : '${current.toString().trim()} $word';
    if (candidate.length > limit && current.isNotEmpty) {
      parts.add(current.toString().trim());
      current = StringBuffer(word);
      current.write(' ');
    } else {
      current = StringBuffer(candidate);
      current.write(' ');
    }
  }
  final tail = current.toString().trim();
  if (tail.isNotEmpty) parts.add(tail);
  return parts.isEmpty ? [sentence] : parts;
}

/// Large avatar-as-teacher for the Learn screen.
///
/// Single tap toggles play/pause (via the existing [AudioService], same audio
/// source as before). Double tap cycles playback speed
/// (1.0 -> 1.25 -> 1.5 -> 2.0 -> 1.0) with a temporary indicator.
/// Subtitles are a frontend-only proportional estimate from position/duration;
/// the full explanation stays available in a collapsed expandable section.
///
/// No separate audio-player card: the avatar is the only playback control.
class AvatarTeacher extends ConsumerStatefulWidget {
  const AvatarTeacher({
    super.key,
    required this.skillId,
    required this.materialId,
    this.classroomId,
    this.supplementary = false,
    required this.explanation,
    this.audioUrl,
    this.envelopeUrl,
    this.avatarSize = 180,
  });

  final String skillId;
  final String materialId;
  final String? classroomId;
  final bool supplementary;
  final String explanation;

  /// Overrides for tests; production resolves via [StudentRepository].
  final String? audioUrl;
  final String? envelopeUrl;
  final double avatarSize;

  @override
  ConsumerState<AvatarTeacher> createState() => _AvatarTeacherState();
}

class _AvatarTeacherState extends ConsumerState<AvatarTeacher> {
  late final String _url;
  late final String _envelopeUrl;

  /// Cached on every build: `ref` cannot be used in [dispose].
  AudioService? _audio;
  Timer? _speedTimer;
  double? _speedFlash;
  bool _expanded = false;
  bool _hasPlayed = false;

  @override
  void initState() {
    super.initState();
    if (widget.audioUrl != null) {
      // Explicit override (tests may pass '' to simulate missing audio).
      _url = widget.audioUrl!;
      _envelopeUrl = widget.envelopeUrl ?? '';
    } else {
      final repo = _readRepository();
      if (repo != null) {
        _url = repo.skillAudioUrl(
          skillId: widget.skillId,
          materialId: widget.materialId,
          classroomId: widget.classroomId,
          supplementary: widget.supplementary,
        );
        _envelopeUrl = repo.skillEnvelopeUrl(
          skillId: widget.skillId,
          materialId: widget.materialId,
          classroomId: widget.classroomId,
          supplementary: widget.supplementary,
        );
      } else {
        _url = widget.audioUrl ?? '';
        _envelopeUrl = widget.envelopeUrl ?? '';
      }
    }
  }

  StudentRepository? _readRepository() {
    try {
      return ref.read(studentRepositoryProvider);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    // Leaving the skill stops this explanation so two readings never overlap.
    final audio = _audio;
    if (audio != null) {
      try {
        if (audio.activeUrl == _url) {
          unawaited(audio.stop());
        }
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _onAvatarTap() async {
    final audio = ref.read(audioServiceProvider);
    // Loading: ignore duplicate taps (single-flight in the service too).
    try {
      if (audio.activeUrl == _url &&
          (audio.state == ReadAloudState.loading ||
              audio.state == ReadAloudState.ready)) {
        return;
      }
    } catch (_) {}
    HapticFeedback.selectionClick();
    try {
      if (audio.activeUrl == _url && audio.state == ReadAloudState.playing) {
        await audio.pause();
        return;
      }
      if (audio.activeUrl == _url && audio.state == ReadAloudState.paused) {
        await audio.resume();
        if (mounted) setState(() => _hasPlayed = true);
        return;
      }
      if (_url.isEmpty) return;
      final err = await audio.playUrl(_url, envelopeUrl: _envelopeUrl);
      if (mounted && err == null) setState(() => _hasPlayed = true);
      // Errors surface inline via stateStream (error state); the lesson
      // continues with subtitles + full explanation, no crash.
    } catch (_) {}
  }

  Future<void> _onAvatarDoubleTap() async {
    final audio = ref.read(audioServiceProvider);
    HapticFeedback.selectionClick();
    try {
      final next = nextPlaybackSpeed(audio.speed);
      await audio.setSpeed(next);
      if (!mounted) return;
      setState(() => _speedFlash = next);
      _speedTimer?.cancel();
      _speedTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _speedFlash = null);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final audio = ref.watch(audioServiceProvider);
    _audio = audio;
    final text = Theme.of(context).textTheme;
    final chunks = subtitleChunks(widget.explanation);
    final hasText = chunks.isNotEmpty;

    return StreamBuilder<ReadAloudState>(
      stream: audio.stateStream,
      initialData: _scopedState(audio),
      builder: (context, stateSnap) {
        var state = stateSnap.data ?? ReadAloudState.idle;
        try {
          if (audio.activeUrl != _url) state = ReadAloudState.idle;
        } catch (_) {
          state = ReadAloudState.idle;
        }
        final busy =
            state == ReadAloudState.loading || state == ReadAloudState.ready;
        final isError = state == ReadAloudState.error;
        final reduced = MediaQuery.disableAnimationsOf(context) ||
            MediaQuery.accessibleNavigationOf(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Large avatar (the teacher) ----
            Center(
              child: Semantics(
                button: true,
                enabled: !busy && _url.isNotEmpty,
                label: 'Avatar teacher. Single tap to ${state == ReadAloudState.playing ? 'pause' : 'listen'}. Double tap to change playback speed.',
                child: GestureDetector(
                  key: const ValueKey('avatar-teacher-gesture'),
                  behavior: HitTestBehavior.opaque,
                  // Flutter defers onTap until the double-tap window ends
                  // when both are set, so a double tap changes speed WITHOUT
                  // firing play/pause.
                  onTap: _onAvatarTap,
                  onDoubleTap: _onAvatarDoubleTap,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          key: const ValueKey('avatar-teacher-stage'),
                          width: widget.avatarSize + 44,
                          height: widget.avatarSize + 44,
                          decoration: BoxDecoration(
                            color: SahlhaColors.aquaSoft.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: state == ReadAloudState.playing
                                  ? SahlhaColors.joyTeal.withValues(alpha: 0.55)
                                  : SahlhaColors.borderSubtle,
                              width: 2,
                            ),
                            boxShadow: SahlhaShadows.soft,
                          ),
                        ),
                        AudioCompanion(url: _url, size: widget.avatarSize),
                        if (busy)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(10),
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: SahlhaColors.joyTeal,
                                ),
                              ),
                            ),
                          ),
                        if (!busy && state != ReadAloudState.playing)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isError
                                    ? SahlhaColors.softCoralSoft
                                    : SahlhaColors.joyTeal,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                              child: Icon(
                                isError
                                    ? Icons.refresh_rounded
                                    : state == ReadAloudState.paused
                                        ? Icons.play_arrow_rounded
                                        : _hasPlayed
                                            ? Icons.replay_rounded
                                            : Icons.play_arrow_rounded,
                                color: isError
                                    ? SahlhaColors.softCoralDark
                                    : Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        // Temporary speed feedback: readable, never blocks.
                        if (_speedFlash != null)
                          Positioned(
                            top: 0,
                            child: AnimatedOpacity(
                              opacity: 1,
                              duration: reduced
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              child: Container(
                                key: const ValueKey('avatar-teacher-speed'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: SahlhaColors.ink,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '${_trimSpeed(_speedFlash!)}x',
                                  style: text.labelLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ---- First-use affordance (subtle, disappears after first play) ----
            if (!_hasPlayed && state == ReadAloudState.idle && _url.isNotEmpty)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 2, bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: SahlhaColors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.touch_app_outlined,
                        size: 16,
                        color: SahlhaColors.joyTealDark,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Tap to listen',
                        style: text.bodySmall?.copyWith(
                          color: SahlhaColors.joyTealDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // ---- Status line ----
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  switch (state) {
                    ReadAloudState.loading || ReadAloudState.ready =>
                      'Getting the voice ready…',
                    ReadAloudState.playing => 'Sahlha is teaching…',
                    ReadAloudState.paused => 'Paused — tap the avatar to resume.',
                    ReadAloudState.stopped => 'Finished — tap to listen again.',
                    ReadAloudState.error =>
                      'Audio is unavailable right now.',
                    ReadAloudState.idle => _hasPlayed
                        ? 'Tap the avatar to listen again.'
                        : 'Hear it in a friendly voice.',
                  },
                  style: text.bodySmall?.copyWith(
                    color: SahlhaColors.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            // ---- Subtitles ----
            _SubtitleArea(
              chunks: chunks,
              audio: audio,
              url: _url,
              state: state,
            ),
            const SizedBox(height: 10),
            // ---- Full explanation (collapsed by default, optional) ----
            if (hasText)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: SahlhaColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      key: const ValueKey(
                        'avatar-teacher-full-explanation-toggle',
                      ),
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _expanded = !_expanded);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _expanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: SahlhaColors.joyTealDark,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _expanded
                                    ? 'Full explanation'
                                    : 'Read full explanation',
                                style: text.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: SahlhaColors.joyTealDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_expanded)
                      Container(
                        key: const ValueKey(
                          'avatar-teacher-full-explanation-body',
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: LessonContent(source: widget.explanation),
                      ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: SahlhaColors.borderSubtle),
                ),
                child: Text(
                  'Your teacher is preparing this explanation.',
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        );
      },
    );
  }

  ReadAloudState _scopedState(AudioService audio) {
    try {
      if (audio.activeUrl != _url) return ReadAloudState.idle;
      return audio.state;
    } catch (_) {
      return ReadAloudState.idle;
    }
  }

  String _trimSpeed(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    // 1.25 / 1.5 stay readable; avoid long float tails.
    return value.toStringAsFixed(value * 100 % 100 == 0 ? 0 : 2).replaceAll(
          RegExp(r'0+$'),
          '',
        ).replaceAll(RegExp(r'\.$'), '');
  }
}

class _SubtitleArea extends StatelessWidget {
  const _SubtitleArea({
    required this.chunks,
    required this.audio,
    required this.url,
    required this.state,
  });

  final List<String> chunks;
  final AudioService audio;
  final String url;
  final ReadAloudState state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (chunks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: SahlhaColors.borderSubtle),
        ),
        child: Text(
          'Your teacher is preparing this explanation.',
          style: text.bodyLarge?.copyWith(height: 1.6),
          textAlign: TextAlign.center,
        ),
      );
    }
    return StreamBuilder<Duration?>(
      stream: _durationStream(),
      initialData: _duration(),
      builder: (context, durationSnap) => StreamBuilder<Duration>(
        stream: _positionStream(),
        initialData: _position(),
        builder: (context, positionSnap) {
          final duration = durationSnap.data;
          final position = positionSnap.data ?? Duration.zero;
          final index = subtitleIndexFor(position, duration, chunks.length);
          final reduced = MediaQuery.disableAnimationsOf(context) ||
              MediaQuery.accessibleNavigationOf(context);
          return Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: state == ReadAloudState.playing
                    ? SahlhaColors.joyTeal.withValues(alpha: 0.4)
                    : SahlhaColors.borderSubtle,
                width: state == ReadAloudState.playing ? 1.6 : 1,
              ),
              boxShadow: SahlhaShadows.soft,
            ),
            child: Semantics(
              liveRegion: true,
              label: 'Spoken explanation, part ${index + 1} of ${chunks.length}',
              child: AnimatedSwitcher(
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                child: Text(
                  chunks[index],
                  key: ValueKey('subtitle-$index'),
                  style: text.bodyLarge?.copyWith(
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Duration? _duration() {
    try {
      if (audio.activeUrl != url) return null;
      return audio.duration;
    } catch (_) {
      return null;
    }
  }

  Stream<Duration?> _durationStream() {
    try {
      return audio.durationStream;
    } catch (_) {
      return const Stream.empty();
    }
  }

  Duration _position() {
    try {
      if (audio.activeUrl != url) return Duration.zero;
      return audio.position;
    } catch (_) {
      return Duration.zero;
    }
  }

  Stream<Duration> _positionStream() {
    try {
      return audio.positionStream;
    } catch (_) {
      return const Stream.empty();
    }
  }
}
