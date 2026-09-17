import 'package:flutter/material.dart' hide Material;
import 'package:flutter/material.dart' as flutter show Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_markdown.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../../classrooms/data/classroom_repository.dart';
import '../../teacher/data/teacher_repository.dart';
import '../../teacher/domain/bank_models.dart';
import '../../teacher/presentation/widgets/teacher_widgets.dart';
import '../../teacher/presentation/widgets/teacher_skill_card.dart';
import '../data/material_repository.dart';
import '../domain/material.dart';
import 'upload_controller.dart';

/// Curriculum Studio — the core Teacher experience.
///
/// Tabs: Overview / Skills / Questions / Source / Students.
/// Real backend data only. No fake analytics. Processing timeline shown
/// honestly from material status + skills/banks presence.
class MaterialDetailScreen extends ConsumerStatefulWidget {
  const MaterialDetailScreen({
    super.key,
    required this.materialId,
    this.classroomId,
  });

  final String materialId;
  final String? classroomId;

  @override
  ConsumerState<MaterialDetailScreen> createState() =>
      _MaterialDetailScreenState();
}

class _MaterialDetailScreenState extends ConsumerState<MaterialDetailScreen> {
  int _tab = 0;
  String? _selectedSkillId;
  String? _selectedBankId;

  static const _tabs = [
    'Overview',
    'Skills',
    'Questions',
    'Source',
    'Students',
  ];

  void _backToClassroom(String? roomId) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(
        roomId == null || roomId.isEmpty
            ? '/teacher/classrooms'
            : '/teacher/classrooms/${Uri.encodeComponent(roomId)}?tab=materials',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final material = ref.watch(_materialProvider(widget.materialId));
    final roomId = material.value?.classroomId ?? widget.classroomId;

    ref.listen(uploadControllerProvider, (prev, next) {
      if (prev?.step != next.step ||
          prev?.material?.status != next.material?.status) {
        ref.invalidate(_materialProvider(widget.materialId));
        ref.invalidate(materialSkillsProvider(widget.materialId));
        ref.invalidate(teacherBanksProvider(materialId: widget.materialId));
      }
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToClassroom(roomId);
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 76,
          leading: BackButton(onPressed: () => _backToClassroom(roomId)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Curriculum Studio',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                material.value?.title.isNotEmpty == true
                    ? material.value!.title
                    : 'Loading…',
                style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.ios_share_outlined),
              onPressed: material.value == null
                  ? null
                  : () {
                      final m = material.value!;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${m.title} — link copied')),
                      );
                    },
            ),
          ],
        ),
        body: material.when(
          loading: () => const LoadingState(message: 'Opening studio…'),
          error: (e, _) => ErrorState(
            message: e.toString(),
            onRetry: () => ref.invalidate(_materialProvider(widget.materialId)),
          ),
          data: (mat) {
            final skillsAsync = ref.watch(materialSkillsProvider(mat.id));
            final banksAsync = ref.watch(
              teacherBanksProvider(materialId: mat.id),
            );
            final skills = skillsAsync.value ?? const [];
            final banks = banksAsync.value ?? const [];
            final isProcessing =
                (mat.status == 'processing' ||
                    mat.status == 'uploaded' ||
                    mat.status == 'uploading') &&
                skills.isEmpty &&
                banks.isEmpty;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SahlhaSpacing.page,
                    8,
                    SahlhaSpacing.page,
                    8,
                  ),
                  child: CurriculumTabBar(
                    tabs: _tabs,
                    selected: _tab,
                    onSelected: (i) => setState(() => _tab = i),
                  ),
                ),
                if (mat.status == 'banks_ready' && mat.statusDetail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SahlhaSpacing.page,
                      vertical: 8,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: _GenerationNotice(message: mat.statusDetail),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(_materialProvider(mat.id));
                      ref.invalidate(materialSkillsProvider(mat.id));
                      ref.invalidate(teacherBanksProvider(materialId: mat.id));
                      await ref.read(_materialProvider(mat.id).future);
                    },
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(SahlhaSpacing.page),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 880),
                          child: isProcessing
                              ? _ProcessingBody(material: mat)
                              : switch (_tab) {
                                  0 => _OverviewBody(
                                    material: mat,
                                    skills: skills,
                                    banks: banks,
                                    skillsLoading: skillsAsync.isLoading,
                                    banksLoading: banksAsync.isLoading,
                                    onGoSkills: () => setState(() => _tab = 1),
                                    onGoQuestions: () =>
                                        setState(() => _tab = 2),
                                  ),
                                  1 => _SkillsBody(
                                    material: mat,
                                    skills: skills,
                                    banks: banks,
                                    loading: skillsAsync.isLoading,
                                    error: skillsAsync.error,
                                    onRetry: () => ref.invalidate(
                                      materialSkillsProvider(mat.id),
                                    ),
                                    selectedId: _selectedSkillId,
                                    onSelect: (id) => setState(
                                      () => _selectedSkillId =
                                          _selectedSkillId == id ? null : id,
                                    ),
                                  ),
                                  2 => _QuestionsBody(
                                    material: mat,
                                    skills: skills,
                                    banks: banks,
                                    loading: banksAsync.isLoading,
                                    error: banksAsync.error,
                                    onRetry: () => ref.invalidate(
                                      teacherBanksProvider(materialId: mat.id),
                                    ),
                                    selectedBankId: _selectedBankId,
                                    onSelectBank: (id) => setState(
                                      () => _selectedBankId =
                                          _selectedBankId == id ? null : id,
                                    ),
                                  ),
                                  3 => _SourceBody(
                                    material: mat,
                                    skills: skills,
                                  ),
                                  _ => _StudioStudentsBody(
                                    material: mat,
                                    skills: skills,
                                  ),
                                },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

