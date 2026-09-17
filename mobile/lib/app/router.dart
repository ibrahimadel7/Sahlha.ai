import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/auth/auth_controller.dart';
import '../features/auth/domain/app_user.dart';
import '../features/auth/presentation/choose_role_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/learning_profile/presentation/learning_profile_screen.dart';
import '../features/materials/presentation/material_detail_screen.dart';
import '../features/materials/presentation/material_upload_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/onboarding/presentation/splash_screen.dart';
import '../features/parent/presentation/child_materials_screen.dart';
import '../features/parent/presentation/child_progress_screen.dart';
import '../features/parent/presentation/link_child_screen.dart';
import '../features/parent/presentation/parent_home_screen.dart';
import '../features/parent/presentation/parent_profile_screen.dart';
import '../features/parent/presentation/supplementary_upload_screen.dart';
import '../features/student/presentation/join_classroom_screen.dart';
import '../features/student/presentation/learn_screen.dart';
import '../features/student/presentation/practice_screen.dart';
import '../features/student/presentation/skill_lesson_screen.dart';
import '../features/student/presentation/student_home_screen.dart';
import '../features/student/presentation/student_progress_screen.dart';
import '../features/student/presentation/student_profile_screen.dart';
import '../features/teacher/presentation/analytics_screen.dart';
import '../features/teacher/presentation/bank_review_screen.dart';
import '../features/teacher/presentation/classroom_detail_screen.dart';
import '../features/teacher/presentation/classrooms_screen.dart';
import '../features/teacher/presentation/create_classroom_screen.dart';
import '../features/teacher/presentation/student_detail_screen.dart';
import '../features/teacher/presentation/teacher_dashboard_screen.dart';
import '../features/teacher/presentation/teacher_profile_screen.dart';
import 'shell_scaffold.dart';

part 'router.g.dart';

const _publicRoutes = [
  '/splash',
  '/onboarding',
  '/role',
  '/login',
  '/register',
];

@riverpod
GoRouter router(Ref ref) {
  // Re-evaluate redirects when auth (or the student profile) changes.
  final notifier = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => notifier.value++);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      if (auth.isLoading || auth.hasError) return null;
      final AppUser? user = auth.value;
      final loc = state.matchedLocation;

      if (user == null) {
        return _publicRoutes.contains(loc) ? null : '/splash';
      }
      if (loc == '/splash' || (_publicRoutes.contains(loc))) {
        return user.homeRoute;
      }
      if (loc.startsWith('/student') && !user.isStudent) return user.homeRoute;
      if (loc.startsWith('/teacher') && !user.isTeacher) return user.homeRoute;
      if (loc.startsWith('/parent') && !user.isParent) return user.homeRoute;
      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.matchedLocation}')),
    ),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/role', builder: (_, _) => const ChooseRoleScreen()),
      GoRoute(
        path: '/login',
        builder: (_, state) =>
            LoginScreen(role: state.uri.queryParameters['role'] ?? 'student'),
      ),
      GoRoute(
        path: '/register',
        builder: (_, state) => RegisterScreen(
          role: state.uri.queryParameters['role'] ?? 'student',
        ),
      ),
      // ---- student setup (outside the tab shell) ----
      GoRoute(
        path: '/student/setup',
        builder: (_, _) => const LearningProfileScreen(),
      ),
      GoRoute(
        path: '/student/join',
        builder: (_, _) => const JoinClassroomScreen(),
      ),
      GoRoute(
        path: '/student/skill/:skillId',
        builder: (_, state) => SkillLessonScreen(
          skillId: state.pathParameters['skillId']!,
          materialId: state.uri.queryParameters['materialId'] ?? '',
          classroomId: state.uri.queryParameters['classroomId'],
          supplementary: state.uri.queryParameters['supplementary'] == 'true',
        ),
      ),
      GoRoute(
        path: '/student/practice',
        builder: (_, state) => PracticeScreen(
          mode: state.uri.queryParameters['mode'] ?? 'practice',
          classroomId: state.uri.queryParameters['classroomId'],
          materialId: state.uri.queryParameters['materialId'],
          skillId: state.uri.queryParameters['skillId'],
          supplementary: state.uri.queryParameters['supplementary'] == 'true',
        ),
      ),
      // ---- teacher detail ----
      GoRoute(
        path: '/teacher/classrooms/new',
        builder: (_, _) => const CreateClassroomScreen(),
      ),
      GoRoute(
        path: '/teacher/classrooms/:id',
        builder: (_, state) => ClassroomDetailScreen(
          classroomId: state.pathParameters['id']!,
          initialTab: state.uri.queryParameters['tab'] == 'materials' ? 1 : 0,
        ),
      ),
      GoRoute(
        path: '/teacher/materials/new',
        builder: (_, state) => MaterialUploadScreen(
          classroomId: state.uri.queryParameters['classroomId'],
        ),
      ),
      GoRoute(
        path: '/teacher/materials/:id',
        builder: (_, state) => MaterialDetailScreen(
          materialId: state.pathParameters['id']!,
          classroomId: state.uri.queryParameters['classroomId'],
        ),
      ),
      GoRoute(
        path: '/teacher/banks/:id',
        builder: (_, state) =>
            BankReviewScreen(bankId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/teacher/students/:classroomId/:studentId',
        builder: (_, state) => StudentDetailScreen(
          classroomId: state.pathParameters['classroomId']!,
          studentId: state.pathParameters['studentId']!,
        ),
      ),
      // ---- parent detail ----
      GoRoute(path: '/parent/link', builder: (_, _) => const LinkChildScreen()),
      GoRoute(
        path: '/parent/upload',
        builder: (_, state) => SupplementaryUploadScreen(
          childId: state.uri.queryParameters['childId'],
        ),
      ),
      GoRoute(
        path: '/parent/children/:id',
        builder: (_, state) =>
            ChildProgressScreen(childId: state.pathParameters['id']!),
      ),
      // ---- role shells (one StatefulShell per role, 4 tab branches each) ----
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) =>
            ScaffoldWithNavBar(navigationShell: shell, role: 'student'),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/student/home',
                builder: (_, _) => const StudentHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/student/learn',
                builder: (_, state) => LearnScreen(
                  classroomId: state.uri.queryParameters['classroomId'],
                  supplementary:
                      state.uri.queryParameters['supplementary'] == 'true',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/student/progress',
                builder: (_, _) => const StudentProgressScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/student/profile',
                builder: (_, _) => const StudentProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) =>
            ScaffoldWithNavBar(navigationShell: shell, role: 'teacher'),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/teacher/home',
                builder: (_, _) => const TeacherDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/teacher/classrooms',
                builder: (_, _) => const ClassroomsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/teacher/analytics',
                builder: (_, _) => const AnalyticsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/teacher/profile',
                builder: (_, _) => const TeacherProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) =>
            ScaffoldWithNavBar(navigationShell: shell, role: 'parent'),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/parent/home',
                builder: (_, _) => const ParentHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/parent/progress',
                builder: (_, state) => ChildProgressScreen(
                  childId: state.uri.queryParameters['childId'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/parent/materials',
                builder: (_, state) => ChildMaterialsScreen(
                  childId: state.uri.queryParameters['childId'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/parent/profile',
                builder: (_, _) => const ParentProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
