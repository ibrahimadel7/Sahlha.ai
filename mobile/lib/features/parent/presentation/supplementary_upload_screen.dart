import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../../materials/presentation/upload_controller.dart';
import '../data/parent_repository.dart';

/// Parent uploads SUPPLEMENTARY material for one child.
/// The UI states clearly that it does not replace classroom material.
class SupplementaryUploadScreen extends ConsumerStatefulWidget {
  const SupplementaryUploadScreen({super.key, this.childId});

  final String? childId;

  @override
  ConsumerState<SupplementaryUploadScreen> createState() =>
      _SupplementaryUploadScreenState();
}

class _SupplementaryUploadScreenState
    extends ConsumerState<SupplementaryUploadScreen> {
  final _title = TextEditingController();
  String? _childId;

  @override
  void initState() {
    super.initState();
    _childId = widget.childId;
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
    final children = ref.watch(linkedChildrenProvider);

    ref.listen(uploadControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: const SahlhaAppBar(title: 'Upload Supplementary'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SahlhaSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Supplementary material', style: text.headlineSmall),
              const SizedBox(height: SahlhaSpacing.sm),
              Text(
                'Upload worksheets or notes for your child. This supports their learning — it does not replace classroom material and never changes school grades.',
                style: text.bodyMedium?.copyWith(color: SahlhaColors.muted),
              ),
              const SizedBox(height: SahlhaSpacing.lg),
              children.when(
                loading: () => const LoadingState(),
                error: (e, _) => ErrorState(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(linkedChildrenProvider),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return SahlhaSecondaryButton(
                      label: 'Link a child first',
                      onPressed: () => context.push('/parent/link'),
                    );
                  }
                  if (!list.any((c) => c.id == _childId)) {
                    _childId = list.first.id;
                  }
                  return DropdownButtonFormField<String>(
                    initialValue: list.any((c) => c.id == _childId)
                        ? _childId
                        : list.first.id,
                    decoration: const InputDecoration(labelText: 'Child'),
                    items: list
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    onChanged: state.uploading || state.extracting
                        ? null
                        : (v) {
                            controller.reset();
                            setState(() => _childId = v);
                          },
                  );
                },
              ),
              const SizedBox(height: SahlhaSpacing.lg),
              InkWell(
                onTap: state.picking || state.uploading || state.extracting
                    ? null
                    : controller.pickFile,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(SahlhaSpacing.xl),
                  decoration: BoxDecoration(
                    color: SahlhaColors.tealFaint,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: SahlhaColors.tealSoft,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: SahlhaColors.teal,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: SahlhaSpacing.md),
                      Text(
                        state.fileName ?? 'Choose file',
                        style: text.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: SahlhaSpacing.lg),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Title (optional)',
                ),
              ),
              const SizedBox(height: SahlhaSpacing.xl),
              SahlhaPrimaryButton(
                label: 'Upload',
                loading: state.uploading || state.extracting,
                onPressed:
                    state.picking ||
                        (state.filePath == null && state.fileBytes == null) ||
                        _childId == null ||
                        !(children.value?.any(
                              (child) => child.id == _childId,
                            ) ??
                            false)
                    ? null
                    : () async {
                        if (ref.read(uploadControllerProvider).material ==
                            null) {
                          await controller.upload(
                            title: _title.text.trim(),
                            childStudentId: _childId,
                          );
                        }
                        if (!mounted) return;
                        final uploaded = ref
                            .read(uploadControllerProvider)
                            .material;
                        if (uploaded == null) return;
                        await controller.extractSkills(uploaded.id);
                        if (!mounted) return;
                        if (ref.read(uploadControllerProvider).error == null) {
                          ref.invalidate(linkedChildrenProvider);
                          if (context.mounted) context.go('/parent/materials');
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
