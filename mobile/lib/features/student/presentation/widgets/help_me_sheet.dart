import 'package:flutter/material.dart';

class HelpMeSheet extends StatefulWidget {
  const HelpMeSheet({
    super.key,
    this.order = const [
      'simpler',
      'example',
      'read_aloud',
      'steps',
      'visual',
      'word',
    ],
  });
  final List<String> order;
  @override
  State<HelpMeSheet> createState() => _HelpMeSheetState();
}

class _HelpMeSheetState extends State<HelpMeSheet> {
  bool _more = false;
  List<(String, String, IconData)> get _items {
    final items = [
      ('simpler', 'Make it simpler', Icons.short_text_rounded),
      ('example', 'Show an example', Icons.auto_stories_outlined),
      ('read_aloud', 'Read aloud', Icons.volume_up_outlined),
      ('steps', 'Break into steps', Icons.format_list_numbered_rounded),
      ('visual', 'Show visually', Icons.image_outlined),
      ('word', 'Explain this word', Icons.spellcheck_rounded),
    ];
    int rank(String key) {
      final index = widget.order.indexOf(key);
      return index < 0 ? 99 : index;
    }

    return items..sort((a, b) => rank(a.$1).compareTo(rank(b.$1)));
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Let’s find your way in',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text('Choose the kind of help that feels right.'),
      const SizedBox(height: 16),
      for (final item in _items.take(_more ? _items.length : 3))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(item.$1),
            icon: Icon(item.$3),
            label: Text(item.$2),
          ),
        ),
      if (!_more)
        TextButton(
          onPressed: () => setState(() => _more = true),
          child: const Text('More ways to help'),
        ),
    ],
  );
}
