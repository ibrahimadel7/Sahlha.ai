import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/core/auth/auth_controller.dart';
import 'package:sahlha/core/theme/sahlha_theme.dart';
import 'package:sahlha/features/auth/domain/app_user.dart';
import 'package:sahlha/features/classrooms/data/classroom_repository.dart';
import 'package:sahlha/features/classrooms/domain/classroom.dart';
import 'package:sahlha/features/student/data/student_repository.dart';
import 'package:sahlha/features/student/domain/skill_models.dart';
import 'package:sahlha/features/student/domain/assessment_models.dart';
import 'package:sahlha/features/student/presentation/learn_screen.dart';
import 'package:sahlha/features/student/presentation/student_home_screen.dart';
import 'package:sahlha/features/student/presentation/student_progress_screen.dart';
import 'package:sahlha/features/student/presentation/student_profile_screen.dart';
import 'package:sahlha/features/learning_profile/data/learning_profile_repository.dart';
import 'package:sahlha/features/learning_profile/domain/learning_profile.dart';
import 'package:sahlha/features/student/presentation/skill_lesson_screen.dart';
import 'package:sahlha/features/student/presentation/practice_screen.dart';
import 'package:sahlha/features/student/presentation/widgets/learning_journey.dart';
import 'package:sahlha/features/student/presentation/widgets/help_me_sheet.dart';
import 'package:sahlha/features/student/presentation/widgets/student_bottom_navigation.dart';

import 'journey_presentation_test.dart' show journeyFixture;

class PreviewStudentRepository extends StudentRepository {
  PreviewStudentRepository() : super(Dio());
  int starts = 0;
  bool failStart = false;
  bool emptyStart = false;
  bool returning = false;
  @override
  Future<AssessmentStart> startQuickCheck({
    String? classroomId,
    String? materialId,
    bool childScope = false,
  }) => startAssessment(
    classroomId: classroomId,
    materialId: materialId,
    childScope: childScope,
  );

  @override
  Future<Map<String, dynamic>> learningPath({
    String? classroomId,
    bool supplementary = false,
  }) async => journeyFixture();
  @override
  Future<Map<String, dynamic>> home() async => {
    'classrooms': [
      {
        'classroom_id': 'room',
        'subject': 'Programming',
        if (returning)
          'recent_practiced_at': DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
        'current': journeyFixture()['current'],
      },
    ],
    'onboarding_completed': true,
  };
  @override
  Future<Map<String, dynamic>> progress({String? classroomId}) async => {
    'classrooms': [
      {
        'classroom_id': 'room',
        'subject': 'Programming',
        'units': journeyFixture()['units'],
        'summary': {'mastered': 1},
        'grades': [],
      },
    ],
  };
  @override
  Future<SkillBundle> skillBundle({
    required String skillId,
    required String materialId,
    String? classroomId,
    bool supplementary = false,
  }) async => const SkillBundle(
    skillId: 'loops',
    name: 'Loops (921200ded738)',
    description: 'Python loop repeats code',
    explanation: 'A loop repeats an instruction. Instead of writing the same line many times, you can tell the computer to repeat it.\n\nFor example, imagine greeting each person in your class. The greeting stays the same, but the person changes.',
    position: 2,
    total: 6,
    exerciseReady: true,
    keyConcepts: ['Repetition', 'Instructions'],
  );
  @override
  Future<AssessmentStart> startAssessment({
    String? classroomId,
    String? materialId,
    String? skillId,
    bool childScope = false,
  }) async {
    starts++;
    if (failStart) {
      failStart = false;
      throw StateError('Internal error with 921200ded738');
    }
    return AssessmentStart(
      assessmentId: 'attempt',
      questions: emptyStart
          ? []
          : const [
              PracticeQuestion(
                id: 'q1',
                skillId: 'loops',
                question: 'What does a loop help a computer do?',
                options: [
                  'Repeat an instruction',
                  'Forget a value',
                  'Close a program',
                ],
              ),
            ],
    );
  }

