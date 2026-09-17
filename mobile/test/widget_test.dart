import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/core/theme/sahlha_theme.dart';
import 'package:sahlha/core/widgets/sahlha_widgets.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: SahlhaTheme.light(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('SahlhaPrimaryButton shows label and loading state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const SahlhaPrimaryButton(label: 'Continue')),
    );
    expect(find.text('Continue'), findsOneWidget);

    await tester.pumpWidget(
      _wrap(const SahlhaPrimaryButton(label: 'Continue', loading: true)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('SkillStatusBadge renders each mastery state', (tester) async {
    for (final state in [
      'mastered',
      'developing',
      'needs_practice',
      'not_started',
    ]) {
      await tester.pumpWidget(_wrap(SkillStatusBadge(state: state)));
      expect(find.text(masteryLabel(state)), findsOneWidget);
    }
  });

  testWidgets('InlineFeedback uses consistent calm language', (tester) async {
    await tester.pumpWidget(
      _wrap(const InlineFeedback(correct: true, message: 'Well done.')),
    );
    expect(find.text('Correct.'), findsOneWidget);

    await tester.pumpWidget(
      _wrap(const InlineFeedback(correct: false, message: 'Try again.')),
    );
    expect(find.text('Not yet.'), findsOneWidget);
  });

  testWidgets('LearningPathNode states render without error', (tester) async {
    for (final state in PathNodeState.values) {
      await tester.pumpWidget(
        _wrap(
          LearningPathNode(
            state: state,
            title: 'Skill',
            subtitle: 'sub',
            isLast: true,
          ),
        ),
      );
      expect(find.text('Skill'), findsOneWidget);
    }
  });
}
