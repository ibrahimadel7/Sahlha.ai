import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/sahlha_widgets.dart';
import '../../data/student_repository.dart';
import '../journey_presentation.dart';
import '../practice_controller.dart';
import 'joyful_cards.dart';
import 'playful_background.dart';
import 'sahlha_avatar.dart';

class SkillCompletion extends ConsumerWidget {
  const SkillCompletion({
    super.key,
    required this.state,
    required this.elapsed,
    required this.onPath,
    required this.onRetry,
  });
  final PracticeState state;
  final Duration elapsed;
  final VoidCallback onPath, onRetry;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = state.result!;
    final path = ref.watch(
      studentLearningPathProvider(
        classroomId: state.classroomId,
        supplementary: state.childScope,
      ),
    );
    final journey = path.asData == null
        ? null
        : LearningJourney.fromJson(path.asData!.value);
    final steps =
        journey?.units.expand((u) => u.steps).toList() ?? <JourneyStep>[];
    final touched = result.results.map((r) => r.skillId).toSet();
    final practiced = steps
        .where(
          (s) =>
              s.materialId == state.materialId &&
              touched.contains(s.skill.skillId),
        )
        .toList();
    final next = journey?.activeUnit?.current;
    final titles = practiced.map((s) => s.title).join(', ');
    final handled = practiced.where(
      (s) =>
          result.results.any((r) => r.skillId == s.skill.skillId && r.correct),
    );
    final review = practiced.where(
      (s) => result.masteryStates[s.skill.skillId] != 'mastered',
    );
    final mastered = touched.any(
      (id) => result.masteryStates[id] == 'mastered',
    );
    final text = Theme.of(context).textTheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return PlayfulBackground(
      variant: PlayfulVariant.completion,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Center(
            child: SahlhaAvatar(
              size: 130,
              state: mastered
                  ? SahlhaAvatarState.celebrating
                  : SahlhaAvatarState.encouraging,
              label: 'Sahlha celebrating your work',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Nice work!',
            textAlign: TextAlign.center,
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'You completed\n${titles.isEmpty ? 'your practice' : titles}',
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          // Keep exact stats strings for tests: total, correct/total, time.
          const SizedBox(height: 20),
          SkillCompletionSummary(
            questions: result.total,
            correct: result.correct,
            elapsed: elapsed,
          ),
          const SizedBox(height: 18),
          _Recap(
            icon: Icons.lightbulb_outline_rounded,
            title: 'You learned',
            body: practiced.isEmpty
                ? 'You worked through ${result.total} ${result.total == 1 ? "question" : "questions"}.'
                : practiced
                      .map(
                        (s) => cleanStudentText(s.skill.description).isEmpty
                            ? s.title
                            : cleanStudentText(s.skill.description),
                      )
                      .join('\n'),
            color: const Color(0xFFFFF3D1),
          ),
          _Recap(
            icon: Icons.star_outline_rounded,
            title: 'You handled well',
            body: handled.isEmpty
                ? 'You gave yourself time to practice.'
                : handled.map((s) => s.title).join(', '),
            color: const Color(0xFFFFF3D1),
          ),
          if (review.isNotEmpty)
            _Recap(
              icon: Icons.refresh_rounded,
              title: 'Practice again later',
              body: review.map((s) => s.title).join(', '),
              color: const Color(0xFFDFFBF8),
            )
          else
            const _Recap(
              icon: Icons.favorite_outline_rounded,
              title: 'Keep exploring',
              body: 'You\u2019re building real skills. Rest, or explore your path a little more.',
              color: Color(0xFFDFFBF8),
            ),
          const SizedBox(height: 12),
          if (!reduced)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.94, end: 1),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutBack,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: _Cta(
                next: next,
                touched: touched,
                onPath: onPath,
                state: state,
              ),
            )
          else
            _Cta(next: next, touched: touched, onPath: onPath, state: state),
          TextButton(
            onPressed: onRetry,
            child: const Text('Revisit this practice'),
          ),
        ],
      ),
    );
  }
}

class _Cta extends StatelessWidget {
  const _Cta({
    required this.next,
    required this.touched,
    required this.onPath,
    required this.state,
  });
  final JourneyStep? next;
  final Set<String> touched;
  final VoidCallback onPath;
  final PracticeState state;
  @override
  Widget build(BuildContext context) => SahlhaPrimaryButton(
    label: next == null
        ? 'Continue my learning path'
        : touched.contains(next!.skill.skillId)
        ? 'Continue learning'
        : 'Continue to next skill →',
    onPressed: next == null
        ? onPath
        : () => context.go(
            lessonLocation(
              next!,
              classroomId: state.classroomId,
              supplementary: state.childScope,
            ),
          ),
  );
}

class _Recap extends StatelessWidget {
  const _Recap({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });
  final IconData icon;
  final String title, body;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7E1D4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF0B6E64), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(body, style: text.bodyMedium?.copyWith(height: 1.55)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
