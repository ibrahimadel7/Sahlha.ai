import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/example_context.dart';
import '../../domain/loop_trace.dart';
import '../../domain/assignment_trace.dart';
import '../common/example_shell.dart';

enum TraceMode { code, loop, variable }

class CodeTraceExample extends StatefulWidget {
  const CodeTraceExample({
    super.key,
    required this.context,
    this.mode = TraceMode.code,
  });
  final ExampleContext context;
  final TraceMode mode;
  @override
  State<CodeTraceExample> createState() => _CodeTraceExampleState();
}

class _CodeTraceExampleState extends State<CodeTraceExample> {
  int step = 0, limit = 3;
  Timer? timer;
  bool get supplied => widget.context.items.length >= 2;
  String get source => widget.context.codeSource;
  AssignmentTrace get assignment => AssignmentTrace.fromCode(
    source.isEmpty ? 'x = 2\nx = x + 3\nprint(x)' : source,
  )!;
  LoopTrace? get trace => loop && !supplied
      ? LoopTrace.fromCode(
          source.isNotEmpty
              ? source
              : 'i = 0\nwhile i < $limit:\n  print(i)\n  i += 1',
        )
      : null;
  bool get loop => widget.mode == TraceMode.loop;
  int get last => supplied
      ? widget.context.items.length - 1
      : loop
      ? trace!.frames.length - 1
      : assignment.lines.length - 1;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedExampleMotion(context)) {
      timer?.cancel();
      timer = null;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void reset() {
    timer?.cancel();
    timer = null;
    setState(() => step = 0);
  }

  void next() {
    if (step < last) setState(() => step++);
    if (step == last) {
      timer?.cancel();
      timer = null;
    }
  }

  void run() {
    if (timer != null) {
      timer!.cancel();
      setState(() => timer = null);
      return;
    }
    setState(
      () => timer = Timer.periodic(
        const Duration(milliseconds: 900),
        (_) => next(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = supplied
        ? widget.context.items.map((i) => i.label).toList()
        : loop
        ? (source.isNotEmpty
              ? source.split('\n')
              : ['i = 0', 'while i < $limit:', '  print(i)', '  i += 1'])
        : assignment.lines;
    final line = supplied
        ? step
        : loop
        ? trace!.frames[step].line
        : step;
    final state = supplied
        ? widget.context.items[step].detail
        : loop
        ? '${trace!.variable} = ${trace!.frames[step].value}\n${trace!.frames[step].message}\nCondition: ${step == last ? 'false' : 'true'}\nIteration: ${trace!.frames[step].output.length}\nOutput: [${trace!.frames[step].output.join(', ')}]'
        : '${assignment.variable} = ${step == 0 ? assignment.initial : assignment.initial + assignment.delta}${step == 2 ? '\nOutput: ${assignment.initial + assignment.delta}' : ''}';
    return ExampleShell(
      title: loop
          ? 'Follow the loop'
          : widget.mode == TraceMode.variable
          ? 'Watch a variable change'
          : 'Trace the code',
      guide: supplied || source.isNotEmpty
          ? 'Follow the supplied trace. Read the state at each step.'
          : 'Illustrative walkthrough. Predict the state before the next line.',
      onReset: reset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loop && !supplied && source.isEmpty)
            ExampleCounter(
              label: 'Loop limit',
              value: limit,
              min: 1,
              max: 6,
              onChanged: (v) {
                reset();
                setState(() => limit = v);
              },
            ),
          for (var i = 0; i < lines.length; i++)
            Semantics(
              selected: i == line,
              label: 'Line ${i + 1}${i == line ? ', current' : ''}',
              child: AnimatedContainer(
                duration: reducedExampleMotion(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: i == line
                      ? const Color(0xFFD8EFEB)
                      : const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  lines[i],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ExampleResult(
            state.isEmpty
                ? 'Read this line, then predict the next change.'
                : state,
          ),
          Text('Step ${step + 1} of ${last + 1}'),
          ExampleNext(onPressed: step < last && timer == null ? next : null),
          if (loop && !reducedExampleMotion(context))
            TextButton(
              onPressed: step < last ? run : null,
              child: Text(
                timer == null ? 'Run walkthrough' : 'Pause walkthrough',
              ),
            ),
        ],
      ),
    );
  }
}
