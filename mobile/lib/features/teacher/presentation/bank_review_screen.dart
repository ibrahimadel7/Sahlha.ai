import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/sahlha_colors.dart';
import '../../../core/theme/sahlha_spacing.dart';
import '../../../core/widgets/sahlha_markdown.dart';
import '../../../core/widgets/sahlha_widgets.dart';
import '../../student/presentation/journey_presentation.dart'
    show cleanStudentText;
import '../data/teacher_repository.dart';
import '../domain/bank_models.dart';

/// Teacher reviews EVERY AI-generated question: edit, regenerate,
/// reject — then approve or reject the whole bank.
class BankReviewScreen extends ConsumerStatefulWidget {
  const BankReviewScreen({super.key, required this.bankId});

  final String bankId;

  @override
  ConsumerState<BankReviewScreen> createState() => _BankReviewScreenState();
}

class _BankReviewScreenState extends ConsumerState<BankReviewScreen> {
  int _index = 0;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(bankDetailProvider(widget.bankId));
      await ref.read(bankDetailProvider(widget.bankId).future);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final bank = ref.watch(bankDetailProvider(widget.bankId));
    return Scaffold(
      appBar: const SahlhaAppBar(title: 'Review Questions'),
      body: bank.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(bankDetailProvider(widget.bankId)),
        ),
        data: (detail) {
          final total = detail.questions.length;
          if (total == 0) {
            return const EmptyState(
              title: 'No questions left',
              message: 'All questions were removed. Regenerate the bank to draft new ones.',
            );
          }
          final safeIndex = _index.clamp(0, total - 1);
          if (safeIndex != _index) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => setState(() => _index = safeIndex),
            );
          }
          final q = detail.questions[safeIndex];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(SahlhaSpacing.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              detail.skillId,
                              style: text.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'v${detail.version} · Question ${safeIndex + 1} of $total',
                              style: text.bodySmall?.copyWith(
                                color: SahlhaColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusChip(status: detail.status),
                    ],
                  ),
                  const SizedBox(height: SahlhaSpacing.sm),
                  SahlhaProgressBar(value: (safeIndex + 1) / total, height: 8),
                  const SizedBox(height: SahlhaSpacing.md),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _QuestionCard(question: q),
                    ),
                  ),
                  const SizedBox(height: SahlhaSpacing.md),
                  Row(
                    children: [
                      IconButton.outlined(
                        onPressed: safeIndex == 0
                            ? null
                            : () => setState(() => _index--),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      const SizedBox(width: SahlhaSpacing.sm),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _editQuestion(detail, q),
                          child: const Text('Edit'),
                        ),
                      ),
                      const SizedBox(width: SahlhaSpacing.sm),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _regenerateQuestion(detail, q),
                          child: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Regenerate'),
                        ),
                      ),
                      const SizedBox(width: SahlhaSpacing.sm),
                      IconButton.outlined(
                        onPressed: safeIndex == total - 1
                            ? null
                            : () => setState(() => _index++),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: SahlhaSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SahlhaColors.danger,
                            side: const BorderSide(color: SahlhaColors.danger),
                          ),
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  () => ref
                                      .read(teacherRepositoryProvider)
                                      .deleteQuestion(detail.id, q.id),
                                ),
                          child: const Text('Remove'),
                        ),
                      ),
                      const SizedBox(width: SahlhaSpacing.sm),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: detail.status != 'pending_review' || _busy
                              ? null
                              : () => _run(
                                  () => ref
                                      .read(teacherRepositoryProvider)
                                      .rejectBank(detail.id, ''),
                                ),
                          child: const Text('Reject bank'),
                        ),
                      ),
                      const SizedBox(width: SahlhaSpacing.sm),
                      Expanded(
                        child: FilledButton(
                          onPressed: detail.status != 'pending_review' || _busy
                              ? null
                              : () => _run(() async {
                                  await ref
                                      .read(teacherRepositoryProvider)
                                      .approveBank(detail.id);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Bank approved. Students can now practice it.',
                                        ),
                                      ),
                                    );
                                    context.pop();
                                  }
                                }),
                          child: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _editQuestion(BankDetail detail, BankQuestion q) async {
    final question = TextEditingController(text: q.question);
    final explanation = TextEditingController(text: q.explanation);
    final opts = q.optionTexts
        .map((t) => TextEditingController(text: t))
        .toList();
    int correct = q.correctAnswer is int ? q.correctAnswer as int : 0;
    final ok = await showSahlhaSheet<bool>(
      context,
      StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Edit question', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: SahlhaSpacing.md),
            TextField(
              controller: question,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Question'),
            ),
            const SizedBox(height: SahlhaSpacing.sm),
            RadioGroup<int>(
              groupValue: correct,
              onChanged: (v) => setSheet(() => correct = v ?? 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(opts.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: SahlhaSpacing.xs),
                    child: Row(
                      children: [
                        Radio<int>(value: i),
                        Expanded(
                          child: TextField(
                            controller: opts[i],
                            decoration: InputDecoration(
                              labelText: 'Option ${i + 1}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: SahlhaSpacing.sm),
            TextField(
              controller: explanation,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Explanation'),
            ),
            const SizedBox(height: SahlhaSpacing.md),
            SahlhaPrimaryButton(
              label: 'Save',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(
        () => ref
            .read(teacherRepositoryProvider)
            .editQuestion(
              detail.id,
              q.id,
              questionText: question.text.trim(),
              options: opts.map((c) => c.text.trim()).toList(),
              correctAnswer: correct,
              explanation: explanation.text.trim(),
            )
            .then((_) {}),
      );
    }
    question.dispose();
    explanation.dispose();
    for (final c in opts) {
      c.dispose();
    }
  }

  Future<void> _regenerateQuestion(BankDetail detail, BankQuestion q) async {
    final feedback = TextEditingController();
    final ok = await showSahlhaSheet<bool>(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Regenerate question',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: SahlhaSpacing.sm),
          const Text(
            'Optional guidance, e.g. “Make this easier” or “Use simpler language”.',
          ),
          const SizedBox(height: SahlhaSpacing.md),
          TextField(
            controller: feedback,
            decoration: const InputDecoration(
              labelText: 'Guidance (optional)',
              hintText: 'Make this easier',
            ),
          ),
          const SizedBox(height: SahlhaSpacing.md),
          SahlhaPrimaryButton(
            label: 'Regenerate',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(
        () => ref
            .read(teacherRepositoryProvider)
            .regenerateQuestion(detail.id, q.id, feedback.text.trim())
            .then((_) {}),
      );
    }
    feedback.dispose();
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question});

  final BankQuestion question;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final opts = question.optionTexts;
    final correct = question.correctAnswer is int
        ? question.correctAnswer as int
        : -1;
    return SahlhaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: SahlhaColors.tealSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  question.difficulty,
                  style: text.labelSmall?.copyWith(
                    color: SahlhaColors.tealDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: SahlhaSpacing.sm),
              Text(
                question.type,
                style: text.bodySmall?.copyWith(color: SahlhaColors.muted),
              ),
            ],
          ),
          const SizedBox(height: SahlhaSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SahlhaSpacing.md),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              cleanStudentText(question.question),
              style: text.bodyMedium?.copyWith(
                color: Colors.white,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: SahlhaSpacing.md),
          ...List.generate(opts.length, (i) {
            final isCorrect = i == correct;
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: SahlhaSpacing.xs),
              padding: const EdgeInsets.all(SahlhaSpacing.md),
              decoration: BoxDecoration(
                color: isCorrect
                    ? SahlhaColors.successSoft
                    : SahlhaColors.cream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCorrect ? SahlhaColors.success : SahlhaColors.line,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCorrect ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: isCorrect
                        ? SahlhaColors.success
                        : SahlhaColors.muted,
                  ),
                  const SizedBox(width: SahlhaSpacing.sm),
                  Expanded(child: Text(cleanStudentText(opts[i]))),
                ],
              ),
            );
          }),
          if (question.explanation.isNotEmpty) ...[
            const SizedBox(height: SahlhaSpacing.sm),
            Text(
              'Explanation',
              style: text.labelSmall?.copyWith(color: SahlhaColors.muted),
            ),
            SahlhaMarkdown(
              data: question.explanation,
              baseStyle: text.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      _ => 'Pending review',
    };
    final bg = switch (status) {
      'approved' => SahlhaColors.successSoft,
      'rejected' => SahlhaColors.dangerSoft,
      _ => SahlhaColors.sunSoft,
    };
    final fg = switch (status) {
      'approved' => SahlhaColors.success,
      'rejected' => SahlhaColors.danger,
      _ => const Color(0xFFB45309),
    };
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
