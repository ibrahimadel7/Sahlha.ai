import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/student/presentation/widgets/engagement.dart';

void main() {
  group('effort labels', () {
    test('mastery states map to calm, non-judgmental labels', () {
      expect(effortLabelForMastery('mastered'), 'Solid understanding');
      expect(effortLabelForMastery('developing'), 'Growing steadily');
      expect(
        effortLabelForMastery('needs_practice'),
        'Needs a little more time',
      );
      expect(effortLabelForMastery('not_started'), 'Not started yet');
      expect(effortLabelForMastery('unknown'), 'Not started yet');
    });

    test('scores praise effort, never talent', () {
      expect(effortLabelForScore(1), 'Careful, steady work');
      expect(effortLabelForScore(0.8), 'Careful, steady work');
      expect(effortLabelForScore(0.6), 'Good effort — keep going');
      expect(effortLabelForScore(0.25), 'Every try counts');
      expect(effortLabelForScore(0), 'A brave first try');
    });
  });

  group('relative day labels', () {
    final now = DateTime(2026, 9, 16, 18, 30);

    test('today / yesterday / N days ago', () {
      expect(relativeDayLabel('2026-09-16T07:12:00.000000', now: now), 'Today');
      expect(relativeDayLabel('2026-09-15T23:59:00', now: now), 'Yesterday');
      expect(relativeDayLabel('2026-09-10T10:00:00', now: now), '6 days ago');
    });

    test('unknown stamps render nothing instead of guessing', () {
      expect(relativeDayLabel(null, now: now), isEmpty);
      expect(relativeDayLabel('', now: now), isEmpty);
      expect(relativeDayLabel('not-a-date', now: now), isEmpty);
    });

    test('most recent stamp wins across classrooms', () {
      expect(
        mostRecentStamp([
          null,
          '',
          '2026-09-14T10:00:00',
          '2026-09-16T07:12:00',
        ]),
        '2026-09-16T07:12:00',
      );
      expect(mostRecentStamp([null, '']), isNull);
    });

    test('practicedToday compares device-local days', () {
      expect(practicedToday('2026-09-16T07:12:00.000000', now: now), isTrue);
      expect(practicedToday('2026-09-15T07:12:00.000000', now: now), isFalse);
      expect(practicedToday(null, now: now), isFalse);
    });
  });

  group('daily goal', () {
    final now = DateTime(2026, 9, 16, 18, 30);

    test('one learning step when nothing practiced today', () {
      final goal = dailyGoalFor(
        hasStep: true,
        recentPracticedAt: '2026-09-14T10:00:00',
        stepTitle: 'Fractions',
        now: now,
      );
      expect(goal.doneToday, isFalse);
      expect(goal.title, 'Today’s goal: one learning step');
      expect(goal.message, contains('Fractions'));
    });

    test('done state is truthful and restful, never a streak', () {
      final goal = dailyGoalFor(
        hasStep: true,
        recentPracticedAt: '2026-09-16T07:12:00.000000',
        now: now,
      );
      expect(goal.doneToday, isTrue);
      expect(goal.title, 'Today’s step is done');
      expect(goal.message, isNot(contains('streak')));
    });

    test('no step means a waiting state, not an empty goal', () {
      final goal = dailyGoalFor(hasStep: false, now: now);
      expect(goal.hasStep, isFalse);
      expect(goal.doneToday, isFalse);
    });
  });

  group('subject visuals', () {
    test('known subjects map to meaningful visuals', () {
      expect(subjectVisualFor('Mathematics').icon, Icons.calculate_rounded);
      expect(subjectVisualFor('Python Programming').icon, Icons.code_rounded);
      expect(subjectVisualFor('English Reading').icon, Icons.menu_book_rounded);
      expect(subjectVisualFor('Science').icon, Icons.science_outlined);
    });

    test('unknown subjects fall back to the book mark', () {
      expect(
        subjectVisualFor('Something Entirely New').icon,
        Icons.auto_stories_rounded,
      );
      expect(subjectVisualFor('').icon, Icons.auto_stories_rounded);
    });

    test('programming concepts get glyphs, other skills get none', () {
      expect(
        conceptIconFor(title: 'While Loops', context: 'python control flow'),
        Icons.loop,
      );
      expect(
        conceptIconFor(title: 'Working with Lists', context: 'python lists'),
        Icons.list_alt,
      );
      expect(
        conceptIconFor(title: 'Fractions', context: 'math parts of a whole'),
        isNull,
      );
    });
  });

  group('why practice copy', () {
    test('every mode explains itself calmly', () {
      for (final mode in ['practice', 'checkpoint', 'mastery']) {
        final copy = whyPracticeCopy(mode);
        expect(copy.title, isNotEmpty);
        expect(copy.body, isNotEmpty);
        expect(copy.body.toLowerCase(), isNot(contains('score')));
      }
    });
  });

  group('widgets', () {
    testWidgets('companion and celebration render without errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SahlhaCompanion(size: 64),
                GentleCelebration(size: 88),
                EffortChip(label: 'Growing steadily'),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(SahlhaCompanion), findsOneWidget);
      expect(find.byType(GentleCelebration), findsOneWidget);
      expect(find.text('Growing steadily'), findsOneWidget);
    });

    testWidgets('daily goal is compact and has no competing primary action', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyGoalCard(goal: dailyGoalFor(hasStep: true)),
          ),
        ),
      );
      expect(find.text('1 learning step today'), findsOneWidget);
      expect(find.text('0 of 1 completed'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
