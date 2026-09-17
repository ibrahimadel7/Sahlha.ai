import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/student/examples/domain/example_context.dart';
import 'package:sahlha/features/student/examples/presentation/renderers/multiplication_groups_example.dart';

import 'adaptive_examples_test.dart' show mount, tap;

void main() {
  testWidgets(
    'larger source factors, stepping, totals and reset stay synchronized',
    (tester) async {
      await mount(
        tester,
        MultiplicationGroupsExample(
          context: ExampleContext(examples: ['6 × 25 = 150']),
        ),
        scale: 1.4,
      );
      expect(find.text('6 × 25 = 150'), findsOneWidget);
      await tap(tester, find.text('Add one group'));
      expect(find.text('1 of 6 groups • Total so far: 25'), findsOneWidget);
      await tap(tester, find.text('Show all groups'));
      expect(find.text('6 of 6 groups • Total so far: 150'), findsOneWidget);
      await tap(tester, find.byTooltip('Increase In each group'));
      expect(find.text('6 × 26 = 156'), findsOneWidget);
      expect(find.text('0 of 6 groups • Total so far: 0'), findsOneWidget);
      await tap(tester, find.text('Reset'));
      expect(find.text('6 × 25 = 150'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'switching skills resets values and supports zero without division errors',
    (tester) async {
      await mount(
        tester,
        MultiplicationGroupsExample(
          context: ExampleContext(examples: ['12 × 8']),
        ),
      );
      await tap(tester, find.text('Show all groups'));
      await mount(
        tester,
        MultiplicationGroupsExample(
          context: ExampleContext(examples: ['0 × 25']),
        ),
      );
      expect(find.text('0 × 25 = 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
