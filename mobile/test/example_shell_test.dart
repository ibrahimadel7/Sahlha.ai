import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/student/examples/domain/example_context.dart';
import 'package:sahlha/features/student/examples/presentation/common/example_shell.dart';
import 'package:sahlha/features/student/examples/presentation/renderers/concept_explorer_example.dart';

void main() {
  testWidgets('key connections paint on the example card Material and expand', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConceptExplorerExample(
              context: ExampleContext(
                skillName: 'Unknown concept',
                description: 'Explore the source.',
                keyConcepts: ['Connection from the lesson'],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final tile = find.byType(ListTile);
    expect(tile, findsOneWidget);
    // The tile must reach the card's ink surface before a painted decoration.
    final ancestors = <Widget>[];
    tester.element(tile).visitAncestorElements((element) {
      ancestors.add(element.widget);
      return element.widget is! Material;
    });
    expect(ancestors.last, isA<Material>());
    expect(
      ancestors.whereType<DecoratedBox>().where(
        (box) =>
            box.decoration is BoxDecoration &&
            (box.decoration as BoxDecoration).color != null,
      ),
      isEmpty,
    );
    expect(
      find.descendant(
        of: find.byType(ExampleShell),
        matching: find.byType(Material),
      ),
      findsWidgets,
    );
    await tester.tap(find.text('Key connections'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('Connection from the lesson').hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.text('Key connections'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Connection from the lesson').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
