import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/student/domain/skill_models.dart';
import 'package:sahlha/features/student/presentation/widgets/interactive_examples.dart';

const _areaSkill = SkillBundle(
  skillId: 'area-models',
  name: 'Area Models of Multiplication',
  subject: 'Math',
  description: 'An area model shows 3 × 5 as an array of 3 rows of 5.',
  explanation: 'Multiplication as repeated addition. 3 rows of 5 = 15 squares.',
  keyConcepts: ['Array'],
);

const _areaExample = SkillHelp(
  kind: 'example',
  title: 'An example first',
  body: 'Look at 3 × 5. There are 3 rows and 5 columns.',
  steps: ['3 rows of 5 = 15 squares'],
);

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('seed comes from real backend text, not hardcoded content', () {
    final seed = parseMultiplicationSeed(
      skill: _areaSkill,
      example: _areaExample,
    );
    expect(seed.rows, 3);
    expect(seed.cols, 5);
    // Repeated-addition shaped backend also seeds correctly.
    const repeated = SkillHelp(
      kind: 'example',
      title: 'An example',
      body: '5 + 5 + 5 = 15',
    );
    final seed2 = parseMultiplicationSeed(
      skill: const SkillBundle(name: 'Multiplication', subject: 'Math'),
      example: repeated,
    );
    expect(seed2.rows, 3);
    expect(seed2.cols, 5);
  });

  test('presets prefer backend facts and always offer three', () {
    final seed = parseMultiplicationSeed(
      skill: _areaSkill,
      example: _areaExample,
    );
    final presets = parseMultiplicationPresets(
      skill: _areaSkill,
      example: _areaExample,
      seed: seed,
    );
    expect(presets.length, 3);
    expect(presets.contains(seed), isFalse);
  });

  testWidgets('grid, equation and repeated addition stay synchronized', (
    tester,
  ) async {
    await _mount(
      tester,
      const StudentExampleView(skill: _areaSkill, example: _areaExample),
    );
    expect(find.text('3 \u00d7 5 = 15'), findsOneWidget);
    expect(find.text('3 rows of 5 = 15 squares'), findsOneWidget);

    // Increase rows: 4 × 5 = 20, repeated addition gains one term.
    await tester.ensureVisible(find.byTooltip('Increase rows'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase rows'));
    await tester.pumpAndSettle();
    expect(find.text('4 \u00d7 5 = 20'), findsOneWidget);
    expect(tester.widget<AreaModelGrid>(find.byType(AreaModelGrid)).rows, 4);
    await tester.ensureVisible(find.byTooltip('Increase columns'));
    await tester.tap(find.byTooltip('Increase columns'));
    await tester.pumpAndSettle();
    expect(tester.widget<AreaModelGrid>(find.byType(AreaModelGrid)).cols, 6);
    expect(find.text('4 \u00d7 6 = 24'), findsOneWidget);
    await tester.ensureVisible(find.text('See repeated addition'));
    await tester.tap(find.text('See repeated addition'));
    await tester.pumpAndSettle();
    final repeated = tester.widget<RepeatedAdditionCard>(
      find.byType(RepeatedAdditionCard),
    );
    expect([repeated.rows, repeated.cols, repeated.product], [4, 6, 24]);

    // Presets work: tap 2 × 4 (scroll into view first).
    final preset = find.text('2 \u00d7 4').first;
    await tester.ensureVisible(preset);
    await tester.pumpAndSettle();
    await tester.tap(preset);
    await tester.pumpAndSettle();
    expect(find.text('2 \u00d7 4 = 8'), findsOneWidget);

    // Reset restores the backend seed.
    await tester.ensureVisible(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('3 \u00d7 5 = 15'), findsOneWidget);
  });

  testWidgets(
    'other subjects reuse the architecture without invented visuals',
    (tester) async {
      const skill = SkillBundle(
        name: 'Photosynthesis',
        subject: 'Science',
        description: 'Leaves collect light.',
      );
      const example = SkillHelp(
        kind: 'example',
        title: 'An example first',
        body: 'Leaves collect light to make food.',
        steps: ['Step 1: light hits the leaf'],
      );
      await _mount(
        tester,
        const StudentExampleView(skill: skill, example: example),
      );
      expect(find.textContaining('Leaves collect light'), findsWidgets);
      expect(find.textContaining('\u00d7'), findsNothing);
    },
  );

  testWidgets('narrow layout never overflows', (tester) async {
    await _mount(
      tester,
      const StudentExampleView(skill: _areaSkill, example: _areaExample),
      size: const Size(320, 568),
    );
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
