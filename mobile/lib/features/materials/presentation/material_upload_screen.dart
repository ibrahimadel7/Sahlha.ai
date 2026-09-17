import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../../classrooms/data/classroom_repository.dart';
import '../../teacher/presentation/widgets/teacher_widgets.dart';
import '../data/material_repository.dart';
import 'upload_controller.dart';

/// Upload Lesson — matches the reference: dashed drop zone, file-type chips,
/// classroom picker, title, and real Recently uploaded list.
class MaterialUploadScreen extends ConsumerStatefulWidget {
  const MaterialUploadScreen({super.key, this.classroomId});

  final String? classroomId;

  @override
  ConsumerState<MaterialUploadScreen> createState() =>
      _MaterialUploadScreenState();
}

class _MaterialUploadScreenState extends ConsumerState<MaterialUploadScreen> {
  final _title = TextEditingController();
  String? _pickedClassroomId;

  @override
  void initState() {
    super.initState();
    _pickedClassroomId = widget.classroomId;
    Future.microtask(() {
      if (mounted) ref.read(uploadControllerProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = ref.watch(uploadControllerProvider);
    final controller = ref.read(uploadControllerProvider.notifier);
    final rooms = ref.watch(classroomListProvider);
    final recent = ref.watch(materialListProvider());

    ref.listen(uploadControllerProvider, (prev, next) {
      if (prev?.material == null && next.material != null) {
        final roomId = next.material!.classroomId ?? _pickedClassroomId;
        final location = Uri(
          path: '/teacher/materials/${next.material!.id}',
          queryParameters: roomId == null ? null : {'classroomId': roomId},
        ).toString();
        context.pushReplacement(location);
      }
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final effectiveClassroom = _pickedClassroomId ?? widget.classroomId;
    final canUpload =
        !state.picking &&
        !state.uploading &&
        (state.filePath != null || state.fileBytes != null) &&
        effectiveClassroom != null;

    return Scaffold(
      appBar: SahlhaAppBar(
        title: 'Upload Lesson',
        onBack: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/teacher/classrooms');
          }
        },
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SahlhaSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add your teaching material and let Sahlha do the heavy lifting.',
                style: text.bodyMedium?.copyWith(color: SahlhaColors.muted),
              ),
              const SizedBox(height: SahlhaSpacing.lg),
              InkWell(
                onTap: state.picking || state.uploading
                    ? null
                    : controller.pickFile,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(SahlhaSpacing.xl),
                  decoration: BoxDecoration(
                    color: SahlhaColors.surfacePrimary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: SahlhaColors.teal.withValues(alpha: 0.45),
                      width: 1.5,
                      style: BorderStyle.solid,
                    ),
                    boxShadow: SahlhaShadows.soft,
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: SahlhaColors.tealSoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: state.picking
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: SahlhaColors.teal,
                                ),
                              )
                            : const Icon(
                                Icons.description_outlined,
                                color: SahlhaColors.tealDark,
                                size: 30,
                              ),
                      ),
                      const SizedBox(height: SahlhaSpacing.md),
                      Text(
                        state.fileName ?? 'Tap to upload a file',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PDF, DOCX, PPTX, or images (Max 50 MB)',
                        style: text.bodySmall?.copyWith(
                          color: SahlhaColors.muted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (state.uploading) ...[
                        const SizedBox(height: SahlhaSpacing.md),
                        const LinearProgressIndicator(
                          color: SahlhaColors.teal,
                          backgroundColor: SahlhaColors.tealSoft,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          state.step.isEmpty ? 'Uploading…' : state.step,
                          style: text.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: SahlhaSpacing.md),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _FileTypeChip(
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'PDF',
                    bg: Color(0xFFFFE8E4),
                    fg: Color(0xFFB3372F),
                  ),
                  _FileTypeChip(
                    icon: Icons.description_outlined,
                    label: 'DOCX',
                    bg: Color(0xFFE3F2FF),
                    fg: Color(0xFF2E7FC4),
                  ),
                  _FileTypeChip(
                    icon: Icons.slideshow_outlined,
                    label: 'PPTX',
                    bg: Color(0xFFFFF3D1),
                    fg: Color(0xFF956300),
                  ),
                  _FileTypeChip(
                    icon: Icons.image_outlined,
                    label: 'Image',
                    bg: Color(0xFFDFFBF8),
                    fg: Color(0xFF0B6E64),
                  ),
                ],
              ),
              const SizedBox(height: SahlhaSpacing.lg),
              Text('Classroom', style: text.titleSmall),
              const SizedBox(height: SahlhaSpacing.sm),
              rooms.when(
                loading: () => const LoadingState(message: 'Loading classes…'),
                error: (e, _) => ErrorState(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(classroomListProvider),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return SahlhaCard(
                      onTap: () =>
                          context.push('/teacher/classrooms/new'),
                      child: const Row(
                        children: [
                          Icon(Icons.add, color: SahlhaColors.teal),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Create a classroom first'),
                          ),
                        ],
                      ),
                    );
                  }
                  return DropdownButtonFormField<String>(
                    initialValue: effectiveClassroom != null &&
                            list.any((r) => r.id == effectiveClassroom)
                        ? effectiveClassroom
                        : null,
                    decoration: const InputDecoration(
                      hintText: 'Choose a classroom',
                    ),
                    items: list
                        .map(
                          (r) => DropdownMenuItem(
                            value: r.id,
                            child: Text(r.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _pickedClassroomId = v),
                  );
                },
              ),
              const SizedBox(height: SahlhaSpacing.md),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Lesson title (optional)',
                  hintText: 'e.g. Lecture 11 — While Loops',
                ),
              ),
              const SizedBox(height: SahlhaSpacing.lg),
              SahlhaPrimaryButton(
                label: state.uploading ? 'Uploading…' : 'Upload and process',
                loading: state.uploading,
                onPressed: !canUpload
                    ? null
                    : () => controller.upload(
                          title: _title.text.trim(),
                          classroomId: effectiveClassroom,
                        ),
              ),
              const SizedBox(height: SahlhaSpacing.xl),
              Text(
                'Recently uploaded',
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: SahlhaSpacing.sm),
              recent.when(
                loading: () =>
                    const LoadingState(message: 'Loading recent files…'),
                error: (e, _) => ErrorState(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(materialListProvider()),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const SahlhaCard(
                      child: Row(
                        children: [
                          SahlhaProcessingAvatar(size: 52),
                          SizedBox(width: SahlhaSpacing.md),
                          Expanded(
                            child: Text('Great things happen here!'),
                          ),
                        ],
                      ),
                    );
                  }
                  final items = list.take(5).toList();
                  return Column(
                    children: [
                      for (final m in items)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: SahlhaSpacing.sm,
                          ),
                          child: _RecentMaterialRow(materialId: m.id),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: SahlhaSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileTypeChip extends StatelessWidget {
  const _FileTypeChip({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: fg, size: 24),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: SahlhaColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _RecentMaterialRow extends ConsumerWidget {
  const _RecentMaterialRow({required this.materialId});

  final String materialId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final all = ref.watch(materialListProvider()).value ?? const [];
    MaterialRowData? found;
    for (final m in all) {
      if (m.id == materialId) {
        found = MaterialRowData(
          id: m.id,
          title: m.title,
          filename: m.filename,
          status: m.status,
        );
        break;
      }
    }
    if (found == null) return const SizedBox.shrink();
    final isProcessing = found.status == 'processing' ||
        found.status == 'uploaded' ||
        found.status == 'uploading';
    final isFailed = found.status == 'failed';
    final isReady = found.status == 'banks_ready' ||
        found.status == 'skills_ready' ||
        found.status == 'processed';
    return SahlhaCard(
      onTap: () => context.push('/teacher/materials/${found!.id}'),
      padding: const EdgeInsets.all(SahlhaSpacing.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isFailed
                  ? SahlhaColors.softCoralSoft
                  : isReady
                      ? SahlhaColors.successSoft
                      : SahlhaColors.warmYellowSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.description_outlined,
              color: isFailed
                  ? SahlhaColors.softCoralDark
                  : isReady
                      ? SahlhaColors.success
                      : SahlhaColors.warmYellowDeep,
            ),
          ),
          const SizedBox(width: SahlhaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  found.title.isEmpty ? found.filename : found.title,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isProcessing
                      ? 'Processing…'
                      : isFailed
                          ? 'Needs attention'
                          : isReady
                              ? 'Ready for review'
                              : 'Completed',
                  style: text.bodySmall?.copyWith(
                    color: isFailed
                        ? SahlhaColors.softCoralDark
                        : isReady
                            ? SahlhaColors.success
                            : SahlhaColors.warmYellowDeep,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (isProcessing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: SahlhaColors.teal,
              ),
            )
          else if (isReady)
            const Icon(Icons.check_circle, color: SahlhaColors.success)
          else
            const Icon(Icons.chevron_right, color: SahlhaColors.muted),
        ],
      ),
    );
  }
}

class MaterialRowData {
  MaterialRowData({
    required this.id,
    required this.title,
    required this.filename,
    required this.status,
  });

  final String id;
  final String title;
  final String filename;
  final String status;
}
