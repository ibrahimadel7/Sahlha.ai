import 'package:flutter/material.dart' hide Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../../materials/domain/material.dart';
import '../data/parent_repository.dart';

/// Supplementary library: parent-uploaded support materials for the child.
/// Explicitly NOT classroom curriculum.
class ChildMaterialsScreen extends ConsumerWidget {
  const ChildMaterialsScreen({super.key, this.childId});

  final String? childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final children = ref.watch(linkedChildrenProvider);
    return Scaffold(
      appBar: const SahlhaAppBar(title: 'Supplementary Library'),
      body: children.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(linkedChildrenProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              title: 'No linked child yet',
              message: 'Link your child first.',
              action: SahlhaPrimaryButton(
                label: 'Link a child',
                onPressed: () => context.push('/parent/link'),
              ),
            );
          }
          final id =
              childId ?? ref.watch(selectedChildProvider) ?? list.first.id;
          final mats = ref.watch(_matsProvider(id));
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: DropdownButtonFormField<String>(
                  initialValue: list.any((c) => c.id == id)
                      ? id
                      : list.first.id,
                  decoration: const InputDecoration(labelText: 'Child'),
                  items: list
                      .map(
                        (c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                      )
                      .toList(),
                  onChanged: (v) =>
                      ref.read(selectedChildProvider.notifier).select(v),
                ),
              ),
              Expanded(
                child: mats.when(
                  loading: () => const LoadingState(),
                  error: (e, _) => ErrorState(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(_matsProvider(id)),
                  ),
                  data: (materials) => ListView(
                    padding: const EdgeInsets.all(SahlhaSpacing.page),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(SahlhaSpacing.md),
                        decoration: BoxDecoration(
                          color: SahlhaColors.tealFaint,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: SahlhaColors.tealSoft),
                        ),
                        child: Text(
                          'Supplementary material supports your child’s learning. It does not replace classroom material.',
                          style: text.bodySmall?.copyWith(
                            color: SahlhaColors.tealDark,
                          ),
                        ),
                      ),
                      const SizedBox(height: SahlhaSpacing.md),
                      SahlhaPrimaryButton(
                        label: 'Upload supplementary material',
                        onPressed: () =>
                            context.push('/parent/upload?childId=$id'),
                      ),
                      const SizedBox(height: SahlhaSpacing.lg),
                      if (materials.isEmpty)
                        const EmptyState(
                          title: 'No supplementary material',
                          message: 'Upload worksheets or notes and Sahlha will turn them into extra support.',
                        )
                      else
                        ...materials.map(
                          (m) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: SahlhaSpacing.sm,
                            ),
                            child: SahlhaCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.title, style: text.titleMedium),
                                  Text(
                                    m.filename,
                                    style: text.bodySmall?.copyWith(
                                      color: SahlhaColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    m.friendlyStatus,
                                    style: text.bodySmall?.copyWith(
                                      color: SahlhaColors.tealDark,
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
              ),
            ],
          );
        },
      ),
    );
  }
}

final _matsProvider = FutureProvider.autoDispose.family<List<Material>, String>(
  (ref, id) {
    return ref.watch(parentRepositoryProvider).childMaterials(id);
  },
);
