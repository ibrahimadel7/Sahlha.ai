import 'package:flutter/material.dart';

import '../../domain/example_context.dart';
import '../../domain/example_resolver.dart';
import '../common/example_shell.dart';

/// Equal groups for source products too large for a unit-square array.
class MultiplicationGroupsExample extends StatefulWidget {
  const MultiplicationGroupsExample({super.key, required this.context});
  final ExampleContext context;

  @override
  State<MultiplicationGroupsExample> createState() =>
      _MultiplicationGroupsExampleState();
}

class _MultiplicationGroupsExampleState
    extends State<MultiplicationGroupsExample> {
  late int groups, each;
  int revealed = 0;

  void reset() {
    final pair = multiplicationPair(widget.context)!;
    groups = pair[0];
    each = pair[1];
    revealed = 0;
  }

  @override
  void initState() {
    super.initState();
    reset();
  }

  @override
  void didUpdateWidget(MultiplicationGroupsExample oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.context != widget.context) reset();
  }

  @override
  Widget build(BuildContext context) => ExampleShell(
    title: 'Explore equal groups',
    guide: 'Start with the lesson’s numbers. Add a group, predict the total, then change the numbers to explore.',
    onReset: () => setState(reset),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceAround,
          spacing: 16,
          runSpacing: 12,
          children: [
            ExampleCounter(
              label: 'Groups',
              value: groups,
              max: 1000,
              onChanged: (value) => setState(() {
                groups = value;
                revealed = 0;
              }),
            ),
            ExampleCounter(
              label: 'In each group',
              value: each,
              max: 1000,
              onChanged: (value) => setState(() {
                each = value;
                revealed = 0;
              }),
            ),
          ],
        ),
        ExampleResult('$groups × $each = ${groups * each}'),
        Text('$revealed of $groups groups • Total so far: ${revealed * each}'),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: groups == 0 ? 1 : revealed / groups),
        const SizedBox(height: 12),
        if (revealed > 0)
          ExampleResult(
            '${List.filled(revealed.clamp(0, 8), '$each').join(' + ')}${revealed > 8 ? ' + … ($revealed groups)' : ''} = ${revealed * each}',
          ),
        ExampleNext(
          label: 'Add one group',
          onPressed: revealed < groups
              ? () => setState(() => revealed++)
              : null,
        ),
        TextButton(
          onPressed: revealed < groups
              ? () => setState(() => revealed = groups)
              : null,
          child: const Text('Show all groups'),
        ),
        if (groups == 0 || each == 0)
          const Text(
            'Zero groups or zero in each group gives a total of zero.',
          ),
      ],
    ),
  );
}
