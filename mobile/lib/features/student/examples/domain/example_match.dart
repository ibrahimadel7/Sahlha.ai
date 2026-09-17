import 'example_kind.dart';

class ExampleMatch {
  const ExampleMatch(
    this.kind,
    this.score,
    this.signals, {
    this.explicit = false,
  });
  final ExampleKind kind;
  final int score;
  final List<String> signals;
  final bool explicit;
  double get confidence => (score / 100).clamp(0, 1);
}
