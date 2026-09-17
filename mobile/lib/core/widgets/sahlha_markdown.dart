import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Renders backend educational text with its markdown formatting applied:
/// `**bold**`, `*italic*`, lists, headings and `code` show styled instead
/// of leaking raw markers. Code is never executed.
class SahlhaMarkdown extends StatelessWidget {
  const SahlhaMarkdown({super.key, required this.data, this.baseStyle});
  final String data;
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base =
        baseStyle ?? theme.textTheme.bodyLarge?.copyWith(height: 1.6);
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: base,
      strong: base?.copyWith(fontWeight: FontWeight.w800),
      em: base?.copyWith(fontStyle: FontStyle.italic),
      h1: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      h2: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      h3: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      listBullet: base,
      code: const TextStyle(
        fontFamily: 'monospace',
        color: Color(0xFF27447E),
        fontSize: 14,
        height: 1.65,
      ),
    );
    if (data.trim().isEmpty) return const SizedBox.shrink();
    return MarkdownBody(data: data.trim(), styleSheet: sheet);
  }
}
