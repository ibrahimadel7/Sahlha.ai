import 'example_context.dart';
import 'example_kind.dart';
import 'example_match.dart';

/// Curated capabilities; layout and arbitrary executable metadata never enter domain resolution.
class ExampleRenderer {
  const ExampleRenderer(
    this.kind,
    this.domain,
    this.pattern, {
    this.aliases = const [],
  });
  final ExampleKind kind;
  final String domain, pattern;
  final List<String> aliases;
  ExampleMatch supports(ExampleContext context) {
    final signals = <String>[];
    var score = 0;
    final expression = RegExp(pattern, caseSensitive: false);
    if (expression.hasMatch(context.skillName)) {
      score += 120;
      signals.add('skill title');
    } else if (expression.hasMatch(context.topic)) {
      score += 65;
      signals.add('topic: ${expression.firstMatch(context.topic)![0]}');
    }
    if (expression.hasMatch(context.supporting)) {
      score += 25;
      signals.add('description / lesson');
    }
    if (domain.isNotEmpty &&
        RegExp(
          domain,
          caseSensitive: false,
        ).hasMatch('${context.subject} ${context.courseName}')) {
      score += 20;
      signals.add('subject');
    }
    return ExampleMatch(kind, score, signals);
  }
}
