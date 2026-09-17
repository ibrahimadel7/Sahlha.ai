import 'assignment_trace.dart';
import 'loop_trace.dart';
import 'example_context.dart';
import 'example_kind.dart';
import 'example_match.dart';
import 'example_renderer.dart';

const _math =
    r'math|arithmetic|algebra|\u0631\u064a\u0627\u0636|\u062d\u0633\u0627\u0628';
const _code = r'programming|computer|coding|informatics';
const _science = r'science|biology|chemistry|physics';
const renderers = <ExampleRenderer>[
  ExampleRenderer(
    ExampleKind.multiplicationGroups,
    _math,
    r'\b(multiplication|multiply|repeated addition|times tables?)\b',
    aliases: ['multiplication_groups'],
  ),
  ExampleRenderer(
    ExampleKind.multiplicationAreaModel,
    _math,
    r'\b(area models?|multiplication|multiply|repeated addition|times tables?)\b',
    aliases: ['area_model', 'multiplication_area_model'],
  ),
  ExampleRenderer(
    ExampleKind.additionNumberLine,
    _math,
    r'\b(addition|adding|add|plus|sum)\b',
    aliases: ['addition_number_line'],
  ),
  ExampleRenderer(
    ExampleKind.subtractionNumberLine,
    _math,
    r'\b(subtraction|subtracting|subtract|minus)\b',
    aliases: ['subtraction_number_line'],
  ),
  ExampleRenderer(
    ExampleKind.fractionBars,
    _math,
    r'\bfractions?\b',
    aliases: ['fraction_bars'],
  ),
  ExampleRenderer(
    ExampleKind.fractionCircle,
    _math,
    r'\b(pie fractions?|fraction circles?|circle fractions?)\b',
    aliases: ['fraction_circle'],
  ),
  ExampleRenderer(
    ExampleKind.equationSteps,
    _math,
    r'\b(linear equations?|solving equations?|equation steps|algebra)\b',
    aliases: ['equation_steps'],
  ),
  ExampleRenderer(
    ExampleKind.codeTrace,
    _code,
    r'\b(code trac(e|ing)|program trac(e|ing))\b',
    aliases: ['code_trace'],
  ),
  ExampleRenderer(
    ExampleKind.loopTrace,
    _code,
    r'\b(while loops?|for loops?|loops?|iteration)\b',
    aliases: ['loop_flow', 'loop_trace'],
  ),
  ExampleRenderer(
    ExampleKind.conditionFlow,
    _code,
    r'\b(if\s*[/ /]?\s*else|conditions?|boolean|conditional)\b',
    aliases: ['condition_flow'],
  ),
  ExampleRenderer(
    ExampleKind.variableState,
    _code,
    r'\b(variable assignment|variables?|assignment)\b',
    aliases: ['variable_state'],
  ),
  ExampleRenderer(
    ExampleKind.processFlow,
    _science,
    r'\b(photosynthesis|water cycle|digestion|process stages|cellular respiration)\b',
    aliases: ['process_sequence', 'process_flow'],
  ),
  ExampleRenderer(
    ExampleKind.labeledDiagram,
    _science,
    r'\b(anatomy|cell components|labeled diagram|parts of)\b',
    aliases: ['labeled_diagram'],
  ),
  ExampleRenderer(
    ExampleKind.timeline,
    r'history|social studies',
    r'\b(timeline|chronology|chronological|world war)\b',
    aliases: ['timeline'],
  ),
  ExampleRenderer(
    ExampleKind.sentenceBuilder,
    r'language|english|grammar|arabic',
    r'\b(sentence (builder|structure|word order)|word order)\b',
    aliases: ['sentence_builder', 'word_order'],
  ),
];

class ExampleResolver {
  const ExampleResolver();
  static const confidenceThreshold = 65;
  ExampleMatch resolve(ExampleContext context) {
    var explicit = context.visualType;
    if (explicit.isEmpty || explicit == 'none') {
      explicit = exampleText(context.playgroundSpec['type']);
    }
    if (explicit == 'number_line') {
      final sub = RegExp(r'\bsubtract|\bminus').hasMatch(context.topic);
      final add = RegExp(r'\badd|\bplus|\bsum').hasMatch(context.topic);
      explicit = sub != add
          ? (sub ? 'subtraction_number_line' : 'addition_number_line')
          : '';
    }
    for (final renderer in renderers) {
      if ((renderer.aliases.contains(explicit) ||
              renderer.kind.name.toLowerCase() == explicit) &&
          _compatible(renderer, context) &&
          canRender(renderer.kind, context)) {
        return ExampleMatch(renderer.kind, 100, [
          'supported metadata: $explicit',
        ], explicit: true);
      }
    }
    final matches =
        renderers
            .where((r) => _compatible(r, context) && canRender(r.kind, context))
            .map((r) => r.supports(context))
            .where((m) => m.score >= confidenceThreshold)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    // A circle is a specifically requested fraction representation.
    final primary = context.skillName.toLowerCase();
    if (RegExp(r'\b(multiplication|multiply|repeated addition)\b')
            .hasMatch(primary) &&
        !RegExp(r'\b(addition|adding|add|plus|sum)\b')
            .hasMatch(primary.replaceAll('repeated addition', ''))) {
      matches.removeWhere((m) => m.kind == ExampleKind.additionNumberLine);
    }
    if (matches.any((m) => m.kind == ExampleKind.fractionCircle)) {
      matches.removeWhere((m) => m.kind == ExampleKind.fractionBars);
    }
    if (matches.isEmpty) return _fallback('insufficient grounded evidence');
    if (matches.length > 1 && matches[0].score - matches[1].score < 15) {
      return _fallback('ambiguous topic');
    }
    return matches.first;
  }

