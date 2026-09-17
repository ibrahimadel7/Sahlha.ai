import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/sahlha_colors.dart';
import 'loop_trace.dart';
import 'sahlha_avatar.dart';

bool _reduced(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    MediaQuery.accessibleNavigationOf(context);

/// Joyful wrapper: avatar bubble + concept card + step controls.
/// Never executes arbitrary code — only safe predefined visual simulations.
class InteractiveExampleCard extends StatelessWidget {
  const InteractiveExampleCard({
    super.key,
    required this.title,
    required this.explanation,
    required this.child,
    this.avatarMessage,
  });
  final String title;
  final String explanation;
  final Widget child;
  final String? avatarMessage;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6E0), Color(0xFFF8F4E9)],
        ),
        border: Border.all(color: SahlhaColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (explanation.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        explanation,
                        style: text.bodySmall?.copyWith(
                          color: SahlhaColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SahlhaAvatar(
                size: 56,
                state: SahlhaAvatarState.encouraging,
              ),
            ],
          ),
          if (avatarMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: SahlhaColors.borderSubtle),
              ),
              child: Text(
                avatarMessage!,
                style: text.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Programming: code trace with line highlight, variable state,
/// condition result, output panel, step progression.
class CodeTracePlayground extends StatefulWidget {
  const CodeTracePlayground({super.key, required this.code});
  final String code;
  @override
  State<CodeTracePlayground> createState() => _CodeTracePlaygroundState();
}

class _CodeTracePlaygroundState extends State<CodeTracePlayground> {
  int _step = 0;
  Timer? _timer;
  bool _running = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _stop() {
    _timer?.cancel();
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final trace = LoopTrace.fromCode(widget.code.trim());
    final lines = widget.code.trim().split('\n');
    // Fallback: plain reading walkthrough when the code shape is unknown.
    if (trace == null) {
      final count = lines.length;
      final idx = _step % count;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CodeCard(lines: lines, highlight: idx),
          const SizedBox(height: 12),
          Text(
            'Step ${_step + 1} of $count',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton.icon(
            onPressed: () => setState(() => _step = (_step + 1) % count),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Run walkthrough'),
          ),
        ],
      );
    }
    final frames = trace.frames;
    final frame = frames[_step % frames.length];
    final text = Theme.of(context).textTheme;

    // Condition checklist derived from the current message.
    final isCheck =
        frame.message.contains('is true') || frame.message.contains('is false');
    final isTrue = frame.message.contains('true');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CodeCard(lines: lines, highlight: frame.line),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: SahlhaColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: SahlhaColors.joyTeal,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${trace.variable} = ${frame.value}',
                            style: text.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _CheckRow(
                      done: isCheck,
                      label: 'Check ${trace.variable} < bound',
                      result: isCheck
                          ? (isTrue ? 'True: repeat' : 'False: exit')
                          : null,
                    ),
                    _CheckRow(
                      done: frame.output.isNotEmpty,
                      label: 'Output so far',
                      result: frame.output.isEmpty
                          ? null
                          : frame.output.join(' '),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8FBF5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: SahlhaColors.joyTeal.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Output:',
                style: text.labelLarge?.copyWith(
                  color: SahlhaColors.joyTealDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                frame.output.isEmpty ? '—' : frame.output.join(' '),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: SahlhaColors.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            frame.message,
            textAlign: TextAlign.center,
            style: text.bodyMedium,
          ),
        ),
        Text(
          'Step ${_step + 1} of ${frames.length}',
          textAlign: TextAlign.center,
          style: text.bodySmall,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _step == 0
                    ? null
                    : () => setState(() => _step = (_step - 1)),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () {
                  if (_running) {
                    _stop();
                    return;
                  }
                  if (_reduced(context)) {
                    setState(() => _step = (_step + 1) % frames.length);
                    return;
                  }
                  setState(() {
                    if (_step >= frames.length - 1) _step = 0;
                    _running = true;
                  });
                  _timer = Timer.periodic(const Duration(milliseconds: 1400), (
                    timer,
                  ) {
                    if (!mounted) {
                      timer.cancel();
                      return;
                    }
                    if (_step >= frames.length - 1) {
                      timer.cancel();
                      setState(() => _running = false);
                    } else {
                      setState(() => _step++);
                    }
                  });
                },
                icon: Icon(
                  _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(
                  _running
                      ? 'Pause'
                      : _step == 0
                      ? 'Run'
                      : 'Next step',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.lines, required this.highlight});
  final List<String> lines;
  final int highlight;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF203B50),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.circle, size: 8, color: Color(0xFF7BD4C6)),
              SizedBox(width: 5),
              Icon(Icons.circle, size: 8, color: Color(0xFFFFDB80)),
              SizedBox(width: 5),
              Icon(Icons.circle, size: 8, color: Color(0xFF7BD4C6)),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < lines.length; i++)
            if ((i - highlight).abs() <= 3)
              AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                decoration: BoxDecoration(
                  color: i == highlight
                      ? const Color(0xFF365B70)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  lines[i].isEmpty ? ' ' : lines[i],
                  style: TextStyle(
                    fontFamily: 'monospace',
                    height: 1.6,
                    fontWeight: i == highlight
                        ? FontWeight.w800
                        : FontWeight.w400,
                    color: i == highlight
                        ? const Color(0xFFFFE28D)
                        : Colors.white,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.done, required this.label, this.result});
  final bool done;
  final String label;
  final String? result;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: done ? SahlhaColors.success : SahlhaColors.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (result != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: SahlhaColors.successSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                result!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: SahlhaColors.success,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Math: number line + equation steps from lesson numbers.
class NumberLinePlayground extends StatefulWidget {
  const NumberLinePlayground({super.key, required this.source});
  final String source;
  @override
  State<NumberLinePlayground> createState() => _NumberLinePlaygroundState();
}

class _NumberLinePlaygroundState extends State<NumberLinePlayground> {
  double? _value;
  @override
  Widget build(BuildContext context) {
    final values =
        RegExp(r'(?<!\w)-?\d+(?:\.\d+)?')
            .allMatches(widget.source)
            .map((m) => double.tryParse(m.group(0)!))
            .whereType<double>()
            .where((v) => v.isFinite)
            .toSet()
            .toList()
          ..sort();
    if (values.length < 2) return const SizedBox.shrink();
    final lo = values.first, hi = values.last;
    final cur = (_value ?? lo).clamp(lo, hi);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SahlhaColors.borderSubtle),
          ),
          child: Column(
            children: [
              Text(
                'Number line: ${cur.toStringAsFixed(1)}',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Slider(
                min: lo,
                max: hi,
                value: cur,
                onChanged: (v) => setState(() => _value = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('$lo'), Text('$hi')],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Science / process: reveal steps one at a time (source-backed only).
class ProcessDiagramPlayground extends StatefulWidget {
  const ProcessDiagramPlayground({
    super.key,
    required this.title,
    required this.steps,
  });
  final String title;
  final List<String> steps;
  @override
  State<ProcessDiagramPlayground> createState() =>
      _ProcessDiagramPlaygroundState();
}

class _ProcessDiagramPlaygroundState extends State<ProcessDiagramPlayground> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    final idx = _index % widget.steps.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.science_outlined,
              size: 28,
              color: Color(0xFF4F8542),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.title,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < widget.steps.length; i++)
              ChoiceChip(
                selected: idx == i,
                label: Text(
                  widget.steps[i],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onSelected: (_) => setState(() => _index = i),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SahlhaColors.borderSubtle),
          ),
          child: Semantics(
            liveRegion: true,
            child: Text(
              widget.steps[idx],
              style: text.bodyLarge?.copyWith(height: 1.6),
            ),
          ),
        ),
        if (widget.steps.length > 1)
          TextButton.icon(
            onPressed: () =>
                setState(() => _index = (_index + 1) % widget.steps.length),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Reveal next step'),
          ),
      ],
    );
  }
}
