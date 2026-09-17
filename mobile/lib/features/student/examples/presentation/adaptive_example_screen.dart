import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/skill_models.dart';
import '../application/example_selection_provider.dart';
import '../domain/example_context.dart';
import 'example_renderer_registry.dart';

/// Embedded in the existing lesson shell, which owns navigation and audio.
class AdaptiveExampleScreen extends ConsumerStatefulWidget {
  const AdaptiveExampleScreen({
    super.key,
    required this.skill,
    required this.example,
    this.audio,
  });
  final SkillBundle skill;
  final SkillHelp example;
  final Widget? audio;
  @override
  ConsumerState<AdaptiveExampleScreen> createState() =>
      _AdaptiveExampleScreenState();
}

class _AdaptiveExampleScreenState extends ConsumerState<AdaptiveExampleScreen> {
  late ExampleContext contextData;
  @override
  void initState() {
    super.initState();
    normalize();
  }

  void normalize() =>
      contextData = ExampleContext.fromLesson(widget.skill, widget.example);
  @override
  void didUpdateWidget(AdaptiveExampleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.skill != widget.skill ||
        oldWidget.example != widget.example) {
      normalize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(exampleSelectionProvider(contextData));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: ObjectKey(contextData),
          child: ExampleRendererRegistry.build(match.kind, contextData),
        ),
        if (widget.audio != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: widget.audio!,
          ),
        if (kDebugMode && const bool.fromEnvironment('EXAMPLE_DEBUG'))
          ExpansionTile(
            title: const Text('Example resolver (developer)'),
            children: [
              Text(
                '${match.kind.name} ? ${match.confidence.toStringAsFixed(2)}\n${match.signals.join(', ')}',
              ),
            ],
          ),
      ],
    );
  }
}

/// Compatibility entry point for callers embedding the former standalone view.
class StudentExampleView extends StatelessWidget {
  const StudentExampleView({
    super.key,
    required this.skill,
    required this.example,
  });
  final SkillBundle skill;
  final SkillHelp example;
  @override
  Widget build(BuildContext context) => ProviderScope(
    child: AdaptiveExampleScreen(skill: skill, example: example),
  );
}
