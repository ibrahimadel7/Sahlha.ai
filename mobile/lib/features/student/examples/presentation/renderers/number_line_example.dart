import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/example_context.dart';
import '../common/example_shell.dart';

class NumberLineExample extends StatefulWidget {
  const NumberLineExample({
    super.key,
    required this.context,
    this.subtract = false,
  });
  final ExampleContext context;
  final bool subtract;
  @override
  State<NumberLineExample> createState() => _NumberLineExampleState();
}

class _NumberLineExampleState extends State<NumberLineExample> {
  late int start, jumps;
  int step = 0;
  @override
  void initState() {
    super.initState();
    reset();
  }

  void reset() {
    final source = widget.context.mathSource;
    final match = RegExp(
      widget.subtract
          ? r'(\d{1,2})\s*[-\u2212]\s*(\d{1,2})'
          : r'(\d{1,2})\s*\+\s*(\d{1,2})',
    ).firstMatch(source);
    start = match == null
        ? (widget.subtract ? 8 : 4)
        : int.parse(match[1]!).clamp(0, 12);
    jumps = match == null ? 3 : int.parse(match[2]!).clamp(0, 12);
    step = 0;
  }

  @override
  Widget build(BuildContext context) {
    final sign = widget.subtract ? -1 : 1;
    final position = start + step * sign;
    final end = start + jumps * sign;
    return ExampleShell(
      title: widget.subtract
          ? 'Subtract on a number line'
          : 'Add on a number line',
      guide: step == 0
          ? 'Start at $start. Predict where $jumps steps will land.'
          : 'Move ${widget.subtract ? 'backward' : 'forward'} one space at a time.',
      onReset: () => setState(reset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              ExampleCounter(
                label: 'Start',
                value: start,
                onChanged: (v) => setState(() {
                  start = v;
                  step = 0;
                }),
              ),
              ExampleCounter(
                label: 'Jumps',
                value: jumps,
                onChanged: (v) => setState(() {
                  jumps = v;
                  step = 0;
                }),
              ),
            ],
          ),
          Semantics(
            label:
                'Number line. Start $start. Current position $position. $step of $jumps jumps.',
            child: ExcludeSemantics(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: position.toDouble()),
                duration: reducedExampleMotion(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 280),
                builder: (context, value, child) => SizedBox(
                  height: 100,
                  child: CustomPaint(
                    painter: NumberLinePainter(
                      min: math.min(0, end),
                      max: math.max(12, end),
                      position: value,
                      start: start,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          ExampleResult('Position: $position \u2022 $step / $jumps jumps'),
          if (step == jumps)
            ExampleResult(
              '$start ${widget.subtract ? '\u2212' : '+'} $jumps = $end',
            ),
          ExampleNext(
            onPressed: step < jumps ? () => setState(() => step++) : null,
            label: step < jumps
                ? 'Move ${widget.subtract ? '\u2212'
                            '1' : '+1'}'
                : 'Walkthrough complete',
          ),
        ],
      ),
    );
  }
}

class NumberLinePainter extends CustomPainter {
  const NumberLinePainter({
    required this.min,
    required this.max,
    required this.position,
    required this.start,
    required this.color,
  });
  final int min, max, start;
  final double position;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    double x(num n) => 14 + (n - min) / (max - min) * (size.width - 28);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x(min), 50), Offset(x(max), 50), paint);
    for (var n = min; n <= max; n++) {
      canvas.drawLine(Offset(x(n), 45), Offset(x(n), 55), paint);
      // Keep labels legible on small phones; accessible state is above.
      if ((max - min) <= 14 || n.isEven || n == min || n == max) {
        final text = TextPainter(
          text: TextSpan(
            text: '$n',
            style: const TextStyle(color: Colors.black87, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(x(n) - text.width / 2, 65));
      }
    }
    canvas.drawCircle(Offset(x(start), 50), 4, paint);
    canvas.drawCircle(Offset(x(position), 32), 8, paint);
  }

  @override
  bool shouldRepaint(NumberLinePainter old) =>
      min != old.min ||
      max != old.max ||
      position != old.position ||
      start != old.start ||
      color != old.color;
}
