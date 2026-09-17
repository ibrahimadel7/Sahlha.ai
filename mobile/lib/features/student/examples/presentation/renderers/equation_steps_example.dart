import 'package:flutter/material.dart';

import '../../domain/example_context.dart';
import '../../domain/example_resolver.dart';
import '../common/example_shell.dart';

class EquationStepsExample extends StatefulWidget {
  const EquationStepsExample({super.key, required this.context});
  final ExampleContext context;
  @override
  State<EquationStepsExample> createState() => _EquationStepsExampleState();
}

class _EquationStepsExampleState extends State<EquationStepsExample> {
  int step = 0;
  @override
  Widget build(BuildContext context) {
    final seed = equationSeed(widget.context)!;
    final a = seed[0], b = seed[1], total = seed[2];
    final equations = [
      '$a x + $b = $total',
      '$a x = ${total - b}',
      'x = ${(total - b) ~/ a}',
    ];
    final reasons = [
      'Keep both sides equal.',
      'Subtract $b from both sides.',
      'Divide both sides by $a.',
    ];
    return ExampleShell(
      title: 'Solve one step at a time',
      guide: reasons[step],
      onReset: () => setState(() => step = 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Starting equation: ${equations.first}'),
          AnimatedSwitcher(
            duration: reducedExampleMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            child: ExampleResult(equations[step], key: ValueKey(step)),
          ),
          Text('Step ${step + 1} of 3'),
          const SizedBox(height: 12),
          ExampleNext(
            onPressed: step < 2 ? () => setState(() => step++) : null,
            label: step == 2 ? 'Equation solved' : 'Reveal the next operation',
          ),
        ],
      ),
    );
  }
}
