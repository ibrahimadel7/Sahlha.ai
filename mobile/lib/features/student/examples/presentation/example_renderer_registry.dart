import 'package:flutter/material.dart';

import '../../domain/skill_models.dart';
import '../../presentation/widgets/interactive_examples.dart'
    show AreaModelExample;
import '../domain/example_context.dart';
import '../domain/example_kind.dart';
import '../domain/example_resolver.dart';
import 'renderers/concept_explorer_example.dart';
import 'renderers/multiplication_groups_example.dart';
import 'renderers/number_line_example.dart';
import 'renderers/fraction_example.dart';
import 'renderers/equation_steps_example.dart';
import 'renderers/code_trace_example.dart';
import 'renderers/condition_flow_example.dart';
import 'renderers/source_sequence_example.dart';
import 'renderers/sentence_builder_example.dart';

typedef ExampleBuilder = Widget Function(ExampleContext context);

class ExampleRendererRegistry {
  static final Map<ExampleKind, ExampleBuilder> builders = Map.unmodifiable({
    ExampleKind.multiplicationGroups: (c) =>
        MultiplicationGroupsExample(context: c),
    ExampleKind.multiplicationAreaModel: (c) => AreaModelExample(
      skill: SkillBundle(
        name: c.skillName,
        description: c.description,
        explanation: c.explanation,
      ),
      example: SkillHelp(
        body: c.examples.join('\n'),
        steps: [exampleText(c.visualSpec['source_text']), ...c.steps],
      ),
    ),
    ExampleKind.additionNumberLine: (c) => NumberLineExample(context: c),
    ExampleKind.subtractionNumberLine: (c) =>
        NumberLineExample(context: c, subtract: true),
    ExampleKind.fractionBars: (c) => FractionExample(context: c),
    ExampleKind.fractionCircle: (c) =>
        FractionExample(context: c, circle: true),
    ExampleKind.equationSteps: (c) => EquationStepsExample(context: c),
    ExampleKind.codeTrace: (c) => CodeTraceExample(context: c),
    ExampleKind.loopTrace: (c) =>
        CodeTraceExample(context: c, mode: TraceMode.loop),
    ExampleKind.variableState: (c) =>
        CodeTraceExample(context: c, mode: TraceMode.variable),
    ExampleKind.conditionFlow: (c) => const ConditionFlowExample(),
    ExampleKind.processFlow: (c) =>
        SourceSequenceExample(context: c, mode: SourceSequenceMode.process),
    ExampleKind.timeline: (c) =>
        SourceSequenceExample(context: c, mode: SourceSequenceMode.timeline),
    ExampleKind.labeledDiagram: (c) =>
        SourceSequenceExample(context: c, mode: SourceSequenceMode.diagram),
    ExampleKind.sentenceBuilder: (c) => SentenceBuilderExample(context: c),
    ExampleKind.conceptExplorer: (c) => ConceptExplorerExample(context: c),
  });
  static Widget build(ExampleKind kind, ExampleContext context) {
    final builder = canRender(kind, context) ? builders[kind] : null;
    return (builder ?? builders[ExampleKind.conceptExplorer]!)(context);
  }
}
