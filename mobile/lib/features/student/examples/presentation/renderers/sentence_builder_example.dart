import 'package:flutter/material.dart';

import '../../domain/example_context.dart';
import '../common/example_shell.dart';

class SentenceBuilderExample extends StatefulWidget {
  const SentenceBuilderExample({super.key, required this.context});
  final ExampleContext context;
  @override
  State<SentenceBuilderExample> createState() => _SentenceBuilderExampleState();
}

class _SentenceBuilderExampleState extends State<SentenceBuilderExample> {
  final selected = <int>[];
  bool hint = false, reveal = false;
  @override
  Widget build(BuildContext context) {
    final words = widget.context.sentence.split(RegExp(r'\s+'));
    return ExampleShell(
      title: 'Build the sentence',
      guide: 'Tap the words in order. Compare with the lesson sentence when ready.',
      onReset: () => setState(() {
        selected.clear();
        hint = false;
        reveal = false;
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExampleResult(
            selected.isEmpty
                ? 'Your sentence will appear here.'
                : selected.map((i) => words[i]).join(' '),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in List.generate(words.length, (i) => i).reversed)
                OutlinedButton(
                  onPressed: selected.contains(i)
                      ? null
                      : () => setState(() => selected.add(i)),
                  child: Text(words[i]),
                ),
            ],
          ),
          Wrap(
            children: [
              TextButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => setState(() => selected.removeLast()),
                child: const Text('Undo'),
              ),
              TextButton(
                onPressed: () => setState(() => hint = true),
                child: const Text('Hint'),
              ),
            ],
          ),
          if (hint) Text('The lesson sentence starts with ${words.first}.'),
          if (reveal)
            ExampleResult('Lesson sentence: ${widget.context.sentence}')
          else
            ExampleNext(
              onPressed: () => setState(() => reveal = true),
              label: 'Reveal lesson sentence',
            ),
        ],
      ),
    );
  }
}
