import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/core/audio/audio_service.dart';
import 'package:sahlha/features/student/presentation/widgets/avatar_teacher.dart';

class FakeTeacherAudio extends Fake implements AudioService {
  final events = StreamController<ReadAloudState>.broadcast();
  final positionEvents = StreamController<Duration>.broadcast();
  final durationEvents = StreamController<Duration?>.broadcast();

  @override
  String? activeUrl;
  @override
  ReadAloudState state = ReadAloudState.idle;
  @override
  Stream<ReadAloudState> get stateStream => events.stream;

  Duration positionValue = Duration.zero;
  Duration? durationValue = const Duration(seconds: 10);

  @override
  Duration get position =>
      activeUrl == null ? Duration.zero : positionValue;
  @override
  Duration? get duration => activeUrl == null ? null : durationValue;
  @override
  Stream<Duration> get positionStream => positionEvents.stream;
  @override
  Stream<Duration?> get durationStream => durationEvents.stream;

  @override
  double speed = 1.0;
  int plays = 0;
  int pauses = 0;
  int resumes = 0;
  int stops = 0;
  final speeds = <double>[];

  @override
  double? lipSyncLevel(String audioUrl, Duration position, Duration? duration) =>
      null;

  @override
  Future<String?> playUrl(String url, {String? envelopeUrl}) async {
    // Mirror the real single-flight: taps while loading are ignored.
    if (activeUrl == url && state == ReadAloudState.loading) return null;
    if (activeUrl == url && state == ReadAloudState.playing) return null;
    if (activeUrl == url && state == ReadAloudState.paused) {
      await resume();
      return null;
    }
    plays++;
    activeUrl = url;
    state = ReadAloudState.playing;
    events.add(state);
    return null;
  }

  @override
  Future<void> pause() async {
    pauses++;
    state = ReadAloudState.paused;
    events.add(state);
  }

  @override
  Future<void> resume() async {
    resumes++;
    state = ReadAloudState.playing;
    events.add(state);
  }

  @override
  Future<void> stop() async {
    stops++;
    activeUrl = null;
    state = ReadAloudState.stopped;
    events.add(state);
  }

  @override
  Future<void> seek(Duration value) async {
    positionValue = value;
    positionEvents.add(value);
  }

  @override
  Future<void> setSpeed(double value) async {
    speeds.add(value);
    speed = value;
  }

  void emitState(ReadAloudState next, {String? url}) {
    if (url != null) activeUrl = url;
    state = next;
    events.add(next);
  }

  void emitPosition(Duration position, Duration? duration) {
    positionValue = position;
    durationValue = duration;
    positionEvents.add(position);
    durationEvents.add(duration);
  }

  Future<void> close() async {
    await events.close();
    await positionEvents.close();
    await durationEvents.close();
  }
}

