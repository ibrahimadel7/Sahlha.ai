import 'package:flutter/material.dart';

import '../../../../core/theme/sahlha_colors.dart';
import '../../../materials/domain/material.dart' show GeneratedSkill;
import '../../../student/presentation/journey_presentation.dart'
    show cleanStudentText;
import 'teacher_widgets.dart';

/// A compact review summary with full, selectable content on expansion.
class TeacherSkillCard extends StatelessWidget {
  const TeacherSkillCard({
    super.key,
    required this.skill,
    required this.questionCount,
    required this.evidenceTone,
    required this.evidenceLabel,
    required this.expanded,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final GeneratedSkill skill;
  final int questionCount;
  final String evidenceTone;
  final String evidenceLabel;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final title = cleanStudentText(
      skill.name.trim().isEmpty ? skill.skillId : skill.name.trim(),
    );
    final description = cleanStudentText(skill.description.trim());
    final showDescription = description.isNotEmpty && description != title;
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: expanded ? SahlhaColors.teal : SahlhaColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: expanded,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: SahlhaColors.tealFaint,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_stories_outlined,
                            size: 20,
                            color: SahlhaColors.tealDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: expanded ? null : 2,
                            overflow: expanded ? null : TextOverflow.ellipsis,
                            style: text.titleSmall?.copyWith(
                              fontSize: 15,
                              height: 1.4,
                              fontWeight: FontWeight.w700,
                              color: SahlhaColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          color: SahlhaColors.muted,
                          size: 20,
                        ),
                      ],
                    ),
                    if (showDescription && !expanded) ...[
                      const SizedBox(height: 10),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(height: 1.5),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '$questionCount question${questionCount == 1 ? '' : 's'}',
                          style: text.bodySmall?.copyWith(
                            color: SahlhaColors.muted,
                          ),
                        ),
                        EvidenceBadge(label: evidenceLabel, tone: evidenceTone),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1, color: SahlhaColors.line),
                  if (showDescription)
                    _section(context, 'Summary', description),
                  if (skill.explanation.trim().isNotEmpty)
                    _section(
                      context,
                      'Explanation',
                      cleanStudentText(skill.explanation.trim()),
                    ),
                  if (skill.keyConcepts.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Key concepts',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final concept in skill.keyConcepts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 5),
                              child: Icon(
                                Icons.check_circle_outline,
                                size: 16,
                                color: SahlhaColors.teal,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                cleanStudentText(concept),
                                style: text.bodyMedium?.copyWith(height: 1.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit skill'),
                      ),
                      TextButton.icon(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          foregroundColor: SahlhaColors.softCoralDark,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Remove'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String label, String value) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SelectableText(
            cleanStudentText(value),
            style: text.bodyMedium?.copyWith(
              height: 1.7,
              color: SahlhaColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
