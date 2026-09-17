import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../data/learning_profile_repository.dart';
import '../domain/learning_profile.dart';

/// Short, accessible onboarding — one question at a time.
/// Support preferences only. Never medical, never a diagnosis.
class LearningProfileScreen extends ConsumerStatefulWidget {
  const LearningProfileScreen({super.key});

  @override
  ConsumerState<LearningProfileScreen> createState() =>
      _LearningProfileScreenState();
}

class _LearningProfileScreenState extends ConsumerState<LearningProfileScreen> {
  int _index = 0;
  final Map<String, String> _answers = {};
  bool _saving = false;

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(learningProfileRepositoryProvider)
          .submit(Map.of(_answers));
      ref.invalidate(learningProfileProvider);
      if (mounted) context.go('/student/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final step = kProfileSteps[_index];
    final total = kProfileSteps.length;
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index > 0) setState(() => _index--);
      },
      child: Scaffold(
        appBar: const SahlhaAppBar(title: 'How you learn best'),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SahlhaSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Question ${_index + 1} of $total',
                  style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
                ),
                const SizedBox(height: SahlhaSpacing.sm),
                SahlhaProgressBar(value: (_index + 1) / total),
                const SizedBox(height: SahlhaSpacing.xl),
                Text(step.title, style: text.headlineSmall),
                const SizedBox(height: SahlhaSpacing.sm),
                Text(
                  'There are no wrong answers. This helps Sahlha support you.',
                  style: text.bodyMedium?.copyWith(color: SahlhaColors.muted),
                ),
                const SizedBox(height: SahlhaSpacing.xl),
                ...step.options.map((opt) {
                  final selected = _answers[step.key] == opt.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: SahlhaSpacing.sm),
                    child: QuestionOptionCard(
                      label: opt.label,
                      selected: selected,
                      onTap: () =>
                          setState(() => _answers[step.key] = opt.value),
                    ),
                  );
                }),
                const Spacer(),
                Row(
                  children: [
                    if (_index > 0)
                      Expanded(
                        child: SahlhaSecondaryButton(
                          label: 'Back',
                          onPressed: () => setState(() => _index--),
                        ),
                      ),
                    if (_index > 0) const SizedBox(width: SahlhaSpacing.md),
                    Expanded(
                      flex: 2,
                      child: SahlhaPrimaryButton(
                        label: _index == total - 1
                            ? 'Start learning'
                            : 'Continue',
                        loading: _saving,
                        onPressed: _answers[step.key] == null
                            ? null
                            : () {
                                if (_index == total - 1) {
                                  _submit();
                                } else {
                                  setState(() => _index++);
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
