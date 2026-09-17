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

void main() {
  const lesson = SkillLessonScreen(
    skillId: 'loops',
    materialId: 'unit-a',
    classroomId: 'room',
  );
  testWidgets('uncached lesson requests and displays its backend picture', (
    tester,
  ) async {
    final repo = ImageRepository();
    await mount(tester, lesson, repository: repo, navigation: false);
    expect(repo.imageCalls, 0);
    await tester.scrollUntilVisible(
      find.text('Explore the lesson diagram'),
      200,
    );
    await tester.ensureVisible(find.text('Explore the lesson diagram'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explore the lesson diagram'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(Image), 200);
    await tester.pumpAndSettle();
    expect(repo.imageCalls, 1);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Listen to this explanation'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unavailable image can be retried without reopening the lesson', (
    tester,
  ) async {
    final repo = ImageRepository()..available = false;
    await mount(tester, lesson, repository: repo, navigation: false);
    await tester.scrollUntilVisible(
      find.text('Explore the lesson diagram'),
      200,
    );
    await tester.ensureVisible(find.text('Explore the lesson diagram'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explore the lesson diagram'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Try picture again'), 200);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Try picture again'));
    await tester.pumpAndSettle();
    repo.available = true;
    await tester.tap(find.text('Try picture again'));
    await tester.pumpAndSettle();
    expect(repo.imageCalls, 2);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
