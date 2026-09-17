/// A bounded native demonstration of assignment plus an optional print.
/// Reject the entire snippet unless it matches this exact supported shape.
class AssignmentTrace {
  const AssignmentTrace(
    this.variable,
    this.initial,
    this.delta,
    this.prints,
    this.lines,
  );
  final String variable;
  final int initial, delta;
  final bool prints;
  final List<String> lines;
  static AssignmentTrace? fromCode(String source) {
    final lines = source
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (lines.length < 2 || lines.length > 3) return null;
    final initial = RegExp(r'^(?:int\s+)?([a-zA-Z_]\w*)\s*=\s*(-?\d+)\s*;?$')
        .firstMatch(lines[0]);
    if (initial == null) return null;
    final variable = initial[1]!;
    final update = RegExp(
      '^$variable\\s*=\\s*$variable\\s*\\+\\s*(-?\\d+)\\s*;?\$',
    ).firstMatch(lines[1]);
    if (update == null) return null;
    if (lines.length == 3 &&
        !RegExp('^print\\($variable\\)\\s*;?\$').hasMatch(lines[2])) {
      return null;
    }
    final value = int.tryParse(initial[2]!);
    final delta = int.tryParse(update[1]!);
    if (value == null ||
        delta == null ||
        value.abs() > 1000 ||
        delta.abs() > 1000) {
      return null;
    }
    return AssignmentTrace(variable, value, delta, lines.length == 3, lines);
  }
}
