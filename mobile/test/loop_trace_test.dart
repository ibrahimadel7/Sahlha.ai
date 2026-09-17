import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/student/presentation/widgets/loop_trace.dart';

void main() {
  test('counter walkthrough follows source values, including a false exit', () {
    final trace = LoopTrace.fromCode(
      'count = 2\nwhile count < 5:\n    print(count)\n    count += 1',
    )!;
    expect(trace.variable, 'count');
    expect(trace.frames.last.output, [2, 3, 4]);
    expect(trace.frames.last.value, 5);
    expect(trace.frames.last.message, contains('false: exit'));
  });
  test('inclusive loops and initially false conditions are faithful', () {
    expect(
      LoopTrace.fromCode('i = 3\nwhile i <= 3:\n print(i)\n i = i + 1')!
          .frames
          .last
          .output,
      [3],
    );
    expect(
      LoopTrace.fromCode('i = 7\nwhile i < 2:\n print(i)\n i += 1')!
          .frames
          .last
          .output,
      isEmpty,
    );
  });
  test('unsupported statements and unbounded traces are never simulated', () {
    expect(
      LoopTrace.fromCode('i = 0\nwhile i < 99:\n print(i)\n i += 1'),
      isNull,
    );
    expect(
      LoopTrace.fromCode('i = 0\nwhile i < 3:\n erase(i)\n i += 1'),
      isNull,
    );
    expect(
      LoopTrace.fromCode('i = 0\nwhile i < 3:\n print(i)\n i -= 1'),
      isNull,
    );
  });
}