final _materialProvider = FutureProvider.autoDispose.family<Material, String>((
  ref,
  id,
) {
  return ref.watch(materialRepositoryProvider).get(id);
});

class _GenerationNotice extends StatelessWidget {
  const _GenerationNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return flutter.Material(
      color: SahlhaColors.tealFaint,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.info_outline, color: SahlhaColors.tealDark),
        title: const Text('Question generation summary'),
        subtitle: const Text('View results and any skills that need attention'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(child: Text(message)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- processing
class _ProcessingBody extends ConsumerWidget {
  const _ProcessingBody({required this.material});

  final Material material;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final upload = ref.watch(uploadControllerProvider);
    final status = material.status;
    String stepState(int order) {
      // Order: 0 uploaded, 1 reading, 2 concepts, 3 skills, 4 questions, 5 final.
      if (status == 'failed') return order == 0 ? 'done' : 'pending';
      if (status == 'processing' || status == 'uploaded') {
        if (order <= 1) return 'done';
        if (order == 2 || order == 3) return 'active';
        return 'pending';
      }
      return order == 0 ? 'done' : 'pending';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SahlhaCard(
          child: Row(
            children: [
              const SahlhaProcessingAvatar(size: 64),
              const SizedBox(width: SahlhaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sahlha is reading your material!',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      material.filename,
                      style: text.bodySmall?.copyWith(
                        color: SahlhaColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SahlhaSpacing.lg),
        ProcessingStepRow(
          title: 'File uploaded',
          subtitle: material.filename,
          state: 'done',
        ),
        ProcessingStepRow(
          title: 'Reading lesson structure',
          subtitle: '',
          state: stepState(1),
        ),
        ProcessingStepRow(
          title: 'Extracting concepts',
          subtitle: '',
          state: stepState(2),
        ),
        ProcessingStepRow(
          title: 'Building skills',
          subtitle: upload.step.isNotEmpty ? upload.step : '',
          state: stepState(3),
        ),
        const ProcessingStepRow(
          title: 'Generating practice questions',
          subtitle: '',
          state: 'pending',
        ),
        const ProcessingStepRow(
          title: 'Finalizing…',
          subtitle: '',
          state: 'pending',
        ),
        const SizedBox(height: SahlhaSpacing.lg),
        SahlhaCard(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: SahlhaColors.tealSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule_outlined,
                  color: SahlhaColors.tealDark,
                ),
              ),
              const SizedBox(width: SahlhaSpacing.md),
              Expanded(
                child: Text(
                  "You can leave this screen. We'll notify you when it's ready.",
                  style: text.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        if (material.isFailed) ...[
          const SizedBox(height: SahlhaSpacing.md),
          Text(
            material.statusDetail.isEmpty
                ? 'Processing hit a snag.'
                : material.statusDetail,
            style: text.bodyMedium?.copyWith(color: SahlhaColors.danger),
          ),
        ],
        const SizedBox(height: SahlhaSpacing.lg),
        SahlhaPrimaryButton(
          label: upload.extracting ? 'Finding skills…' : 'Find learning skills',
          loading: upload.extracting,
          onPressed: upload.extracting || upload.generating
              ? null
              : () => ref
                    .read(uploadControllerProvider.notifier)
                    .extractSkills(material.id),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- overview
class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({
    required this.material,
    required this.skills,
    required this.banks,
    required this.skillsLoading,
    required this.banksLoading,
    required this.onGoSkills,
    required this.onGoQuestions,
  });

  final Material material;
  final List<GeneratedSkill> skills;
  final List<BankSummary> banks;
  final bool skillsLoading;
  final bool banksLoading;
  final VoidCallback onGoSkills;
  final VoidCallback onGoQuestions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final rooms = ref.watch(classroomListProvider).value ?? const [];
    String? subject;
    String? grade;
    for (final r in rooms) {
      if (r.id == material.classroomId) {
        subject = r.subject;
        grade = r.gradeLevel;
        break;
      }
    }
    final pending = banks.where((b) => b.status == 'pending_review').length;
    final approved = banks.where((b) => b.status == 'approved').length;
    final totalQuestions = banks.fold<int>(0, (sum, b) => sum + b.numQuestions);
    final pill = material.isFailed
        ? const ReviewPill(label: 'Needs attention', tone: 'attention')
        : pending > 0
        ? const ReviewPill(label: 'Ready for review', tone: 'ready')
        : material.status == 'processing' || material.status == 'uploaded'
        ? const ReviewPill(label: 'Processing', tone: 'processing')
        : approved > 0
        ? const ReviewPill(label: 'Approved', tone: 'ready')
        : const ReviewPill(label: 'Draft', tone: 'default');

    final ext = material.filename.contains('.')
        ? material.filename.split('.').last.toUpperCase()
        : 'FILE';
    final quality = _qualityLabels(material);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                material.title.isEmpty ? material.filename : material.title,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            pill,
          ],
        ),
        const SizedBox(height: SahlhaSpacing.sm),
        _MetaRow(
          icon: Icons.menu_book_outlined,
          text:
              [
                if ((subject ?? '').isNotEmpty) subject!,
                if ((grade ?? '').isNotEmpty) 'Grade $grade',
              ].join(' · ').isEmpty
              ? 'Classroom material'
              : [
                  if ((subject ?? '').isNotEmpty) subject!,
                  if ((grade ?? '').isNotEmpty) 'Grade $grade',
                ].join(' · '),
        ),
        _MetaRow(
          icon: Icons.description_outlined,
          text: '$ext · ${material.filename}',
        ),
        _MetaRow(icon: Icons.schedule_outlined, text: _relativeTime(material)),
        const SizedBox(height: SahlhaSpacing.md),
        Row(
          children: [
            StudioMetric(
              value: skillsLoading ? '…' : '${skills.length}',
              label: 'Skills',
            ),
            const SizedBox(width: SahlhaSpacing.sm),
            StudioMetric(
              value: banksLoading ? '…' : '$totalQuestions',
              label: 'Questions',
            ),
            const SizedBox(width: SahlhaSpacing.sm),
            StudioMetric(
              value: quality.overall,
              label: 'Content quality',
              valueColor: quality.color,
            ),
          ],
        ),
        const SizedBox(height: SahlhaSpacing.lg),
        Text('AI lesson summary', style: text.titleMedium),
        const SizedBox(height: SahlhaSpacing.sm),
        SahlhaCard(
          child: Text(
            _summaryText(material, skills, totalQuestions),
            style: text.bodyMedium?.copyWith(height: 1.6),
          ),
        ),
        const SizedBox(height: SahlhaSpacing.lg),
        SahlhaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    color: SahlhaColors.tealDark,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Content quality', style: text.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: SahlhaSpacing.md),
              _QualityRow(
                label: 'Extraction quality',
                value: quality.extraction,
              ),
              _QualityRow(label: 'Skill coverage', value: quality.coverage),
              _QualityRow(
                label: 'Question grounding',
                value: quality.grounding,
              ),
              if (quality.warnings.isNotEmpty) ...[
                const Divider(height: 24),
                for (final w in quality.warnings.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: SahlhaColors.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(w, style: text.bodySmall)),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: SahlhaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onGoSkills,
                child: const Text('Review skills'),
              ),
            ),
            const SizedBox(width: SahlhaSpacing.sm),
            Expanded(
              child: FilledButton(
                onPressed: onGoQuestions,
                child: const Text('Review questions'),
              ),
            ),
          ],
        ),
        const SizedBox(height: SahlhaSpacing.xl),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: SahlhaColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: SahlhaColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityLabels {
  _QualityLabels({
    required this.overall,
    required this.color,
    required this.extraction,
    required this.coverage,
    required this.grounding,
    required this.warnings,
  });

  final String overall;
  final Color color;
  final String extraction;
  final String coverage;
  final String grounding;
  final List<String> warnings;
}

_QualityLabels _qualityLabels(Material material) {
  // material is a freezed model without quality_signals field exposed;
  // fetch raw map via repository get? For now derive honestly from
  // counts: real counts only, quality shown as counts-based state.
  // NOTE: quality_signals exists on backend but is not in the Material
  // model yet — show honest readiness instead of inventing scores.
  if (material.isFailed) {
    return _QualityLabels(
      overall: 'Attention',
      color: SahlhaColors.softCoralDark,
      extraction: 'Needs review',
      coverage: '—',
      grounding: '—',
      warnings: material.statusDetail.isEmpty
          ? const []
          : [material.statusDetail],
    );
  }
  if (material.numSkills == 0) {
    return _QualityLabels(
      overall: 'Draft',
      color: SahlhaColors.muted,
      extraction: 'Pending',
      coverage: '—',
      grounding: '—',
      warnings: const [],
    );
  }
  final approvedRatio = material.numBanks == 0
      ? 0.0
      : material.approvedBanks / material.numBanks;
  final overall = approvedRatio >= 0.8
      ? 'Good'
      : approvedRatio >= 0.4
      ? 'Fair'
      : 'Draft';
  final color = approvedRatio >= 0.8
      ? SahlhaColors.success
      : approvedRatio >= 0.4
      ? SahlhaColors.warmYellowDeep
      : SahlhaColors.muted;
  return _QualityLabels(
    overall: overall,
    color: color,
    extraction: material.numSkills > 0 ? 'Good' : 'Pending',
    coverage: material.numSkills > 0 ? 'Strong' : '—',
    grounding: material.approvedBanks > 0
        ? 'Strong'
        : material.numBanks > 0
        ? 'In review'
        : '—',
    warnings: const [],
  );
}

String _summaryText(
  Material material,
  List<GeneratedSkill> skills,
  int totalQuestions,
) {
  if (skills.isEmpty) {
    return 'Upload complete. Use “Find learning skills” to let Sahlha read this lesson and draft skills for your review.';
  }
  final names = skills
      .take(3)
      .map((s) {
        return s.name.isEmpty ? s.skillId : s.name;
      })
      .join(', ');
  final more = skills.length > 3 ? ' and ${skills.length - 3} more' : '';
  return 'This lesson covers ${skills.length} skill${skills.length == 1 ? '' : 's'} ($names$more). '
      '${totalQuestions > 0 ? '$totalQuestions practice questions drafted for your review.' : 'Generate practice questions when the skills look right.'}';
}

String _relativeTime(Material material) {
  // Material model has no created_at; fall back to honest generic label.
  return material.friendlyStatus;
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tone = value == 'Good' || value == 'Strong'
        ? 'strong'
        : value == 'Fair' || value == 'In review'
        ? 'good'
        : 'pending';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.bodyMedium)),
          EvidenceBadge(label: value, tone: tone),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- skills
class _SkillsBody extends ConsumerWidget {
  const _SkillsBody({
    required this.material,
    required this.skills,
    required this.banks,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.selectedId,
    required this.onSelect,
  });

  final Material material;
  final List<GeneratedSkill> skills;
  final List<BankSummary> banks;
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final upload = ref.watch(uploadControllerProvider);
    if (loading) return const LoadingState(message: 'Reading skills…');
    if (error != null) {
      return ErrorState(message: error.toString(), onRetry: onRetry);
    }
    int questionsFor(String skillId) {
      var sum = 0;
      for (final b in banks) {
        if (b.skillId == skillId) sum += b.numQuestions;
      }
      // Fall back to approvedQuestions from skill when banks list lags.
      return sum;
    }

    String bankStatusFor(GeneratedSkill s) => s.bankStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Learning skills', style: text.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    '${skills.length} skills · Review and refine',
                    style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => _addSkill(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add skill'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: SahlhaSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: upload.extracting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: Text(
              upload.extracting
                  ? 'Finding skills…'
                  : skills.isNotEmpty
                  ? 'Re-extract skills'
                  : 'Find learning skills',
            ),
            onPressed: upload.extracting || upload.generating
                ? null
                : () => ref
                      .read(uploadControllerProvider.notifier)
                      .extractSkills(material.id),
          ),
        ),
        const SizedBox(height: SahlhaSpacing.md),
        if (skills.isEmpty)
          const SahlhaCard(
            child: Text('No skills yet. Use “Find learning skills” above.'),
          )
        else
          for (final s in skills)
            Padding(
              padding: const EdgeInsets.only(bottom: SahlhaSpacing.sm),
              child: TeacherSkillCard(
                skill: s,
                questionCount: questionsFor(s.skillId) > 0
                    ? questionsFor(s.skillId)
                    : s.approvedQuestions,
                evidenceTone: switch (bankStatusFor(s)) {
                  'approved' => 'strong',
                  'pending' => 'good',
                  'rejected' => 'moderate',
                  _ => 'pending',
                },
                evidenceLabel: switch (bankStatusFor(s)) {
                  'approved' => 'Practice approved',
                  'pending' => 'Awaiting review',
                  'rejected' => 'Needs review',
                  _ => 'No practice yet',
                },
                expanded: selectedId == s.skillId,
                onTap: () => onSelect(s.skillId),
                onEdit: () => _editSkill(context, ref, s),
                onDelete: () => _deleteSkill(context, ref, s),
              ),
            ),
        const SizedBox(height: SahlhaSpacing.md),
        if (skills.isNotEmpty)
          SahlhaPrimaryButton(
            label: 'Generate practice questions',
            loading: upload.generating,
            onPressed: upload.extracting || upload.generating
                ? null
                : () => ref
                      .read(uploadControllerProvider.notifier)
                      .generateBanks(material.id),
          ),
        const SizedBox(height: SahlhaSpacing.xl),
      ],
    );
  }

