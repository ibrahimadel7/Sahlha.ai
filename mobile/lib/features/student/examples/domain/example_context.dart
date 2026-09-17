import '../../domain/skill_models.dart';

String exampleText(Object? value) => value is String
    ? value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '').trim()
    : '';
Map<String, dynamic> exampleMap(Object? value) => value is Map
    ? {
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      }
    : {};
List<String> exampleStrings(Object? value) => value is List
    ? value.take(40).map(exampleText).where((s) => s.isNotEmpty).toList()
    : [];

class ExampleItem {
  const ExampleItem(this.label, this.detail);
  final String label;
  final String detail;
}

/// Frontend-only snapshot. No service, mastery or audio state belongs here.
class ExampleContext {
  ExampleContext({
    String subject = '',
    String courseName = '',
    String lessonTitle = '',
    String skillId = '',
    String skillName = '',
    String description = '',
    String learningObjective = '',
    List<String> keyConcepts = const [],
    String explanation = '',
    List<String> examples = const [],
    List<String> steps = const [],
    String difficulty = '',
    String visualType = '',
    Map<String, dynamic> visualSpec = const {},
    Map<String, dynamic> playgroundSpec = const {},
    String sourceType = '',
    Map<String, dynamic> rawMetadata = const {},
    this.skill,
    this.help,
  }) : subject = exampleText(subject),
       courseName = exampleText(courseName),
       lessonTitle = exampleText(lessonTitle),
       skillId = exampleText(skillId),
       skillName = exampleText(skillName),
       description = exampleText(description),
       learningObjective = exampleText(learningObjective),
       keyConcepts = List.unmodifiable(exampleStrings(keyConcepts)),
       explanation = exampleText(explanation),
       examples = List.unmodifiable(exampleStrings(examples)),
       steps = List.unmodifiable(exampleStrings(steps)),
       difficulty = exampleText(difficulty),
       visualType = exampleText(visualType).toLowerCase(),
       visualSpec = Map.unmodifiable(visualSpec),
       playgroundSpec = Map.unmodifiable(playgroundSpec),
       sourceType = exampleText(sourceType),
       rawMetadata = Map.unmodifiable(rawMetadata);

  factory ExampleContext.fromLesson(SkillBundle skill, SkillHelp help) {
    final raw = {...skill.exampleMetadata, ...help.exampleMetadata};
    final content = {
      ...exampleMap(skill.exampleMetadata['learning_content']),
      ...exampleMap(help.exampleMetadata['learning_content']),
    };
    final metadata = {...raw, ...content};
    return ExampleContext(
      skill: skill,
      help: help,
      skillId: skill.skillId,
      skillName: skill.name,
      subject: skill.subject,
      courseName: exampleText(raw['course_name']),
      lessonTitle: exampleText(raw['lesson_title']),
      description: skill.description,
      learningObjective: exampleText(raw['learning_objective']),
      keyConcepts: {...skill.keyConcepts, ...help.keyConcepts}.toList(),
      explanation: exampleText(content['core_idea']).isNotEmpty
          ? exampleText(content['core_idea'])
          : skill.explanation,
      examples: [
        help.body,
        exampleText(content['example']),
        ...exampleStrings(metadata['examples']),
      ],
      steps: help.steps.isNotEmpty
          ? help.steps
          : exampleStrings(content['steps']),
      difficulty: exampleText(raw['difficulty']),
      visualType: exampleText(metadata['visual_type']),
      visualSpec: exampleMap(metadata['visual_spec']),
      playgroundSpec: exampleMap(metadata['playground']),
      sourceType: exampleText(raw['source_type']),
      rawMetadata: raw,
    );
  }
  final String subject,
      courseName,
      lessonTitle,
      skillId,
      skillName,
      description,
      learningObjective,
      explanation,
      difficulty,
      visualType,
      sourceType;
  final List<String> keyConcepts, examples, steps;
  final Map<String, dynamic> visualSpec, playgroundSpec, rawMetadata;
  final SkillBundle? skill;
  final SkillHelp? help;
  String get topic =>
      [skillName, learningObjective, ...keyConcepts].join(' ').toLowerCase();
  String get supporting => [description, lessonTitle].join(' ').toLowerCase();
  String get codeSource {
    final source = exampleText(visualSpec['source_text']);
    if (source.isNotEmpty) return source;
    final text = [...examples, explanation].join('\n');
    return RegExp(r'```[^\n]*\n([\s\S]*?)```')
            .firstMatch(text)
            ?.group(1)
            ?.trim() ??
        '';
  }

  String get mathSource => [
    exampleText(visualSpec['source_text']),
    ...steps,
    ...examples,
    explanation,
    description,
  ].join(' ');
  String get corpus => [topic, supporting, ...examples, explanation].join(' ');
  String get title => skillName.isNotEmpty ? skillName : 'Explore this concept';
  List<ExampleItem> get items {
    final value = visualSpec['items'];
    if (value is! List) return const [];
    return value
        .take(40)
        .map((v) {
          final m = exampleMap(v);
          return ExampleItem(exampleText(m['label']), exampleText(m['detail']));
        })
        .where((v) => v.label.isNotEmpty)
        .toList();
  }

  List<ExampleItem> get stages =>
      items.isNotEmpty ? items : steps.map((s) => ExampleItem(s, '')).toList();
  List<ExampleItem> get processStages {
    if (stages.isNotEmpty) return stages;
    // Retain source order and wording; never manufacture a scientific stage.
    final source = explanation.isNotEmpty ? explanation : examples.join('\n');
    return source
        .split(RegExp(r'(?<=[.!?])\s+|\n+'))
        .map(exampleText)
        .where((s) => s.isNotEmpty)
        .take(12)
        .map((s) => ExampleItem(s, ''))
        .toList();
  }

  List<ExampleItem> get timelineEvents {
    if (stages.isNotEmpty) return stages;
    final source = explanation.isNotEmpty ? explanation : examples.join('\n');
    return source
        .split(RegExp(r'(?<=[.!?])\s+|\n+'))
        .map(exampleText)
        .where((s) => RegExp(r'\b\d{3,4}\b').hasMatch(s))
        .take(12)
        .map((s) => ExampleItem(s, ''))
        .toList();
  }

  String get sentence {
    final source = exampleText(visualSpec['source_text']);
    if (source.isNotEmpty) return source;
    return examples.isEmpty ? '' : examples.first;
  }
}
