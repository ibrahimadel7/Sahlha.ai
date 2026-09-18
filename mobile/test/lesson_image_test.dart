import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/student/presentation/skill_lesson_screen.dart';

import 'student_redesign_test.dart' show PreviewStudentRepository, mount;

class ImageRepository extends PreviewStudentRepository {
  int imageCalls = 0;
  bool available = true;
  @override
  Future<Uint8List?> skillImageBytes({
    required String skillId,
    required String materialId,
    String? classroomId,
    bool supplementary = false,
  }) async {
    imageCalls++;
    expect(skillId, 'loops');
    expect(materialId, 'unit-a');
    expect(classroomId, 'room');
    return available
        ? base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
          )
        : null;
  }
}

/// The Learn redesign centers the avatar as the teacher: no separate audio
/// player card (no Slider) and no inline diagram. The skill visual remains
/// available on demand via Help me → Show visually (same backend bytes).
Future<void> openVisual(WidgetTester tester) async {
  await tester.tap(find.text('Help me'));
  await tester.pumpAndSettle();
  // 'Show visually' sits behind "More ways to help" for the default order.
  if (find.text('Show visually').evaluate().isEmpty) {
    await tester.tap(find.text('More ways to help'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Show visually'));
  await tester.pumpAndSettle();
}

void main() {
  const lesson = SkillLessonScreen(
    skillId: 'loops',
    materialId: 'unit-a',
    classroomId: 'room',
  );
  testWidgets('redesigned lesson teaches via avatar without a player card', (
    tester,
  ) async {
    final repo = ImageRepository();
    await mount(tester, lesson, repository: repo, navigation: false);
    // Avatar is the teacher; subtitles + collapsed explanation + Continue.
    expect(
      find.byKey(const ValueKey('avatar-teacher-gesture')),
      findsOneWidget,
    );
    expect(find.text('Read full explanation'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    // No separate audio-player card remains.
    expect(find.byType(Slider), findsNothing);
    expect(find.text('Listen to this explanation'), findsNothing);
    expect(find.text('Explore the lesson diagram'), findsNothing);
    // The visual is lazy: nothing fetched until the student asks for it.
    expect(repo.imageCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uncached lesson requests and displays its backend picture', (
    tester,
  ) async {
    final repo = ImageRepository();
    await mount(tester, lesson, repository: repo, navigation: false);
    expect(repo.imageCalls, 0);
    await openVisual(tester);
    await tester.ensureVisible(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(repo.imageCalls, 1);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unavailable image can be retried without reopening the lesson', (
    tester,
  ) async {
    final repo = ImageRepository()..available = false;
    await mount(tester, lesson, repository: repo, navigation: false);
    await openVisual(tester);
    await tester.ensureVisible(find.text('Try picture again').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Try picture again').first);
    await tester.pumpAndSettle();
    repo.available = true;
    await tester.tap(find.text('Try picture again'));
    await tester.pumpAndSettle();
    expect(repo.imageCalls, 2);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