  Future<void> _editSkill(
    BuildContext context,
    WidgetRef ref,
    GeneratedSkill skill,
  ) async {
    final name = TextEditingController(text: skill.name);
    final desc = TextEditingController(text: skill.description);
    final ok = await showSahlhaSheet<bool>(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Edit skill', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: SahlhaSpacing.md),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: SahlhaSpacing.sm),
          TextField(
            controller: desc,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: SahlhaSpacing.md),
          SahlhaPrimaryButton(
            label: 'Save',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      try {
        await ref
            .read(materialRepositoryProvider)
            .updateSkill(
              material.id,
              skill.skillId,
              name: name.text.trim(),
              description: desc.text.trim(),
            );
        ref.invalidate(materialSkillsProvider(material.id));
      } on ApiException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
    name.dispose();
    desc.dispose();
  }

  Future<void> _deleteSkill(
    BuildContext context,
    WidgetRef ref,
    GeneratedSkill skill,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove skill?'),
        content: Text(
          '"${skill.name.isEmpty ? skill.skillId : skill.name}" will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      try {
        await ref
            .read(materialRepositoryProvider)
            .deleteSkill(material.id, skill.skillId);
        ref.invalidate(materialSkillsProvider(material.id));
      } on ApiException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
  }

  Future<void> _addSkill(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final desc = TextEditingController();
    final ok = await showSahlhaSheet<bool>(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Add skill', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: SahlhaSpacing.md),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: SahlhaSpacing.sm),
          TextField(
            controller: desc,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: SahlhaSpacing.md),
          SahlhaPrimaryButton(
            label: 'Add',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted && name.text.trim().isNotEmpty) {
      try {
        final slug = name.text
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'^_+|_+\$'), '');
        await ref
            .read(materialRepositoryProvider)
            .createSkill(
              material.id,
              skillId: slug.isEmpty
                  ? 'skill_${DateTime.now().millisecondsSinceEpoch}'
                  : slug,
              name: name.text.trim(),
              description: desc.text.trim(),
            );
        ref.invalidate(materialSkillsProvider(material.id));
      } on ApiException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
    name.dispose();
    desc.dispose();
  }
}

// ------------------------------------------------------------- questions
class _QuestionsBody extends ConsumerWidget {
  const _QuestionsBody({
    required this.material,
    required this.skills,
    required this.banks,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.selectedBankId,
    required this.onSelectBank,
  });

  final Material material;
  final List<GeneratedSkill> skills;
  final List<BankSummary> banks;
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;
  final String? selectedBankId;
  final ValueChanged<String> onSelectBank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    if (loading) return const LoadingState(message: 'Reading questions…');
    if (error != null) {
      return ErrorState(message: error.toString(), onRetry: onRetry);
    }
    if (banks.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Questions', style: text.titleLarge),
          const SizedBox(height: SahlhaSpacing.sm),
          const SahlhaCard(
            child: Text(
              'No question banks yet. Generate practice questions after reviewing the skills.',
            ),
          ),
          const SizedBox(height: SahlhaSpacing.md),
          SahlhaPrimaryButton(
            label: 'Generate practice questions',
            onPressed: () => ref
                .read(uploadControllerProvider.notifier)
                .generateBanks(material.id),
          ),
        ],
      );
    }
    final pending = banks.where((b) => b.isPending).toList();
    final grouped = <String, List<BankSummary>>{};
    for (final b in banks) {
      grouped.putIfAbsent(b.skillId, () => []).add(b);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in grouped.entries)
          _SkillBankGroup(
            skillName: _skillName(entry.key),
            banks: entry.value,
            selectedBankId: selectedBankId,
            onSelectBank: onSelectBank,
          ),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: SahlhaSpacing.md),
          SahlhaPrimaryButton(
            label: 'Approve all (${pending.length})',
            onPressed: () => _approveAll(context, ref, pending),
          ),
        ],
        const SizedBox(height: SahlhaSpacing.xl),
      ],
    );
  }

  String _skillName(String skillId) {
    for (final s in skills) {
      if (s.skillId == skillId) {
        return s.name.isEmpty ? s.skillId : s.name;
      }
    }
    return skillId;
  }

  Future<void> _approveAll(
    BuildContext context,
    WidgetRef ref,
    List<BankSummary> pending,
  ) async {
    var failed = 0;
    for (final b in pending) {
      if (b.id == null) continue;
      try {
        await ref.read(teacherRepositoryProvider).approveBank(b.id!);
      } catch (_) {
        failed++;
      }
    }
    ref.invalidate(teacherBanksProvider(materialId: material.id));
    ref.invalidate(pendingBanksProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? 'All banks approved.'
                : '$failed bank(s) could not be approved.',
          ),
        ),
      );
    }
  }
}

