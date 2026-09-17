import 'package:flutter/material.dart';

import '../common/example_shell.dart';

class ConditionFlowExample extends StatefulWidget {
  const ConditionFlowExample({super.key});
  @override
  State<ConditionFlowExample> createState() => _ConditionFlowExampleState();
}

class _ConditionFlowExampleState extends State<ConditionFlowExample> {
  int value = 5;
  @override
  Widget build(BuildContext context) => ExampleShell(
    title: 'Choose a branch',
    guide: 'Illustrative condition: is the value at least 5?',
    onReset: () => setState(() => value = 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleCounter(
          label: 'Value',
          value: value,
          max: 10,
          onChanged: (v) => setState(() => value = v),
        ),
        ExampleResult('$value >= 5 \u2192 ${value >= 5}'),
        for (final branch in [true, false])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              selected: (value >= 5) == branch,
              child: AnimatedContainer(
                duration: reducedExampleMotion(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (value >= 5) == branch
                      ? const Color(0xFFD8EFEB)
                      : const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (value >= 5) == branch
                        ? Colors.teal
                        : Colors.black26,
                  ),
                ),
                child: Text(
                  '${(value >= 5) == branch ? '\u2192 ' : ''}${branch ? 'TRUE: At least 5' : 'FALSE: Less than 5'}',
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
