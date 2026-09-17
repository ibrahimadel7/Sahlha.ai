import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/student/domain/skill_models.dart';
import 'package:sahlha/features/student/presentation/widgets/learning_playground.dart';

Future<void> mountPlayground(WidgetTester tester, SkillBundle skill) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: SingleChildScrollView(
            child: LearningPlayground(skill: skill, subject: skill.subject),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reduced-motion counter advances only on student action', (
    tester,
  ) async {
    await mountPlayground(
      tester,
      const SkillBundle(
        name: 'Counter',
        subject: 'Programming',
        explanation: '```python\ni = 1\nwhile i < 3:\n print(i)\n i += 1\n```',
      ),
    );
    expect(find.text('i = 1'), findsWidgets);
    await tester.pump(const Duration(seconds: 10));
    // i=1 while i<3 yields 8 safe frames (init + 2×3 steps + exit).
    expect(find.text('Step 1 of 8'), findsOneWidget);
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(find.text('1 < 3 is true: repeat.'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets('math uses numbers from the lesson and supports dragging', (
    tester,
  ) async {
    await mountPlayground(
      tester,
      const SkillBundle(
        name: 'Addition',
        subject: 'Math',
        explanation: '2 + 3 = 5',
      ),
    );
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 2);
    expect(slider.max, 5);
    slider.onChanged!(4);
    await tester.pumpAndSettle();
    expect(find.text('Number line: 4.0'), findsOneWidget);
  });
  testWidgets('language construction keeps source words and can be reset', (
    tester,
  ) async {
    await mountPlayground(
      tester,
      const SkillBundle(
        name: 'Sentence',
        subject: 'Language',
        explanation: 'Birds can fly.',
      ),
    );
    await tester.tap(find.widgetWithText(FilterChip, 'Birds'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Birds'))
          .selected,
      isTrue,
    );
    await tester.tap(find.text('Try another arrangement'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Birds'))
          .selected,
      isFalse,
    );
  });
  for (final skill in [
    const SkillBundle(
      name: 'Plant parts',
      subject: 'Science',
      keyConcepts: ['Roots absorb water', 'Leaves collect light'],
    ),
    const SkillBundle(
      name: 'Events',
      subject: 'History',
      explanation: '1900: First event.\n1910: Next event.',
    ),
    const SkillBundle(
      name: 'Coordinates',
      subject: 'Geography',
      explanation: '30 N, 31 E',
    ),
  ]) {
    testWidgets(
      '${skill.subject} reveals source-backed visuals without overflow',
      (tester) async {
        await mountPlayground(tester, skill);
        expect(tester.takeException(), isNull);
        expect(find.byType(CustomPaint), findsWidgets);
      },
    );
  }
}
