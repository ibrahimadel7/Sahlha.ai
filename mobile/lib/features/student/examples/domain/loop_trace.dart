/// Bounded visualization of a simple counter loop from lesson code. This is
/// deliberately not an evaluator: unknown statements reject the whole trace.
/// Assessment answers always go to the backend.
class LoopFrame {
  const LoopFrame(this.line, this.value, this.message, this.output);
  final int line, value;
  final String message;
  final List<int> output;
}

class LoopTrace {
  const LoopTrace(this.variable, this.frames);
  final String variable;
  final List<LoopFrame> frames;

  static LoopTrace? fromCode(String code) {
    final lines = code.split('\n');
    final nonempty = <(int, String)>[
      for (var i = 0; i < lines.length; i++)
        if (lines[i].trim().isNotEmpty && lines[i].trim() != '}')
          (i, lines[i].trim()),
    ];
    if (nonempty.length != 4) return null;
    final initial = RegExp(r'^(?:int\s+)?([A-Za-z_]\w*)\s*=\s*(-?\d+)\s*;?$')
        .firstMatch(nonempty[0].$2);
    if (initial == null) return null;
    final variable = initial.group(1)!;
    final condition = RegExp(
      '^while\\s*\\(?\\s*$variable\\s*(<=|<)\\s*(-?\\d+)\\s*\\)?\\s*[:{]?\$',
    ).firstMatch(nonempty[1].$2);
    final print = RegExp('^(?:print|console.log)\\($variable\\)\\s*;?\$')
        .hasMatch(nonempty[2].$2);
    final increment = RegExp(
      '^$variable\\s*(?:\\+\\+|\\+=\\s*1|=\\s*$variable\\s*\\+\\s*1)\\s*;?\$',
    ).hasMatch(nonempty[3].$2);
    if (condition == null || !print || !increment) return null;
    final start = int.tryParse(initial.group(2)!);
    final bound = int.tryParse(condition.group(2)!);
    if (start == null ||
        bound == null ||
        bound - start > 12 ||
        start.abs() > 1000000 ||
        bound.abs() > 1000000) {
      return null;
    }
    var value = start;
    final inclusive = condition.group(1) == '<=';
    final output = <int>[];
    final frames = <LoopFrame>[
      LoopFrame(nonempty[0].$1, value, '$variable starts at $value.', []),
    ];
    while (true) {
      final test = inclusive ? value <= bound : value < bound;
      frames.add(
        LoopFrame(
          nonempty[1].$1,
          value,
          '$value ${condition.group(1)} $bound is ${test ? "true: repeat" : "false: exit"}.',
          List.of(output),
        ),
      );
      if (!test) break;
      output.add(value);
      frames.add(
        LoopFrame(
          nonempty[2].$1,
          value,
          'Show $value in the output.',
          List.of(output),
        ),
      );
      value++;
      frames.add(
        LoopFrame(
          nonempty[3].$1,
          value,
          '$variable increases to $value.',
          List.of(output),
        ),
      );
    }
    return LoopTrace(variable, frames);
  }
}