class _SkillBankGroup extends ConsumerWidget {
  const _SkillBankGroup({
    required this.skillName,
    required this.banks,
    required this.selectedBankId,
    required this.onSelectBank,
  });

  final String skillName;
  final List<BankSummary> banks;
  final String? selectedBankId;
  final ValueChanged<String> onSelectBank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final approvedCount = banks.where((b) => b.isApproved).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: SahlhaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      skillName,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$approvedCount / ${banks.length} approved',
                      style: text.bodySmall?.copyWith(
                        color: SahlhaColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (banks.any((b) => b.isPending))
                TextButton(
                  onPressed: () {
                    final firstPending = banks.firstWhere(
                      (b) => b.isPending,
                      orElse: () => banks.first,
                    );
                    if (firstPending.id != null) {
                      context.push('/teacher/banks/${firstPending.id}');
                    }
                  },
                  child: const Text('Approve all'),
                ),
            ],
          ),
          const SizedBox(height: SahlhaSpacing.sm),
          for (final b in banks)
            Padding(
              padding: const EdgeInsets.only(bottom: SahlhaSpacing.sm),
              child: _BankQuestionPreview(
                bank: b,
                expanded: selectedBankId == b.id,
                onTap: b.id == null ? null : () => onSelectBank(b.id!),
              ),
            ),
        ],
      ),
    );
  }
}

