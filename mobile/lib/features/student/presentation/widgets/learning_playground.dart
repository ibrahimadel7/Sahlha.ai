import 'subject_visuals.dart';
import 'audio_companion.dart';
import 'playgrounds_joy.dart';

import 'package:flutter/material.dart';

import '../../domain/skill_models.dart';
import '../journey_presentation.dart';
import 'sahlha_avatar.dart';

// Re-export joyful playgrounds so lessons can use subject-aware renderers
// directly while `LearningPlayground` stays the auto-detecting entry point.
export 'playgrounds_joy.dart'
    show
        CodeTracePlayground,
        NumberLinePlayground,
        ProcessDiagramPlayground,
        InteractiveExampleCard;

/// Only source-backed content is displayed. Unsupported code is a reading
/// walkthrough, never presented as executed code or used to score an answer.
///
/// SEE → INTERACT: visual explanation + safe step-by-step simulation.
/// Audio (HEAR) is observed via [AudioCompanion], never re-downloaded here.
class LearningPlayground extends StatefulWidget {
  const LearningPlayground({
    super.key,
    required this.skill,
    this.subject = '',
    this.audioUrl,
  });
  final SkillBundle skill;
  final String subject;
  final String? audioUrl;
  @override
  State<LearningPlayground> createState() => _LearningPlaygroundState();
}

class _LearningPlaygroundState extends State<LearningPlayground> {
  int _step = 0;
  final List<int> _words = [];

  @override
  void didUpdateWidget(LearningPlayground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.skill != widget.skill) {
      _step = 0;
      _words.clear();
    }
  }

  void _advance(int count) => setState(() => _step = (_step + 1) % count);

  @override
  Widget build(BuildContext context) {
    final source = widget.skill.explanation.isEmpty
        ? widget.skill.description
        : widget.skill.explanation;
    final evidence =
        '${widget.subject} ${widget.skill.name} ${widget.skill.description}'
            .toLowerCase();
    final code = RegExp(r'```[^\n]*\n([\s\S]*?)```')
        .firstMatch(source)
        ?.group(1)
        ?.trim();
    final ideas = widget.skill.keyConcepts.isNotEmpty
        ? widget.skill.keyConcepts
        : lessonSections(source);
    var content = ideas.isEmpty ? [widget.skill.name] : ideas;
    final language = RegExp(
      r'language|english|arabic|grammar|sentence|لغة|عربي',
    ).hasMatch(evidence);
    final math = RegExp(r'math|number|equation|algebra|رياض|حساب')
        .hasMatch(evidence);
    final history = RegExp(r'history|histor|timeline|تاريخ').hasMatch(evidence);
    final geography = RegExp(r'geograph|location|latitude|جغراف')
        .hasMatch(evidence);
    if (history) {
      final events = source
          .split(RegExp(r'\n+'))
          .where((line) => RegExp(r'\b\d{3,4}\b').hasMatch(line))
          .toList();
      if (events.isNotEmpty) content = events;
    }
    if (math) {
      final equations = source
          .split(RegExp(r'\n+'))
          .where((line) => line.contains('='))
          .toList();
      if (equations.isNotEmpty) content = equations;
    }
    final programming =
        code != null ||
        RegExp(r'program|python|code|loop|برمج').hasMatch(evidence);
    final text = Theme.of(context).textTheme;

    // ---- Programming: joyful code trace (reference: Watch it run step by step)
    if (programming) {
      final traceCode = code ?? content.join('\n');
      return InteractiveExampleCard(
        title: 'Watch it run step by step',
        explanation: 'I\u2019ll show you what happens!',
        avatarMessage: code == null
            ? 'Let\u2019s walk through this idea one line at a time.'
            : null,
        child: CodeTracePlayground(code: traceCode),
      );
    }

    // ---- Language: sentence builder (source words only)
    if (language) {
      final sentence = source.split(RegExp(r'(?<=[.!?])\s+')).first;
      final words = sentence.split(RegExp(r'\s+')).take(24).toList();
      return InteractiveExampleCard(
        title: 'Build the sentence',
        explanation: 'Tap words to try an order.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(sentence, style: text.bodyLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = words.length - 1; i >= 0; i--)
                  FilterChip(
                    label: Text(words[i]),
                    selected: _words.contains(i),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _words.add(i);
                      } else {
                        _words.remove(i);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _words.isEmpty
                    ? 'Your sentence will appear here.'
                    : _words.map((i) => words[i]).join(' '),
                style: text.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () => setState(_words.clear),
              child: const Text('Try another arrangement'),
            ),
          ],
        ),
      );
    }

    // ---- Math / Geography / History / Science
    return InteractiveExampleCard(
      title: history
          ? 'Explore the timeline'
          : geography
          ? 'Explore locations'
          : math
          ? 'Explore the steps'
          : 'Explore the idea',
      explanation: history
          ? 'Tap an event to see more.'
          : 'One small piece at a time.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (math) ...[
            NumberLinePlayground(source: source),
            CoordinatePlot(source: source),
          ],
          if (geography) CoordinatePlot(source: source, geographic: true),
          if (history)
            LessonTimeline(
              events: content,
              selected: _step % content.length,
              onSelect: (i) => setState(() => _step = i),
            )
          else if (!math && !geography)
            ProcessDiagramPlayground(
              title: studentTitle(widget.skill.name),
              steps: content.map((e) => cleanStudentText(e)).toList(),
            ),
          if (math || geography)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < content.length; i++)
                    ChoiceChip(
                      selected: (_step % content.length) == i,
                      label: Text('${i + 1}'),
                      onSelected: (_) => setState(() => _step = i),
                    ),
                ],
              ),
            ),
          if (!history && (math || geography) && content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  cleanStudentText(content[_step % content.length]),
                  style: text.bodyLarge?.copyWith(height: 1.6),
                ),
              ),
            ),
          if (!history && !math && !geography && content.length > 1)
            const SizedBox.shrink(),
          if (history && content.length > 1)
            TextButton.icon(
              onPressed: () => _advance(content.length),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Next event'),
            ),
          // Companion / audio row: avatar observes existing audio, never
          // starts new requests. Keeps SEE→HEAR→INTERACT together.
          const SizedBox(height: 8),
          Row(
            children: [
              if (widget.audioUrl != null)
                AudioCompanion(url: widget.audioUrl!, size: 44)
              else
                const SahlhaAvatar(
                  size: 44,
                  state: SahlhaAvatarState.encouraging,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Take it one step at a time.',
                  style: text.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
