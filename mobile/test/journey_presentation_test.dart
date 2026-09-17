import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/student/presentation/journey_presentation.dart';

Map<String, dynamic> journeyFixture() => {
  'current': {'material_id': 'unit-a', 'skill_id': 'loops'},
  'units': [
    {
      'material_id': 'unit-a',
      'title': 'Lecture_11.pdf',
      'skills': [
        {
          'id': 'row-a',
          'skill_id': 'bool',
          'name': 'False (921200ded738)',
          'description': 'Python boolean values True and False',
          'state': 'mastered',
          'attempted': 4,
          'explanation': true,
          'exercise_ready': true,
          'practice_questions': 4,
        },
        {
          'id': 'row-b',
          'skill_id': 'loops',
          'name': 'Loops (921200ded738)',
          'description': 'A Python loop repeats code',
          'state': 'developing',
          'attempted': 4,
          'explanation': true,
          'exercise_ready': true,
          'practice_questions': 4,
        },
        {
          'id': 'row-c',
          'skill_id': 'looping',
          'name': 'Looping (921200ded738)',
          'description': 'Python loop statements',
          'state': 'not_started',
          'explanation': true,
          'exercise_ready': true,
          'practice_questions': 4,
        },
        {
          'id': 'row-d',
          'skill_id': 'list',
          'name': 'Mydlist (921200ded738)',
          'description': 'A Python list contains items',
          'state': 'not_started',
          'explanation': false,
          'exercise_ready': false,
        },
        {
          'id': 'row-e',
          'skill_id': 'statement',
          'name': 'Statements',
          'description': 'Python statements',
          'state': 'not_started',
          'explanation': false,
        },
        {
          'id': 'row-f',
          'skill_id': 'while',
          'name': 'While',
          'description': 'A Python while loop',
          'state': 'not_started',
          'explanation': false,
        },
      ],
    },
  ],
};

void main() {
  test('Titles remove IDs and filenames without mutating source models', () {
    final raw = journeyFixture();
    final unit = LearningJourney.fromJson(raw).units.single;
    expect(unit.title, 'Lecture 11');
    expect(unit.steps.first.title, 'False');
    expect(unit.steps[3].title, 'Mydlist');
    expect(unit.source.title, 'Lecture_11.pdf');
    expect(unit.steps.first.skill.name, 'False (921200ded738)');
    expect(
      studentTitle('921200ded738__While', context: 'Python loop'),
      'While',
    );
    expect(studentTitle('921200ded738'), 'Learning step');
  });

  test('Academic meaning is only normalized with supporting context', () {
    expect(
      studentTitle('False', context: 'False statements in logic'),
      'False',
    );
    expect(studentTitle('Mydlist', context: 'A proper name'), 'Mydlist');
    expect(studentTitle('While', context: 'English conjunctions'), 'While');
  });

  test(
    'Current matches both material and skill, and ready lessons stay available',
    () {
      final raw = journeyFixture();
      (raw['units'] as List).insert(0, {
        'material_id': 'other',
        'title': 'Other topic',
        'skills': [
          {
            'id': 'another-row',
            'skill_id': 'loops',
            'name': 'Loops',
            'explanation': true,
          },
        ],
      });
      final journey = LearningJourney.fromJson(raw);
      expect(journey.units.first.steps.single.state, JourneyState.available);
      expect(journey.activeUnit!.source.materialId, 'unit-a');
      expect(journey.units[1].steps.map((s) => s.state).toList().take(4), [
        JourneyState.completed,
        JourneyState.current,
        JourneyState.available,
        JourneyState.locked,
      ]);
    },
  );

  test('No current recommendation is invented when the API has none', () {
    final raw = journeyFixture()..['current'] = null;
    expect(LearningJourney.fromJson(raw).units.single.current, isNull);
  });

  test(
    'Checkpoint and unit review require actual progress and ready questions',
    () {
      final raw = journeyFixture();
      expect(
        LearningJourney.fromJson(raw).units.single.checkpointAfter(3),
        isNull,
      );
      final skills = (raw['units'] as List).first['skills'] as List;
      skills[2]['attempted'] = 1;
      expect(
        LearningJourney.fromJson(raw).units.single.checkpointAfter(3),
        isNotNull,
      );
      expect(LearningJourney.fromJson(raw).units.single.masteryReady, isFalse);
      for (final skill in skills) {
        skill['state'] = 'mastered';
        skill['exercise_ready'] = true;
      }
      expect(LearningJourney.fromJson(raw).units.single.masteryReady, isTrue);
      skills.last['exercise_ready'] = false;
      expect(LearningJourney.fromJson(raw).units.single.masteryReady, isFalse);
    },
  );

  test('Long lessons retain every word across manageable reading sections', () {
    final source = List.filled(
      45,
      'A loop repeats a useful instruction.',
    ).join(' ');
    final chunks = lessonSections(source);
    expect(chunks.length, greaterThan(1));
    expect(chunks.every((c) => c.length <= 420), isTrue);
    expect(chunks.join(' '), source);
  });

  test('Supplementary routes keep the source identifiers internally', () {
    final unit = LearningJourney.fromJson(journeyFixture()).units.single;
    final route = Uri.parse(lessonLocation(unit.current!, supplementary: true));
    expect(route.queryParameters['materialId'], 'unit-a');
    expect(route.queryParameters['supplementary'], 'true');
    expect(route.path, '/student/skill/loops');
  });
}
