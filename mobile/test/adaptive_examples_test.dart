import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/student/domain/skill_models.dart';
import 'package:sahlha/features/student/examples/presentation/adaptive_example_screen.dart';
import 'package:sahlha/features/student/examples/domain/example_context.dart';
import 'package:sahlha/features/student/examples/domain/example_kind.dart';
import 'package:sahlha/features/student/examples/presentation/example_renderer_registry.dart';
import 'package:sahlha/features/student/examples/presentation/renderers/number_line_example.dart';
import 'package:sahlha/features/student/examples/presentation/renderers/fraction_example.dart';
import 'package:sahlha/features/student/examples/presentation/renderers/code_trace_example.dart';
import 'package:sahlha/features/student/examples/presentation/renderers/concept_explorer_example.dart';

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'addition updates start and jumps; reset restores lesson values',
    (tester) async {
      await mount(
        tester,
        NumberLineExample(context: ExampleContext(examples: ['4 + 3'])),
      );
      await tap(tester, find.text('Move +1'));
      expect(find.text('Position: 5 \u2022 1 / 3 jumps'), findsOneWidget);
      await tap(tester, find.byTooltip('Increase Start'));
      expect(find.text('Position: 5 \u2022 0 / 3 jumps'), findsOneWidget);
      await tap(tester, find.text('Reset'));
      expect(find.text('Position: 4 \u2022 0 / 3 jumps'), findsOneWidget);
    },
  );
  testWidgets('subtraction walks backward through zero', (tester) async {
    await mount(
      tester,
      NumberLineExample(
        context: ExampleContext(examples: ['1 - 2']),
        subtract: true,
      ),
    );
    await tap(tester, find.text('Move \u22121'));
    await tap(tester, find.text('Move \u22121'));
    expect(find.text('1 \u2212 2 = -1'), findsOneWidget);
  });
  testWidgets('fraction denominator clamps selection and painters stay valid', (
    tester,
  ) async {
    await mount(
      tester,
      FractionExample(context: ExampleContext(examples: ['3/4'])),
    );
    await tap(tester, find.byTooltip('Decrease Denominator'));
    await tap(tester, find.byTooltip('Decrease Denominator'));
    expect(find.text('2 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('code trace changes state and output without executing code', (
    tester,
  ) async {
    await mount(tester, CodeTraceExample(context: ExampleContext()));
    expect(find.text('x = 2'), findsWidgets);
    await tap(tester, find.text('Next step'));
    expect(find.text('x = 5'), findsOneWidget);
    await tap(tester, find.text('Next step'));
    expect(find.text('x = 5\nOutput: 5'), findsOneWidget);
  });
  testWidgets('loop terminates and shows final false condition', (
    tester,
  ) async {
    await mount(
      tester,
      CodeTraceExample(context: ExampleContext(), mode: TraceMode.loop),
    );
    for (var i = 0; i < 10; i++) {
      await tap(tester, find.text('Next step'));
    }
    expect(find.textContaining('Condition: false'), findsOneWidget);
    expect(find.textContaining('Output: [0, 1, 2]'), findsOneWidget);
    expect(find.text('Run walkthrough'), findsNothing);
  });
  testWidgets('generic minimal context and long content reveal progressively', (
    tester,
  ) async {
    await mount(tester, ConceptExplorerExample(context: ExampleContext()));
    expect(find.text('Explore this concept'), findsOneWidget);
    await tap(tester, find.text('Reflect on the idea'));
    expect(find.textContaining('Compare your explanation'), findsOneWidget);
  });
  testWidgets(
    'lesson change selects a different renderer and resets local state',
    (tester) async {
      var skill = const SkillBundle(name: 'Addition', subject: 'Math');
      late StateSetter update;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return StudentExampleView(skill: skill, example: const SkillHelp());
          },
        ),
      );
      await tap(tester, find.text('Move +1'));
      update(
        () => skill = const SkillBundle(name: 'Fractions', subject: 'Math'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FractionExample), findsOneWidget);
      expect(find.byType(NumberLineExample), findsNothing);
      update(
        () => skill = const SkillBundle(name: 'Addition', subject: 'Math'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Position: 4 \u2022 0 / 3 jumps'), findsOneWidget);
    },
  );
  testWidgets('supplied assignment values and output are traced faithfully', (
    tester,
  ) async {
    await mount(
      tester,
      CodeTraceExample(
        context: ExampleContext(
          visualSpec: {
            'source_text': 'int total = 7;\ntotal = total + 4;\nprint(total);',
          },
        ),
      ),
    );
    await tap(tester, find.text('Next step'));
    await tap(tester, find.text('Next step'));
    expect(find.text('total = 11\nOutput: 11'), findsOneWidget);
  });
  testWidgets('supplied loop uses the existing bounded trace parser', (
    tester,
  ) async {
    await mount(
      tester,
      CodeTraceExample(
        context: ExampleContext(
          visualSpec: {
            'source_text':
                'count = 2\nwhile count < 4:\n print(count)\n count += 1',
          },
        ),
        mode: TraceMode.loop,
      ),
    );
    for (var i = 0; i < 7; i++) {
      await tap(tester, find.text('Next step'));
    }
    expect(find.textContaining('Output: [2, 3]'), findsOneWidget);
    expect(find.textContaining('false: exit'), findsOneWidget);
  });
  testWidgets('equation reveals operations and resets', (tester) async {
    await mount(
      tester,
      ExampleRendererRegistry.build(
        ExampleKind.equationSteps,
        ExampleContext(examples: ['2x + 3 = 11']),
      ),
    );
    await tap(tester, find.text('Reveal the next operation'));
    expect(find.text('2 x = 8'), findsOneWidget);
    expect(find.text('Subtract 3 from both sides.'), findsOneWidget);
    await tap(tester, find.text('Reveal the next operation'));
    expect(find.text('x = 4'), findsOneWidget);
    await tap(tester, find.text('Reset'));
    expect(find.text('2 x + 3 = 11'), findsOneWidget);
  });
  testWidgets('timeline reveals supplied event detail only', (tester) async {
    await mount(
      tester,
      ExampleRendererRegistry.build(
        ExampleKind.timeline,
        ExampleContext(
          visualSpec: {
            'items': [
              {
                'label': '1914: War begins',
                'detail': 'The supplied opening event.',
              },
              {
                'label': '1918: Armistice',
                'detail': 'The supplied final event.',
              },
            ],
          },
        ),
      ),
    );
    expect(find.text('The supplied opening event.'), findsNothing);
    await tap(tester, find.text('Explore this stage'));
    expect(find.text('The supplied opening event.'), findsOneWidget);
    await tap(tester, find.text('Next event'));
    expect(find.text('The supplied opening event.'), findsNothing);
  });
  testWidgets(
    'sentence tokens can be ordered, undone and revealed without scoring',
    (tester) async {
      await mount(
        tester,
        ExampleRendererRegistry.build(
          ExampleKind.sentenceBuilder,
          ExampleContext(examples: ['The cat sleeps.']),
        ),
      );
      await tap(tester, find.text('The'));
      await tap(tester, find.text('cat'));
      expect(find.text('The cat'), findsOneWidget);
      await tap(tester, find.text('Undo'));
      await tap(tester, find.text('Reveal lesson sentence'));
      expect(find.text('Lesson sentence: The cat sleeps.'), findsOneWidget);
    },
  );
  for (final kind in ExampleKind.values) {
    testWidgets('${kind.name} fits narrow phone with large text', (
      tester,
    ) async {
      final context = ExampleContext(
        skillName: 'Explore',
        examples: ['2x + 3 = 11'],
        steps: ['1914: First supplied stage', '1918: Second supplied stage'],
        visualSpec: {
          'items': [
            {'label': 'First component', 'detail': 'A supplied detail'},
            {'label': 'Second component'},
          ],
          'source_text': 'The cat sleeps.',
        },
      );
      await mount(
        tester,
        ExampleRendererRegistry.build(kind, context),
        scale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