Future<void> mountAvatar(
  WidgetTester tester,
  FakeTeacherAudio fake, {
  String explanation =
      'Plants use sunlight to make food. They absorb carbon dioxide from the air. Water enters through their roots.',
  String audioUrl = 'lesson',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [audioServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SingleChildScrollView(
              child: AvatarTeacher(
                skillId: 's1',
                materialId: 'm1',
                explanation: explanation,
                audioUrl: audioUrl,
                avatarSize: 120,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get avatarGesture =>
    find.byKey(const ValueKey('avatar-teacher-gesture'));
Finder get speedBadge => find.byKey(const ValueKey('avatar-teacher-speed'));
Finder get expandToggle =>
    find.byKey(const ValueKey('avatar-teacher-full-explanation-toggle'));

void main() {
  group('nextPlaybackSpeed', () {
    test('cycles 1x → 1.25x → 1.5x → 2x → 1x', () {
      expect(nextPlaybackSpeed(1.0), 1.25);
      expect(nextPlaybackSpeed(1.25), 1.5);
      expect(nextPlaybackSpeed(1.5), 2.0);
      expect(nextPlaybackSpeed(2.0), 1.0);
    });

    test('out-of-range speeds reset to 1x', () {
      expect(nextPlaybackSpeed(0.75), 1.0);
      expect(nextPlaybackSpeed(0.5), 1.0);
      expect(nextPlaybackSpeed(3.0), 1.0);
    });
  });

  group('subtitleChunks', () {
    test('empty explanation yields no chunks', () {
      expect(subtitleChunks(''), isEmpty);
      expect(subtitleChunks('   \n  '), isEmpty);
    });

    test('one sentence stays whole', () {
      expect(
        subtitleChunks('Plants use sunlight to make food.'),
        ['Plants use sunlight to make food.'],
      );
    });

    test('multiple sentences split', () {
      final chunks = subtitleChunks(
        'Plants use sunlight to make food. They absorb carbon dioxide. Water enters through roots.',
      );
      expect(chunks.length, 3);
      expect(chunks.first, contains('sunlight'));
    });

    test('paragraphs and newlines split', () {
      final chunks = subtitleChunks('First idea.\n\nSecond idea.\nThird idea.');
      expect(chunks.length, 3);
    });

    test('very long sentence splits at word boundaries', () {
      final long = '${'word ' * 60}.';
      final chunks = subtitleChunks(long);
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(140));
      }
      expect(chunks.join(' '), contains('word'));
    });

    test('unusual formatting never produces empty chunks', () {
      final chunks = subtitleChunks('... !!! ??? \n\n ...');
      for (final chunk in chunks) {
        expect(chunk.trim(), isNotEmpty);
      }
    });
  });

  group('subtitleIndexFor', () {
    test('no timing stays at first chunk', () {
      expect(subtitleIndexFor(Duration.zero, null, 3), 0);
      expect(subtitleIndexFor(Duration.zero, Duration.zero, 3), 0);
      expect(subtitleIndexFor(Duration.zero, const Duration(seconds: 10), 0), 0);
    });

    test('progress maps proportionally', () {
      const total = Duration(seconds: 10);
      expect(subtitleIndexFor(Duration.zero, total, 4), 0);
      expect(subtitleIndexFor(const Duration(seconds: 3), total, 4), 1);
      expect(subtitleIndexFor(const Duration(seconds: 5), total, 4), 2);
      expect(subtitleIndexFor(const Duration(seconds: 9), total, 4), 3);
    });

    test('completion clamps to last chunk', () {
      const total = Duration(seconds: 10);
      expect(
        subtitleIndexFor(const Duration(seconds: 10), total, 3),
        2,
      );
      expect(
        subtitleIndexFor(const Duration(seconds: 99), total, 3),
        2,
      );
    });
  });

  group('AvatarTeacher widget', () {
    testWidgets('shows avatar, first subtitle, collapsed explanation',
        (tester) async {
      final fake = FakeTeacherAudio();
      await mountAvatar(tester, fake);
      expect(avatarGesture, findsOneWidget);
      expect(find.text('Plants use sunlight to make food.'), findsOneWidget);
      expect(find.text('Read full explanation'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('avatar-teacher-full-explanation-body')),
        findsNothing,
      );
      expect(find.text('Tap to listen'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await fake.close();
    });

    testWidgets('avatar stage is a rounded square, not a circle',
        (tester) async {
      final fake = FakeTeacherAudio();
      await mountAvatar(tester, fake);
      final stage = tester.widget<Container>(
        find.byKey(const ValueKey('avatar-teacher-stage')),
      );
      final decoration = stage.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.rectangle);
      expect(decoration.borderRadius, isNotNull);
      // Square region: equal width and height.
      final size = tester.getSize(
        find.byKey(const ValueKey('avatar-teacher-stage')),
      );
      expect(size.width, size.height);
      expect(size.width, greaterThan(150));
      await tester.pumpWidget(const SizedBox());
      await fake.close();
    });

    testWidgets('full explanation expands and collapses', (tester) async {
      final fake = FakeTeacherAudio();
      await mountAvatar(tester, fake);
      await tester.tap(expandToggle);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('avatar-teacher-full-explanation-body')),
        findsOneWidget,
      );
      expect(find.text('Full explanation'), findsOneWidget);
      await tester.tap(expandToggle);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('avatar-teacher-full-explanation-body')),
        findsNothing,
      );
      expect(find.text('Read full explanation'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await fake.close();
    });

    testWidgets('single tap plays, pauses, resumes', (tester) async {
      final fake = FakeTeacherAudio();
      await mountAvatar(tester, fake);

      await tester.tap(avatarGesture);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(fake.plays, 1);
      expect(find.text('Sahlha is teaching…'), findsOneWidget);

      await tester.tap(avatarGesture);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(fake.pauses, 1);

      await tester.tap(avatarGesture);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(fake.resumes, 1);
      await tester.pumpWidget(const SizedBox());
      await fake.close();
    });

    testWidgets('tapping during loading does not duplicate requests',
        (tester) async {
      final fake = FakeTeacherAudio();
      await mountAvatar(tester, fake);
      fake.emitState(ReadAloudState.loading, url: 'lesson');
      // Spinner never settles: pump explicitly instead of pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Getting the voice ready…'), findsOneWidget);

      await tester.tap(avatarGesture);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(fake.plays, 0);
      expect(fake.pauses, 0);
      await tester.pumpWidget(const SizedBox());
      await fake.close();
    });

    testWidgets('double tap changes speed without play/pause', (tester) async {
      final fake = FakeTeacherAudio();
      await mountAvatar(tester, fake);

      await tester.tap(avatarGesture);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(avatarGesture);
      await tester.pumpAndSettle();

      expect(fake.speeds, [1.25]);
      expect(fake.plays, 0);
      expect(fake.pauses, 0);
      expect(speedBadge, findsOneWidget);
      expect(find.text('1.25x'), findsOneWidget);

      // Feedback fades after a short period.
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();
      expect(speedBadge, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await fake.close();
    });

    testWidgets('repeated double taps cycle 1.25 → 1.5 → 2 → 1', (tester) async {
      final fake = FakeTeacherAudio();
      await mountAvatar(tester, fake);
      for (final expected in [1.25, 1.5, 2.0, 1.0]) {
        await tester.tap(avatarGesture);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(avatarGesture);
        await tester.pumpAndSettle();
        expect(fake.speed, expected);
        await tester.pump(const Duration(milliseconds: 1300));
      }
      expect(fake.speeds, [1.25, 1.5, 2.0, 1.0]);
      expect(fake.plays, 0);
      expect(fake.pauses, 0);
      await tester.pumpWidget(const SizedBox());
      await fake.close();
    });

    testWidgets('subtitles follow position and finish on completion',
        (tester) async {
      final fake = FakeTeacherAudio();
      await mountAvatar(tester, fake);
      fake.emitState(ReadAloudState.playing, url: 'lesson');
      fake.emitPosition(Duration.zero, const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Plants use sunlight to make food.'), findsOneWidget);

      fake.emitPosition(const Duration(seconds: 15), const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(
        find.text('They absorb carbon dioxide from the air.'),
        findsOneWidget,
      );

      fake.emitState(ReadAloudState.stopped, url: 'lesson');
      fake.emitPosition(const Duration(seconds: 30), const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Finished — tap to listen again.'), findsOneWidget);
      expect(
        find.text('Water enters through their roots.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await fake.close();
    });

    testWidgets('error state stays usable with explanation', (tester) async {
      final fake = FakeTeacherAudio();
      await mountAvatar(tester, fake);
      fake.emitState(ReadAloudState.error, url: 'lesson');
      await tester.pumpAndSettle();
      expect(find.text('Audio is unavailable right now.'), findsOneWidget);
      // Subtitles fall back to the first chunk; full text stays available.
      expect(find.text('Plants use sunlight to make food.'), findsOneWidget);
      expect(find.text('Read full explanation'), findsOneWidget);
      await tester.tap(expandToggle);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('avatar-teacher-full-explanation-body')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await fake.close();
    });

    testWidgets('empty explanation renders a calm placeholder', (tester) async {
      final fake = FakeTeacherAudio();
      await mountAvatar(tester, fake, explanation: '   ');
      expect(
        find.text('Your teacher is preparing this explanation.'),
        findsWidgets,
      );
      expect(expandToggle, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await fake.close();
    });

    testWidgets('missing audio keeps the lesson usable', (tester) async {
      final fake = FakeTeacherAudio();
      await mountAvatar(tester, fake, audioUrl: '');
      await tester.tap(avatarGesture);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(fake.plays, 0);
      expect(tester.takeException(), isNull);
      expect(find.text('Read full explanation'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await fake.close();
    });

    testWidgets('long explanation does not overflow a narrow screen',
        (tester) async {
      final fake = FakeTeacherAudio();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final long =
          'Plants use sunlight to make food through photosynthesis in their green leaves. '
              * 20;
      await mountAvatar(tester, fake, explanation: long);
      await tester.tap(expandToggle);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await fake.close();
    });
  });
}