  ExampleMatch _fallback(String reason) =>
      ExampleMatch(ExampleKind.conceptExplorer, 0, [reason]);

  bool _compatible(ExampleRenderer renderer, ExampleContext c) {
    final subject = '${c.subject} ${c.courseName}'.toLowerCase();
    final known = [
      _math,
      _code,
      _science,
      r'history|social studies',
      r'language|english|grammar|arabic',
      r'geography',
    ];
    if (known.any((p) => RegExp(p).hasMatch(subject)) &&
        !RegExp(renderer.domain).hasMatch(subject)) {
      return false;
    }
    // These experiences teach elementary operations, not unrelated advanced uses.
    if (RegExp(
      r'\b(matrix|matrices|complex numbers|polynomial|quadratic|fraction addition|adding fractions|fraction multiplication|multiplying fractions|nested loops|recursive|vectors?|matrices|calculus|geometric series|feedback loops|climate conditions)\b',
    ).hasMatch(c.topic)) {
      return false;
    }
    return true;
  }
}

bool canRender(ExampleKind kind, ExampleContext c) {
  switch (kind) {
    case ExampleKind.multiplicationGroups:
      return !safeNumericExample(c, r'[xX*\u00d7]', 1, 10) &&
          safeNumericExample(c, r'[xX*\u00d7]', 0, 1000) &&
          multiplicationPair(c) != null;
    case ExampleKind.multiplicationAreaModel:
      return safeNumericExample(c, r'[xX*\u00d7]', 1, 10);
    case ExampleKind.additionNumberLine:
      return safeNumericExample(c, r'\+', 0, 12);
    case ExampleKind.subtractionNumberLine:
      return safeNumericExample(c, r'[-\u2212]', 0, 12);
    case ExampleKind.fractionBars:
    case ExampleKind.fractionCircle:
      return safeNumericExample(c, '/', 0, 12, fraction: true);
    case ExampleKind.loopTrace:
      final source = c.codeSource;
      return c.items.length >= 2 ||
          source.isEmpty ||
          LoopTrace.fromCode(source) != null;
    case ExampleKind.codeTrace:
    case ExampleKind.variableState:
      return c.items.length >= 2 ||
          c.codeSource.isEmpty ||
          AssignmentTrace.fromCode(c.codeSource) != null;
    case ExampleKind.processFlow:
      return c.processStages.length >= 2;
    case ExampleKind.timeline:
      return c.timelineEvents.length >= 2;
    case ExampleKind.labeledDiagram:
      return c.items.length >= 2;
    case ExampleKind.sentenceBuilder:
      final words = c.sentence.split(RegExp(r'\s+'));
      return words.length >= 2 &&
          words.length <= 18 &&
          c.sentence.length <= 180;
    case ExampleKind.equationSteps:
      return equationSeed(c) != null;
    default:
      return true;
  }
}

List<int>? multiplicationPair(ExampleContext context) {
  final match = RegExp(r'(?<![\w.\-])(\d+)\s*[xX*\u00d7]\s*(\d+)(?![\d.])')
      .firstMatch(context.mathSource);
  return match == null ? null : [int.parse(match[1]!), int.parse(match[2]!)];
}

/// Only the native ax + b = c demonstration is solved locally.
/// Unrecognized lesson equations fall back instead of being silently replaced.
List<int>? equationSeed(ExampleContext c) {
  final source =
      '${exampleText(c.visualSpec['source_text'])} ${c.examples.join(' ')} ${c.explanation}';
  final m = RegExp(
    r'(?<![\w.\-])([1-9])x\s*\+\s*(\d{1,2})\s*=\s*(\d{1,2})(?![\d.])',
  ).firstMatch(source);
  if (m == null) return null;
  final a = int.parse(m[1]!);
  final b = int.parse(m[2]!);
  final total = int.parse(m[3]!);
  if (total < b || (total - b) % a != 0) return null;
  return [a, b, total];
}

/// Reject unsupported source values instead of clamping them into a different fact.
/// Native defaults are used only when there is no arithmetic example to replace.
bool safeNumericExample(
  ExampleContext context,
  String operator,
  int min,
  int max, {
  bool fraction = false,
}) {
  final expression = RegExp(
    '(-?\\d+(?:\\.\\d+)?)\\s*$operator\\s*(-?\\d+(?:\\.\\d+)?)',
  );
  for (final match in expression.allMatches(context.mathSource)) {
    final a = int.tryParse(match[1]!);
    final b = int.tryParse(match[2]!);
    if (a == null || b == null || a < min || b < min || a > max || b > max) {
      return false;
    }
    if (fraction && (b == 0 || a > b)) return false;
  }
  return true;
}
