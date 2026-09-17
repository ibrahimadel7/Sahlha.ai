import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/student/domain/skill_models.dart';
import 'package:sahlha/features/student/presentation/journey_presentation.dart';

/// Navigation parameter consistency: every location builder must produce
/// URIs that the router (and the receiving screen) parse back identically.
/// A mismatch here strands the learner on a lesson that can never load
/// (e.g. an empty material scope -> backend 404 loop).
JourneyStep _step() => const JourneyStep(
  skill: PathSkill(id: 's1', skillId: 'skill-1', name: 'Fractions'),
  materialId: 'mat-1',
  title: 'Fractions',
  state: JourneyState.available,
  index: 0,
);

void main() {
  test('lessonLocation round-trips through the skill route readers', () {
    final loc = lessonLocation(
      _step(),
      classroomId: 'room-1',
      supplementary: false,
    );
    final uri = Uri.parse(loc);
    expect(uri.path, '/student/skill/skill-1');
    // Router reads these exact keys (router.dart skill route).
    expect(uri.queryParameters['materialId'], 'mat-1');
    expect(uri.queryParameters['classroomId'], 'room-1');
    expect(uri.queryParameters['supplementary'], isNull);
  });

  test('lessonLocation keeps supplementary scope without classroom', () {
    final loc = lessonLocation(_step(), supplementary: true);
    final uri = Uri.parse(loc);
    expect(uri.queryParameters['materialId'], 'mat-1');
    expect(uri.queryParameters['supplementary'], 'true');
    expect(uri.queryParameters['classroomId'], isNull);
  });

  test('practiceLocation round-trips through the practice route readers', () {
    final loc = practiceLocation(
      materialId: 'mat-1',
      skillId: 'skill-1',
      classroomId: 'room-1',
      mode: 'checkpoint',
    );
    final uri = Uri.parse(loc);
    expect(uri.path, '/student/practice');
    // Router reads these exact keys (router.dart practice route).
    expect(uri.queryParameters['materialId'], 'mat-1');
    expect(uri.queryParameters['skillId'], 'skill-1');
    expect(uri.queryParameters['classroomId'], 'room-1');
    expect(uri.queryParameters['mode'], 'checkpoint');
  });

  test('learningLocation round-trips through the learn route readers', () {
    final loc = learningLocation(classroomId: 'room-1');
    final uri = Uri.parse(loc);
    expect(uri.path, '/student/learn');
    expect(uri.queryParameters['classroomId'], 'room-1');

    final extra = Uri.parse(learningLocation(supplementary: true));
    expect(extra.queryParameters['supplementary'], 'true');
  });

  test('practiceLocation always carries a material scope', () {
    // The backend rejects assessments without a resolvable scope; the
    // location must never drop materialId when the caller has one.
    final uri = Uri.parse(
      practiceLocation(materialId: 'mat-9', mode: 'mastery'),
    );
    expect(uri.queryParameters['materialId'], 'mat-9');
    expect(uri.queryParameters['mode'], 'mastery');
  });
}
