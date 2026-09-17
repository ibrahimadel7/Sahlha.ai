import 'package:flutter/material.dart';

import '../../../../core/widgets/sahlha_markdown.dart';

/// Renders backend educational text (skill/lesson explanations, question
/// text and explanations, help bodies) with markdown formatting applied.
/// ```fences still render as monospace code panels. Code is never executed.
class LessonContent extends StatelessWidget {
  const LessonContent({super.key, required this.source, this.question = false});
  final String source;
  final bool question;
  @override
  Widget build(BuildContext context) {
    final base =
        (question
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.bodyLarge)
            ?.copyWith(height: 1.6);
    final blocks = <Widget>[];
    final fences = RegExp(r'```[^\n]*\n([\s\S]*?)```').allMatches(source);
    var offset = 0;
    void prose(String value) {
      if (value.trim().isEmpty) return;
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SahlhaMarkdown(data: value, baseStyle: base),
        ),
      );
    }

    for (final fence in fences) {
      prose(source.substring(offset, fence.start));
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
    prose(source.substring(offset));
    if (blocks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }
}