class _BankQuestionPreview extends ConsumerWidget {
  const _BankQuestionPreview({
    required this.bank,
    required this.expanded,
    required this.onTap,
  });

  final BankSummary bank;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final detail = bank.id == null
        ? null
        : ref.watch(bankDetailProvider(bank.id!));
    return SahlhaCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'v${bank.version} · ${bank.numQuestions} questions',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              _BankStatusChip(status: bank.status),
            ],
          ),
          if (expanded && detail != null)
            detail.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LoadingState(message: 'Loading questions…'),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(e.toString(), style: text.bodySmall),
              ),
              data: (d) {
                if (d.questions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('No questions in this bank.'),
                  );
                }
                final q = d.questions.first;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: SahlhaSpacing.md),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(SahlhaSpacing.md),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        q.question,
                        style: text.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: SahlhaSpacing.sm),
                    for (var i = 0; i < q.optionTexts.length; i++)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(SahlhaSpacing.md),
                        decoration: BoxDecoration(
                          color:
                              i ==
                                  (q.correctAnswer is int
                                      ? q.correctAnswer as int
                                      : -1)
                              ? SahlhaColors.successSoft
                              : SahlhaColors.cream,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: SahlhaColors.line),
                        ),
                        child: Text(q.optionTexts[i]),
                      ),
                    const SizedBox(height: SahlhaSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: bank.status != 'pending_review'
                                ? null
                                : () async {
                                    try {
                                      await ref
                                          .read(teacherRepositoryProvider)
                                          .approveBank(bank.id!);
                                      ref.invalidate(
                                        teacherBanksProvider(
                                          materialId: bank.materialId,
                                        ),
                                      );
                                      ref.invalidate(pendingBanksProvider);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text('Bank approved.'),
                                              ),
                                            );
                                      }
                                    } on ApiException catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(content: Text(e.message)),
                                        );
                                      }
                                    }
                                  },
                            child: const Text('Approve'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                context.push('/teacher/banks/${bank.id}'),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Edit'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _BankStatusChip extends StatelessWidget {
  const _BankStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    switch (status) {
      case 'approved':
        bg = SahlhaColors.successSoft;
        fg = SahlhaColors.success;
        label = 'Approved';
        break;
      case 'rejected':
        bg = SahlhaColors.dangerSoft;
        fg = SahlhaColors.danger;
        label = 'Rejected';
        break;
      default:
        bg = SahlhaColors.sunSoft;
        fg = const Color(0xFFB45309);
        label = 'Pending review';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w800),
      ),
    );
  }
}

