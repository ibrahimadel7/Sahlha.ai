import 'package:flutter/material.dart';

import '../../domain/example_context.dart';
import '../common/example_shell.dart';

enum SourceSequenceMode { process, timeline, diagram }

class SourceSequenceExample extends StatefulWidget {
  const SourceSequenceExample({
    super.key,
    required this.context,
    required this.mode,
  });
  final ExampleContext context;
  final SourceSequenceMode mode;
  @override
  State<SourceSequenceExample> createState() => _SourceSequenceExampleState();
}

class _SourceSequenceExampleState extends State<SourceSequenceExample> {
  int selected = 0;
  bool reveal = false;
  @override
  Widget build(BuildContext context) {
    final stages = switch (widget.mode) {
      SourceSequenceMode.process => widget.context.processStages,
      SourceSequenceMode.timeline => widget.context.timelineEvents,
      SourceSequenceMode.diagram => widget.context.items,
    };
    final diagram = widget.mode == SourceSequenceMode.diagram;
    final timeline = widget.mode == SourceSequenceMode.timeline;
    return ExampleShell(
      title: diagram
          ? 'Explore the components'
          : timeline
          ? 'Explore the timeline'
          : 'Follow the process',
      guide: diagram
          ? 'Select a component to uncover its label.'
          : 'Follow the lesson sequence. Tap a stage to explore it.',
      onReset: () => setState(() {
        selected = 0;
        reveal = false;
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (diagram)
            const Text(
              'Schematic components \u2022 positions do not represent physical locations.',
            ),
          if (timeline) ...[
            for (var i = 0; i < stages.length; i++)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      children: [
                        Icon(
                          i == selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: Colors.teal,
                        ),
                        if (i < stages.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: Colors.teal.shade100,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() {
                          selected = i;
                          reveal = false;
                        }),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(stages[i].label),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ] else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < stages.length; i++) ...[
                  if (i > 0 && !diagram)
                    const Icon(Icons.arrow_forward, semanticLabel: 'Then'),
                  ChoiceChip(
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    label: Text(
                      diagram
                          ? 'Part ${i + 1}'
                          : stages[i].label
                                .split(RegExp(r'\s+'))
                                .take(6)
                                .join(' '),
                    ),
                    selected: selected == i,
                    onSelected: (_) => setState(() {
                      selected = i;
                      reveal = false;
                    }),
                  ),
                ],
              ],
            ),
          if (!diagram || reveal) ExampleResult(stages[selected].label),
          if (reveal && stages[selected].detail.isNotEmpty)
            Text(stages[selected].detail),
          if (!reveal)
            ExampleNext(
              onPressed: () => setState(() => reveal = true),
              label: diagram ? 'Reveal label' : 'Explore this stage',
            )
          else if (selected < stages.length - 1)
            ExampleNext(
              onPressed: () => setState(() {
                selected++;
                reveal = false;
              }),
              label:
                  'Next ${timeline
                      ? 'event'
                      : diagram
                      ? 'component'
                      : 'stage'}',
            ),
        ],
      ),
    );
  }
}
