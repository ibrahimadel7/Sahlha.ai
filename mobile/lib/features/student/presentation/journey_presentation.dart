import '../domain/skill_models.dart';

/// Display-only cleanup. Identifiers and source text in API models stay intact.
String cleanStudentText(String text) {
  return text
      .replaceAll(RegExp(r'\b[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}\b'), '')
      .replaceAll(RegExp(r'(?<![A-Za-z0-9])[0-9a-fA-F]{8,}(?![A-Za-z0-9])'), '')
      .replaceAll(RegExp(r'\(\s*\)|\[\s*\]'), '')
      .replaceAll(RegExp(r'_{2,}'), ' ')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .trim();
}

String studentTitle(
  String source, {
  String context = '',
  String fallback = 'Learning step',
}) {
  final title = cleanStudentText(source)
      .replaceAll(
        RegExp(r'\.(pdf|docx?|pptx?|txt|md)\b', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'[_]+'), ' ')
      .replaceAll(RegExp(r'^\s*#+\s*|^\s*\d+[.)]\s*'), '')
      .trim();
  if (title.isEmpty || !RegExp(r'[\p{L}]', unicode: true).hasMatch(title)) {
    return fallback;
  }
  return title
      .split(' ')
      .map(
        (word) =>
            word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

enum JourneyState { completed, current, available, locked }

class JourneyStep {
  const JourneyStep({
    required this.skill,
    required this.materialId,
    required this.title,
    required this.state,
    required this.index,
  });
  final PathSkill skill;
  final String materialId;
  final String title;
  final JourneyState state;
  final int index;
  bool get canOpen => state != JourneyState.locked;
  bool get learned => skill.attempted > 0 || skill.state == 'mastered';
}

class JourneyUnit {
  const JourneyUnit({
    required this.source,
    required this.title,
    required this.number,
    required this.steps,
  });
  final PathUnit source;
  final String title;
  final int number;
  final List<JourneyStep> steps;
  int get mastered => steps.where((s) => s.skill.state == 'mastered').length;
  JourneyStep? get current =>
      steps.where((s) => s.state == JourneyState.current).firstOrNull;
  bool get masteryReady =>
      steps.isNotEmpty &&
      mastered == steps.length &&
      steps.every((s) => s.skill.exerciseReady);

  /// Existing APIs support one skill or an entire material, not arbitrary groups.
  /// Checkpoints revisit one ready skill after a group has actual attempts.
  JourneyStep? checkpointAfter(int end) {
    final group = steps.sublist((end - 3).clamp(0, steps.length), end);
    if (group.isEmpty || !group.every((s) => s.learned)) return null;
    final ready = group.where((s) => s.skill.exerciseReady);
    return ready.where((s) => s.skill.state != 'mastered').firstOrNull ??
        ready.lastOrNull;
  }
}

class LearningJourney {
  const LearningJourney(this.units);
  final List<JourneyUnit> units;
  JourneyUnit? get activeUnit =>
      units.where((u) => u.current != null).firstOrNull ??
      units.where((u) => u.mastered < u.steps.length).firstOrNull ??
      units.firstOrNull;
  int get total => units.fold(0, (sum, u) => sum + u.steps.length);
  int get mastered => units.fold(0, (sum, u) => sum + u.mastered);

  factory LearningJourney.fromJson(
    Map<String, dynamic> data, {
    String subject = '',
  }) {
    final sources = (data['units'] as List? ?? [])
        .whereType<Map>()
        .map((u) => PathUnit.fromJson(Map<String, dynamic>.from(u)))
        .toList();
    final current = data['current'] as Map?;
    final units = <JourneyUnit>[];
    var currentAssigned = false;
    for (var ui = 0; ui < sources.length; ui++) {
      final source = sources[ui];
      final steps = <JourneyStep>[];
      for (var i = 0; i < source.skills.length; i++) {
        final skill = source.skills[i];
        final isCurrent =
            !currentAssigned &&
            current?['material_id'] == source.materialId &&
            current?['skill_id'] == skill.skillId &&
            skill.state != 'mastered';
        if (isCurrent) currentAssigned = true;
        // No invented prerequisites. Content readiness and any explicit locked
        // state from the API determine access; current is only a recommendation.
        final state = skill.state == 'mastered'
            ? JourneyState.completed
            : skill.state == 'locked'
            ? JourneyState.locked
            : isCurrent
            ? JourneyState.current
            : skill.explanation || skill.exerciseReady
            ? JourneyState.available
            : JourneyState.locked;
        steps.add(
          JourneyStep(
            skill: skill,
            materialId: source.materialId,
            title: studentTitle(
              skill.name,
              context: '$subject ${skill.description}',
            ),
            state: state,
            index: i,
          ),
        );
      }
      units.add(
        JourneyUnit(
          source: source,
          number: ui + 1,
          title: unitTitle(source, subject: subject),
          steps: steps,
        ),
      );
    }
    return LearningJourney(units);
  }
}

String unitTitle(PathUnit unit, {String subject = ''}) {
  final raw = unit.title.trim();
  if (raw.isNotEmpty) {
    return studentTitle(raw, fallback: 'Your learning unit');
  }
  final titles = unit.skills
      .map((s) => studentTitle(s.name, context: '$subject ${s.description}'))
      .where((s) => s != 'Learning step')
      .toSet()
      .toList();
  if (titles.isNotEmpty) return titles.take(2).join(' & ');
  return studentTitle(subject, fallback: 'Your learning unit');
}

String learningLocation({String? classroomId, bool supplementary = false}) =>
    Uri(
      path: '/student/learn',
      queryParameters: {
        if (classroomId?.isNotEmpty == true) 'classroomId': classroomId!,
        if (supplementary) 'supplementary': 'true',
      },
    ).toString();

String lessonLocation(
  JourneyStep step, {
  String? classroomId,
  bool supplementary = false,
}) => Uri(
  path: '/student/skill/${step.skill.skillId}',
  queryParameters: {
    'materialId': step.materialId,
    if (classroomId?.isNotEmpty == true) 'classroomId': classroomId!,
    if (supplementary) 'supplementary': 'true',
  },
).toString();

String practiceLocation({
  required String materialId,
  String? skillId,
  String? classroomId,
  bool supplementary = false,
  String mode = 'practice',
}) => Uri(
  path: '/student/practice',
  queryParameters: {
    'materialId': materialId,
    if (skillId?.isNotEmpty == true) 'skillId': skillId!,
    if (classroomId?.isNotEmpty == true) 'classroomId': classroomId!,
    if (supplementary) 'supplementary': 'true',
    'mode': mode,
  },
).toString();

/// Preserve all educational content, revealing it in comfortably sized sections.
List<String> lessonSections(String source) {
  final text = cleanStudentText(source);
  if (text.isEmpty) return [];
  final result = <String>[];
  for (final paragraph in text.split(RegExp(r'\n\s*\n'))) {
    var remaining = paragraph.trim();
    while (remaining.length > 420) {
      final candidate = remaining.substring(0, 420);
      var cut = candidate.lastIndexOf(RegExp(r'[.!?]\s'));
      if (cut < 160) cut = candidate.lastIndexOf(' ');
      if (cut <= 0) {
        cut = 420;
      } else {
        cut += 1;
      }
      result.add(remaining.substring(0, cut).trim());
      remaining = remaining.substring(cut).trim();
    }
    if (remaining.isNotEmpty) result.add(remaining);
  }
  return result;
}