  @override
  Future<CheckResult> checkAnswer({
    required String assessmentId,
    required String questionId,
    Object? answer,
  }) async => CheckResult(
    questionId: questionId,
    correct: answer == 0,
    correctAnswer: 0,
    explanation:
        'A loop repeats instructions so you do not have to write them again.',
  );
  @override
  Future<AssessmentResult> submitAssessment({
    required String assessmentId,
    required Map<String, Object?> answers,
  }) async => const AssessmentResult(
    assessmentId: 'attempt',
    correct: 1,
    total: 1,
    score: 1,
    results: [
      QuestionResult(
        questionId: 'q1',
        skillId: '921200ded738__loops',
        correct: true,
      ),
    ],
    masteryStates: {'921200ded738__loops': 'mastered'},
  );
}

Future<void> mount(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(390, 844),
  double scale = 1,
  PreviewStudentRepository? repository,
  bool navigation = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        learningProfileProvider.overrideWith(
          (ref) async => const LearningProfile(
            onboardingCompleted: true,
            linkCode: 'SAHL42',
          ),
        ),
        studentRepositoryProvider.overrideWithValue(
          repository ?? PreviewStudentRepository(),
        ),
        currentUserProvider.overrideWith(
          (ref) => const AppUser(id: 'user', name: 'Youssef', role: 'student'),
        ),
        classroomListProvider.overrideWith(
          (ref) async => [
            const Classroom(
              id: 'room',
              name: 'Programming',
              subject: 'Programming',
            ),
          ],
        ),
      ],
      child: MaterialApp(
        theme: SahlhaTheme.light().copyWith(
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              textStyle: const TextStyle(fontFamily: 'PreviewNunito'),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontFamily: 'PreviewNunito'),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              textStyle: const TextStyle(fontFamily: 'PreviewNunito'),
            ),
          ),
          textTheme: SahlhaTheme.light().textTheme.apply(
            fontFamily: 'PreviewNunito',
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: Scaffold(
            body: screen,
            bottomNavigationBar: navigation
                ? StudentBottomNavigation(
                    selectedIndex: screen is StudentHomeScreen
                        ? 0
                        : screen is StudentProgressScreen
                        ? 2
                        : screen is StudentProfileScreen
                        ? 3
                        : 1,
                    onSelected: (_) {},
                  )
                : null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_STUDENT_UI')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('../artifacts/student-redesign')
      ..createSync(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('PreviewNunito')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('test/fonts/Nunito.ttf').readAsBytes(),
          ),
        ),
      );
    await font.load();
    // Flutter's test-only fallback otherwise renders button labels as blocks.
    final fallback = FontLoader('Ahem')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('test/fonts/Nunito.ttf').readAsBytes(),
          ),
        ),
      );
    await fallback.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final entry in <String, Widget>{
    'learn': const LearnScreen(classroomId: 'room'),
    'home': const StudentHomeScreen(),
    'lesson': const SkillLessonScreen(
      skillId: 'loops',
      materialId: 'unit-a',
      classroomId: 'room',
    ),
    'practice': const PracticeScreen(
      materialId: 'unit-a',
      skillId: 'loops',
      classroomId: 'room',
    ),
    'progress': const StudentProgressScreen(),
    'profile': const StudentProfileScreen(),
  }.entries) {
    testWidgets('${entry.key} renders with readable student content', (
      tester,
    ) async {
      await mount(
        tester,
        entry.value,
        navigation: !['lesson', 'practice'].contains(entry.key),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('921200ded738'), findsNothing);
      expect(find.textContaining('.pdf'), findsNothing);
      await capture(tester, entry.key);
    });
    testWidgets(
      '${entry.key} remains scrollable at 320px and 200 percent text',
      (tester) async {
        await mount(
          tester,
          entry.value,
          size: const Size(320, 568),
          scale: 2,
          navigation: !['lesson', 'practice'].contains(entry.key),
        );
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Journey selects the recommended skill with one primary action', (
    tester,
  ) async {
    await mount(tester, const LearnScreen(classroomId: 'room'));
    // The backend-recommended skill is selected by default and owns the
    // single detail block; every node stays tappable.
    expect(find.byType(LearningPathSkillBlock), findsOneWidget);
    expect(find.byType(CurrentSkillCard), findsNothing);
    expect(find.text('YOUR NEXT STEP'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.textContaining('Unit 1'), findsOneWidget);
    expect(find.text('Lecture 11'), findsOneWidget);
  });

  testWidgets('Tapping nodes selects them without changing progress', (
    tester,
  ) async {
    await mount(tester, const LearnScreen(classroomId: 'room'));
    // Scenario B: a completed node offers review, not a reset.
    await tester.tap(find.text('False').first);
    await tester.pumpAndSettle();
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.text('Review skill'), findsOneWidget);
    // Scenario C: a locked node explains its prerequisite.
    await tester.ensureVisible(find.text('Mydlist').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mydlist').first);
    await tester.pumpAndSettle();
    expect(find.text('COMING UP'), findsOneWidget);
    expect(find.text('Locked for now'), findsOneWidget);
    expect(find.textContaining('Looping'), findsWidgets);
  });

  testWidgets('Practice retries real startup and never prints raw errors', (
    tester,
  ) async {
    final repo = PreviewStudentRepository()..failStart = true;
    await mount(
      tester,
      const PracticeScreen(materialId: 'unit-a'),
      repository: repo,
      navigation: false,
    );
    expect(find.textContaining('921200ded738'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(repo.starts, 2);
    expect(find.text('What does a loop help a computer do?'), findsOneWidget);
  });

  testWidgets('Practice empty response ends loading', (tester) async {
    await mount(
      tester,
      const PracticeScreen(materialId: 'unit-a'),
      repository: PreviewStudentRepository()..emptyStart = true,
      navigation: false,
    );
    expect(find.text('Practice is being prepared.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'Feedback uses results without showing technical skill identifiers',
    (tester) async {
      await mount(
        tester,
        const PracticeScreen(materialId: 'unit-a'),
        navigation: false,
      );
      await tester.tap(find.text('Repeat an instruction'));
      await tester.pumpAndSettle();
      expect(find.text('Check answer'), findsNothing);
      await tester.ensureVisible(find.text('Finish practice'));
      await tester.tap(find.text('Finish practice'));
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
      expect(find.textContaining('921200ded738'), findsNothing);
      await capture(tester, 'feedback');
    },
  );

  testWidgets(
    'Quick Check waits for the student and starts one real assessment',
    (tester) async {
      final repository = PreviewStudentRepository();
      await mount(
        tester,
        const PracticeScreen(
          materialId: 'unit-a',
          classroomId: 'room',
          mode: 'checkpoint',
        ),
        repository: repository,
        navigation: false,
      );
      expect(repository.starts, 0);
      expect(find.text('~8 questions'), findsOneWidget);
      await capture(tester, 'quick-check');
      await tester.ensureVisible(find.text('Start Quick Check'));
      await tester.tap(find.text('Start Quick Check'));
      await tester.pumpAndSettle();
      expect(repository.starts, 1);
      expect(find.text('Repeat an instruction'), findsOneWidget);
    },
  );
  testWidgets('Comeback uses the actual name and current skill', (
    tester,
  ) async {
    await mount(
      tester,
      const StudentHomeScreen(),
      repository: PreviewStudentRepository()..returning = true,
    );
    expect(find.text('Welcome back, Youssef!'), findsOneWidget);
    expect(find.text('Continue where you left off'), findsOneWidget);
    await capture(tester, 'comeback');
  });
  testWidgets('Help starts with three choices and reveals additional support', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HelpMeSheet())),
    );
    expect(find.text('Make it simpler'), findsOneWidget);
    expect(find.text('Read aloud'), findsOneWidget);
    expect(find.text('Show visually'), findsNothing);
    await tester.tap(find.text('More ways to help'));
    await tester.pumpAndSettle();
    expect(find.text('Show visually'), findsOneWidget);
  });
}
