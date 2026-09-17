import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/core/widgets/sahlha_markdown.dart';
import 'package:sahlha/features/student/presentation/journey_presentation.dart'
    show cleanStudentMarkdown, cleanStudentText, lessonSections;
import 'package:sahlha/features/student/presentation/widgets/lesson_content.dart';

void main() {
  group('cleanStudentText strips markdown markers from short labels', () {
    test('bold markers are removed but words kept', () {
      expect(cleanStudentText('The answer is **yes** today'), 'The answer is yes today');
    });
    test('underline runs and backticks are removed', () {
      expect(cleanStudentText('__Photosynthesis__ means `light`'), 'Photosynthesis means light');
    });
    test('math keeps single operators', () {
      expect(cleanStudentText('Compute 3*5 now'), 'Compute 3*5 now');
    });
  });

  group('cleanStudentMarkdown preserves formatting', () {
    test('keeps bold, lists and fences', () {
      const raw = '**Light** energy\n\n- chlorophyll\n- water\n\n```py\nx = 1\n```';
      final out = cleanStudentMarkdown(raw);
      expect(out.contains('**Light**'), isTrue);
      expect(out.contains('- chlorophyll'), isTrue);
      expect(out.contains('```py'), isTrue);
    });
  });

  group('lessonSections never splits inside bold spans', () {
    test('long bold span stays in one section', () {
      final intro = List.filled(30, 'Intro sentence here.').join(' ');
      const span =
          '**Photosynthesis converts light energy into chemical energy for plants.**';
      final tail = List.filled(30, 'Trailing sentence here.').join(' ');
      final sections = lessonSections('$intro $span $tail');
      expect(sections, isNotEmpty);
      for (final s in sections) {
        expect('**'.allMatches(s).length.isEven, isTrue,
            reason: 'unbalanced bold markers in: $s');
      }
      expect(sections.join(' '), contains('Photosynthesis converts'));
    });
  });

  group('LessonContent renders markdown instead of raw markers', () {
    testWidgets('bold shows styled with no literal asterisks', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LessonContent(source: 'Plants use **light** energy daily.'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('**'), findsNothing);
      expect(find.text('Plants use light energy daily.', findRichText: true),
          findsOneWidget);
      var sawBoldLight = false;
      for (final element in find.byType(RichText).evaluate()) {
        final rich = element.widget as RichText;
        if (rich.text.toPlainText() != 'Plants use light energy daily.') {
          continue;
        }
        void walk(InlineSpan span) {
          if (span is TextSpan) {
            if (span.text == 'light' &&
                span.style?.fontWeight == FontWeight.w800) {
              sawBoldLight = true;
            }
            span.children?.forEach(walk);
          }
        }

        walk(rich.text);
      }
      expect(sawBoldLight, isTrue, reason: 'expected "light" in bold');
    });

    testWidgets('SahlhaMarkdown renders lists without raw dashes', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SahlhaMarkdown(data: '- chlorophyll\n- water'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('**'), findsNothing);
      expect(find.text('chlorophyll', findRichText: true), findsOneWidget);
      expect(find.text('water', findRichText: true), findsOneWidget);
    });
  });
}