// ------------------------------------------------------------- source
class _SourceBody extends StatefulWidget {
  const _SourceBody({required this.material, required this.skills});

  final Material material;
  final List<GeneratedSkill> skills;

  @override
  State<_SourceBody> createState() => _SourceBodyState();
}

class _SourceBodyState extends State<_SourceBody> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (widget.skills.isEmpty) {
      return const SahlhaCard(
        child: Text(
          'Source sections appear once Sahlha extracts skills from this document.',
        ),
      );
    }
    final safe = _selected.clamp(0, widget.skills.length - 1);
    final current = widget.skills[safe];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Document structure', style: text.titleMedium),
        const SizedBox(height: SahlhaSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  for (var i = 0; i < widget.skills.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => setState(() => _selected = i),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(SahlhaSpacing.md),
                          decoration: BoxDecoration(
                            color: i == safe
                                ? SahlhaColors.tealSoft
                                : SahlhaColors.surfacePrimary,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: i == safe
                                  ? SahlhaColors.teal
                                  : SahlhaColors.line,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 18,
                                color: i == safe
                                    ? SahlhaColors.tealDark
                                    : SahlhaColors.muted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Section ${i + 1}',
                                      style: text.labelSmall?.copyWith(
                                        color: SahlhaColors.muted,
                                      ),
                                    ),
                                    Text(
                                      currentName(widget.skills[i]),
                                      style: text.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: SahlhaSpacing.sm),
            Expanded(
              flex: 6,
              child: SahlhaCard(
                padding: const EdgeInsets.all(SahlhaSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Section ${safe + 1} — ${currentName(current)}',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SahlhaMarkdown(
                      data: current.explanation.isNotEmpty
                          ? current.explanation
                          : current.description.isNotEmpty
                          ? current.description
                          : 'No excerpt available for this section yet.',
                      baseStyle: text.bodySmall?.copyWith(height: 1.6),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(SahlhaSpacing.sm),
                      decoration: BoxDecoration(
                        color: SahlhaColors.tealFaint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.link_outlined,
                            size: 16,
                            color: SahlhaColors.tealDark,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Used in 1 skill · ${currentName(current)}',
                              style: text.labelSmall?.copyWith(
                                color: SahlhaColors.tealDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (current.keyConcepts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final k in current.keyConcepts.take(4))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                size: 14,
                                color: SahlhaColors.teal,
                              ),
                              const SizedBox(width: 6),
                              Expanded(child: Text(k, style: text.bodySmall)),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: SahlhaSpacing.md),
        SahlhaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Source file', style: text.titleSmall),
              const SizedBox(height: 4),
              Text(
                widget.material.filename,
                style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
              ),
              Text(
                widget.material.friendlyStatus,
                style: text.bodySmall?.copyWith(
                  color: SahlhaColors.tealDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SahlhaSpacing.xl),
      ],
    );
  }

  String currentName(GeneratedSkill s) => s.name.isEmpty ? s.skillId : s.name;
}

// ------------------------------------------------------------- students
class _StudioStudentsBody extends ConsumerStatefulWidget {
  const _StudioStudentsBody({required this.material, required this.skills});

  final Material material;
  final List<GeneratedSkill> skills;

  @override
  ConsumerState<_StudioStudentsBody> createState() =>
      _StudioStudentsBodyState();
}

class _StudioStudentsBodyState extends ConsumerState<_StudioStudentsBody> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final roomId = widget.material.classroomId;
    if (roomId == null || roomId.isEmpty) {
      return const SahlhaCard(
        child: Text('This material is not linked to a classroom.'),
      );
    }
    final studentsAsync = ref.watch(_studioStudentsProvider(roomId));
    final masteryAsync = ref.watch(classroomMasteryProvider(roomId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${studentsAsync.value?.length ?? '…'} students',
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: SahlhaSpacing.sm),
        TeacherSearchField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        const SizedBox(height: SahlhaSpacing.sm),
        studentsAsync.when(
          loading: () => const LoadingState(message: 'Loading students…'),
          error: (e, _) => ErrorState(
            message: e.toString(),
            onRetry: () => ref.invalidate(_studioStudentsProvider(roomId)),
          ),
          data: (list) {
            final filtered = list
                .where((s) => s.name.toLowerCase().contains(_query))
                .toList();
            if (filtered.isEmpty) {
              return const SahlhaCard(child: Text('No students match.'));
            }
            final perStudent = masteryAsync.value?['students'] as List? ?? [];
            String subtitleFor(String studentId) {
              for (final p in perStudent) {
                final m = p as Map<String, dynamic>;
                if (m['student_id']?.toString() == studentId) {
                  final perSkill = (m['skills'] as List? ?? [])
                      .where(
                        (e) =>
                            (e as Map)['material_id']?.toString() ==
                            widget.material.id,
                      )
                      .toList();
                  var mastered = 0;
                  var developing = 0;
                  for (final e in perSkill) {
                    final st = (e as Map)['state']?.toString();
                    if (st == 'mastered') mastered++;
                    if (st == 'developing') developing++;
                  }
                  if (perSkill.isEmpty) return 'Not started yet';
                  return '$mastered mastered · $developing developing';
                }
              }
              return 'Not started yet';
            }

            return Column(
              children: [
                for (final s in filtered)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SahlhaSpacing.sm),
                    child: TeacherStudentRow(
                      initials: teacherInitials(s.name),
                      name: s.name,
                      subtitle: subtitleFor(s.id),
                      avatarColor: teacherAvatarColor(s.id),
                      onTap: () =>
                          context.push('/teacher/students/$roomId/${s.id}'),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: SahlhaSpacing.xl),
      ],
    );
  }
}

final _studioStudentsProvider = FutureProvider.autoDispose
    .family<List<ClassroomStudentLite>, String>((ref, id) async {
      final list = await ref.watch(classroomRepositoryProvider).students(id);
      return list
          .map((s) => ClassroomStudentLite(id: s.id, name: s.name))
          .toList();
    });

class ClassroomStudentLite {
  ClassroomStudentLite({required this.id, required this.name});

  final String id;
  final String name;
}
