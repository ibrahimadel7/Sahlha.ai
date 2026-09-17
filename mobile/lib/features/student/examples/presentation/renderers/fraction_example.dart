import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/example_context.dart';
import '../common/example_shell.dart';

class FractionExample extends StatefulWidget {
  const FractionExample({
    super.key,
    required this.context,
    this.circle = false,
  });
  final ExampleContext context;
  final bool circle;
  @override
  State<FractionExample> createState() => _FractionExampleState();
}

class _FractionExampleState extends State<FractionExample> {
  int numerator = 3, denominator = 4;
  @override
  void initState() {
    super.initState();
    reset();
  }

  void reset() {
    final match = RegExp(r'(\d{1,2})\s*/\s*(\d{1,2})')
        .firstMatch(widget.context.mathSource);
    denominator = match == null ? 4 : int.parse(match[2]!).clamp(1, 12);
    numerator = match == null ? 3 : int.parse(match[1]!).clamp(0, denominator);
  }

  @override
  Widget build(BuildContext context) => ExampleShell(
    title: widget.circle ? 'Parts of a circle' : 'Parts of a whole',
    guide: 'Change the equal parts, then select how many to shade.',
    onReset: () => setState(reset),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          children: [
            ExampleCounter(
              label: 'Numerator',
              value: numerator,
              max: denominator,
              onChanged: (v) => setState(() => numerator = v),
            ),
            ExampleCounter(
              label: 'Denominator',
              value: denominator,
              min: 1,
              onChanged: (v) => setState(() {
                denominator = v;
                numerator = numerator.clamp(0, v);
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Semantics(
          label: '$numerator selected parts out of $denominator equal parts',
          child: ExcludeSemantics(
            child: widget.circle
                ? SizedBox(
                    height: 180,
                    child: CustomPaint(
                      painter: FractionPainter(
                        numerator,
                        denominator,
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  )
                : Row(
                    children: List.generate(
                      denominator,
                      (index) => Expanded(
                        child: AnimatedContainer(
                          duration: reducedExampleMotion(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          height: 72,
                          decoration: BoxDecoration(
                            color: index < numerator
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white,
                            border: Border.all(color: Colors.black54),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        ExampleResult('$numerator / $denominator'),
        Text('$numerator selected parts out of $denominator total parts.'),
        if (numerator > 0 && numerator.gcd(denominator) > 1)
          Text(
            'Same amount: ${numerator ~/ numerator.gcd(denominator)} / ${denominator ~/ numerator.gcd(denominator)}',
          ),
      ],
    ),
  );
}

class FractionPainter extends CustomPainter {
  const FractionPainter(this.numerator, this.denominator, this.color);
  final int numerator, denominator;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2 - 4;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
    for (var i = 0; i < denominator; i++) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * 2 * math.pi / denominator,
        2 * math.pi / denominator,
        true,
        Paint()..color = i < numerator ? color : Colors.white,
      );
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * 2 * math.pi / denominator,
        2 * math.pi / denominator,
        true,
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(FractionPainter old) =>
      numerator != old.numerator ||
      denominator != old.denominator ||
      color != old.color;
}
