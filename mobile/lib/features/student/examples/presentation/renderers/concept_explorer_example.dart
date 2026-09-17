import 'package:flutter/material.dart';

import '../../domain/example_context.dart';
import '../common/example_shell.dart';

/// Grounded progressive disclosure even when subject or lesson metadata is absent.
class ConceptExplorerExample extends StatefulWidget {
  const ConceptExplorerExample({super.key, required this.context});
  final ExampleContext context;
  @override
  State<ConceptExplorerExample> createState() => _ConceptExplorerExampleState();
}

class _ConceptExplorerExampleState extends State<ConceptExplorerExample> {
  int step = 0;
  bool reveal = false;
  List<String> chunks(String text) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    return [
      for (var i = 0; i < words.length; i += 45)
        words.sublist(i, (i + 45).clamp(0, words.length)).join(' '),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.context;
    final core = [
      c.learningObjective,
      c.description,
      c.explanation,
    ].firstWhere((s) => s.isNotEmpty, orElse: () => c.title);
    final parts = <String>{
      ...c.examples.expand(chunks),
      ...c.steps.expand(chunks),
      ...chunks(core),
      if (c.explanation != core) ...chunks(c.explanation),
    }.toList();
    final index = step.clamp(0, parts.length - 1);
    return ExampleShell(
      title: 'Concept explorer',
      guide: 'One idea at a time. Predict, reveal, then explain it in your own words.',
      onReset: () => setState(() {
        step = 0;
        reveal = false;
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            index == 0
                ? 'CONCEPT'
                : 'HOW IT WORKS \u2022 ${index + 1} / ${parts.length}',
          ),
          ExampleResult(parts[index]),
          Text('Part ${index + 1} of ${parts.length}'),
          if (index > 0)
            TextButton(
              onPressed: () => setState(() {
                step--;
                reveal = false;
              }),
              child: const Text('Previous idea'),
            ),
          if (c.keyConcepts.isNotEmpty)
            ExpansionTile(
              title: const Text('Key connections'),
              children: [
                Wrap(
                  spacing: 8,
                  children: c.keyConcepts
                      .map(
                        (s) => Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(s),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Text(
            index < parts.length - 1
                ? 'What might come next? Make a prediction before revealing.'
                : 'Try it: explain this idea in your own words. Which detail supports your explanation?',
          ),
          if (reveal)
            ExampleResult(
              index < parts.length - 1 ? parts[index + 1] : 'Compare your explanation with the idea above. Find one connection you can describe.',
            ),
          if (!reveal)
            ExampleNext(
              onPressed: () => setState(() => reveal = true),
              label: index < parts.length - 1
                  ? 'Reveal next idea'
                  : 'Reflect on the idea',
            )
          else if (index < parts.length - 1)
            ExampleNext(
              onPressed: () => setState(() {
                step++;
                reveal = false;
              }),
              label: 'Continue exploring',
            ),
        ],
      ),
    );
  }
}
