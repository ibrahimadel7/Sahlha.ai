import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/student/domain/skill_models.dart';
import 'package:sahlha/features/student/examples/domain/example_context.dart';
import 'package:sahlha/features/student/examples/domain/example_kind.dart';
import 'package:sahlha/features/student/examples/domain/example_resolver.dart';
import 'package:sahlha/features/student/examples/presentation/example_renderer_registry.dart';

void main() {
  const resolver = ExampleResolver();
  test('multiplication applications retain larger source factors', () {
    for (final title in [
      'Multiplication Applications',
      'Multiplication as Repeated Addition',
    ]) {
      final context = ExampleContext(
        subject: 'Math',
        skillName: title,
        keyConcepts: ['Repeated addition', 'Addition'],
        description: 'Use multiplication to calculate a cost.',
        examples: ['Six items cost 25 cents each: 6 × 25 = 150 cents.'],
      );
      expect(resolver.resolve(context).kind, ExampleKind.multiplicationGroups);
      expect(multiplicationPair(context), [6, 25]);
    }
    expect(
      resolver
          .resolve(
            ExampleContext(skillName: 'Repeated addition', examples: ['3 × 5']),
          )
          .kind,
      ExampleKind.multiplicationAreaModel,
    );
  });
  test(
    'skill title wins over related concepts and step numbers are validated',
    () {
      expect(
        resolver
            .resolve(
              ExampleContext(
                subject: 'Math',
                skillName: 'Multiplication',
                keyConcepts: ['Addition'],
                description: 'Addition of equal groups',
              ),
            )
            .kind,
        ExampleKind.multiplicationAreaModel,
      );
      expect(
        resolver
            .resolve(
              ExampleContext(
                skillName: 'Multiplication',
                steps: ['12 × 8 = 96'],
              ),
            )
            .kind,
        ExampleKind.multiplicationGroups,
      );
    },
  );
  final topics = {
    'Area Models of Multiplication': ExampleKind.multiplicationAreaModel,
    'Adding numbers on a number line': ExampleKind.additionNumberLine,
    'Subtracting integers using a number line':
        ExampleKind.subtractionNumberLine,
    'Understanding equivalent fractions': ExampleKind.fractionBars,
    'Fraction circles': ExampleKind.fractionCircle,
    'While loops': ExampleKind.loopTrace,
    'If / Else Conditions': ExampleKind.conditionFlow,
    'Variable Assignment': ExampleKind.variableState,
    'Code trace': ExampleKind.codeTrace,
    'Unknown topic': ExampleKind.conceptExplorer,
  };
  for (final entry in topics.entries) {
    test('resolves ${entry.key}', () {
      expect(
        resolver.resolve(ExampleContext(skillName: entry.key)).kind,
        entry.value,
      );
    });
  }
  test('uses supplied process, timeline, sentence and equation content', () {
    expect(
      resolver
          .resolve(
            ExampleContext(
              skillName: 'Photosynthesis',
              steps: ['Light is absorbed', 'Sugars are produced'],
            ),
          )
          .kind,
      ExampleKind.processFlow,
    );
    expect(
      resolver
          .resolve(
            ExampleContext(
              skillName: 'World War I Timeline',
              steps: ['1914: War begins', '1918: Armistice'],
            ),
          )
          .kind,
      ExampleKind.timeline,
    );
    expect(
      resolver
          .resolve(
            ExampleContext(
              skillName: 'Sentence word order',
              examples: ['The cat sleeps.'],
            ),
          )
          .kind,
      ExampleKind.sentenceBuilder,
    );
    expect(
      resolver
          .resolve(
            ExampleContext(
              skillName: 'Solving linear equations',
              examples: ['2x + 3 = 11'],
            ),
          )
          .kind,
      ExampleKind.equationSteps,
    );
  });
  test(
    'low confidence, ambiguity, missing facts and wrong domains fall back',
    () {
      for (final context in [
        ExampleContext(subject: 'Math', skillName: 'Topology'),
        ExampleContext(subject: 'Biology', skillName: 'Unknown cell mechanism'),
        ExampleContext(
          subject: 'Programming',
          skillName: 'Array multiplication',
        ),
        ExampleContext(subject: 'History', skillName: 'Industrial conditions'),
        ExampleContext(skillName: 'Addition and subtraction'),
        ExampleContext(skillName: 'Photosynthesis'),
        ExampleContext(skillName: 'World War I Timeline'),
        ExampleContext(skillName: 'Quadratic equations'),
        ExampleContext(skillName: 'Adding fractions'),
        ExampleContext(skillName: 'Nested loops'),
        ExampleContext(
          skillName: 'Solving equations',
          examples: ['x? + 3 = 12'],
        ),
      ]) {
        expect(
          resolver.resolve(context).kind,
          ExampleKind.conceptExplorer,
          reason: context.skillName,
        );
      }
    },
  );
  test('supported explicit metadata precedes semantics; unknown/invalid metadata is safe', () {
    expect(
      resolver
          .resolve(
            ExampleContext(
              skillName: 'Fractions',
              visualType: 'fraction_circle',
            ),
          )
          .kind,
      ExampleKind.fractionCircle,
    );
    expect(
      resolver
          .resolve(
            ExampleContext(skillName: 'Adding', visualType: 'arbitrary_widget'),
          )
          .kind,
      ExampleKind.additionNumberLine,
    );
    expect(
      resolver
          .resolve(
            ExampleContext(
              visualType: 'timeline',
              visualSpec: {'items': 'bad'},
            ),
          )
          .kind,
      ExampleKind.conceptExplorer,
    );
    expect(
      resolver.resolve(ExampleContext(visualType: 'number_line')).kind,
      ExampleKind.conceptExplorer,
    );
    expect(
      resolver
          .resolve(
            ExampleContext(
              subject: 'Science',
              skillName: 'Photosynthesis',
              visualType: 'area_model',
            ),
          )
          .kind,
      ExampleKind.conceptExplorer,
    );
  });
  test('retains and safely normalizes existing backend metadata', () {
    final bundle = SkillBundle.fromJson({
      'name': 'Photosynthesis',
      'learning_objective': 'Observe inputs',
      'learning_content': {
        'visual_type': 'process_sequence',
        'visual_spec': {
          'items': [
            {'label': 'Light', 'detail': 'Absorbed by pigments'},
            {'label': 'Sugars'},
            42,
          ],
        },
        'playground': {'interaction': 'step'},
      },
    });
    final context = ExampleContext.fromLesson(bundle, const SkillHelp());
    expect(context.learningObjective, 'Observe inputs');
    expect(context.items.length, 2);
    expect(resolver.resolve(context).kind, ExampleKind.processFlow);
    final malformed = ExampleContext.fromLesson(
      SkillBundle.fromJson({'learning_content': 42}),
      SkillHelp.fromJson({}),
    );
    expect(resolver.resolve(malformed).kind, ExampleKind.conceptExplorer);
    expect(exampleText(null), '');
    expect(exampleStrings([null, 2, '  hello  ']), ['hello']);
  });
  test(
    'unsupported numeric values and arbitrary code use the safe fallback',
    () {
      for (final context in [
        ExampleContext(skillName: 'Addition', examples: ['24 + 3']),
        ExampleContext(skillName: 'Addition', examples: ['1.5 + 2']),
        ExampleContext(skillName: 'Fractions', examples: ['7/3']),
        ExampleContext(skillName: 'Fractions', examples: ['1/0']),
        ExampleContext(skillName: 'Multiplication', examples: ['1200 x 8']),
        ExampleContext(
          skillName: 'Code trace',
          visualSpec: {'source_text': 'deleteEverything()'},
        ),
        ExampleContext(
          skillName: 'While loops',
          visualSpec: {'source_text': 'while true: erase()'},
        ),
      ]) {
        expect(resolver.resolve(context).kind, ExampleKind.conceptExplorer);
      }
    },
  );
  test('legacy source text supports grounded science and dated history', () {
    final science = ExampleContext(
      skillName: 'Photosynthesis',
      explanation: 'Pigments absorb light. Sugars are produced.',
    );
    expect(resolver.resolve(science).kind, ExampleKind.processFlow);
    expect(science.processStages.first.label, 'Pigments absorb light.');
    final history = ExampleContext(
      skillName: 'World War I Timeline',
      explanation: '1914: War begins. 1918: Armistice.',
    );
    expect(resolver.resolve(history).kind, ExampleKind.timeline);
    expect(history.timelineEvents.last.label, '1918: Armistice.');
  });
  test('every advertised kind has a registered native renderer', () {
    expect(
      ExampleRendererRegistry.builders.keys.toSet(),
      ExampleKind.values.toSet(),
    );
  });
}
