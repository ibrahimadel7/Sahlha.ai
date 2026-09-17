import 'package:flutter/material.dart';

/// Keeps whitespace and punctuation in educational code intact. Only the
/// surrounding markdown fence is removed; code is never executed here.
class LessonContent extends StatelessWidget {
  const LessonContent({super.key, required this.source, this.question = false});
  final String source;
  final bool question;
  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    final fences = RegExp(r'```[^\n]*\n([\s\S]*?)```').allMatches(source);
    var offset = 0;
    void text(String value) {
      if (value.trim().isEmpty) return;
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            value.trim(),
            style:
                (question
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.bodyLarge)
                    ?.copyWith(height: 1.6),
          ),
        ),
      );
    }

    for (final fence in fences) {
      text(source.substring(offset, fence.start));
      blocks.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3FC),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            fence.group(1)!.trimRight(),
            style: const TextStyle(
              fontFamily: 'monospace',
              color: Color(0xFF27447E),
              fontSize: 14,
              height: 1.65,
            ),
          ),
        ),
      );
      offset = fence.end;
    }
    text(source.substring(offset));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }
}
