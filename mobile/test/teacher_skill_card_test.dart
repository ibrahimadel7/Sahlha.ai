import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/materials/domain/material.dart'
    show GeneratedSkill;
import 'package:sahlha/features/teacher/presentation/widgets/teacher_skill_card.dart';

void main() {
  for (final scale in [1.0, 1.8]) {
    testWidgets('Long skill content stays usable at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var expanded = false;
      var edits = 0;
      var removals = 0;
      final title = List.filled(5, 'Writing a chemical equation').join(' ');
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return TeacherSkillCard(
                      skill: GeneratedSkill(
                        id: 'skill',
                        name: title,
                        description: title,
                        explanation: 'Balance the atoms on each side.\n\nCheck each coefficient.',
                        keyConcepts: List.generate(
                          8,
                          (i) =>
                              'Concept $i: ${List.filled(8, 'chemical reaction').join(' ')}',
                        ),
                      ),
                      questionCount: 0,
                      evidenceTone: 'good',
                      evidenceLabel: 'Awaiting review',
                      expanded: expanded,
                      onTap: () => setState(() => expanded = !expanded),
                      onEdit: () => edits++,
                      onDelete: () => removals++,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(title), findsOneWidget);
      expect(find.text('Explanation'), findsNothing);
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.text('Explanation'), findsOneWidget);
      expect(find.text('Summary'), findsNothing);
      expect(find.byType(SelectableText), findsNWidgets(9));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Edit skill'));
      await tester.tap(find.text('Edit skill'));
      await tester.pump();
      await tester.ensureVisible(find.text('Remove'));
      await tester.tap(find.text('Remove'));
      expect(edits, 1);
      expect(removals, 1);
      expect(expanded, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
