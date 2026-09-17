import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sahlha/core/api/api_exception.dart';
import 'package:sahlha/features/materials/data/material_repository.dart';
import 'package:sahlha/features/materials/domain/material.dart' as models;
import 'package:sahlha/features/materials/presentation/material_detail_screen.dart';
import 'package:sahlha/features/materials/presentation/material_upload_screen.dart';
import 'package:sahlha/features/materials/presentation/upload_controller.dart';
import 'package:sahlha/features/teacher/domain/bank_models.dart';

class NavigationMaterials extends MaterialRepository {
  NavigationMaterials({this.fail = false}) : super(Dio());
  final bool fail;

  @override
  Future<models.Material> get(String id) async {
    if (fail) throw const ApiException('Material not found');
    return models.Material(id: id, classroomId: 'room', status: 'processed');
  }

  @override
  Future<List<models.GeneratedSkill>> skills(String id) async => [];
  @override
  Future<List<BankSummary>> banks(String id) async => [];
  @override
  Future<models.Material> upload({
    String? filePath,
    Uint8List? fileBytes,
    required String fileName,
    required String title,
    String? classroomId,
    String? childStudentId,
  }) async => get('lesson');
}

class SelectedFile extends UploadController {
  @override
  UploadState build() =>
      UploadState(fileName: 'lesson.pdf', fileBytes: Uint8List.fromList([1]));
  @override
  void reset() {}
}

GoRouter navigationRouter(String location) => GoRouter(
  initialLocation: location,
  routes: [
    GoRoute(
      path: '/teacher/classrooms',
      builder: (_, _) => const Scaffold(body: Text('Classroom list')),
    ),
    GoRoute(
      path: '/teacher/classrooms/:id',
      builder: (context, state) => Scaffold(
        body: Column(
          children: [
            const Text('Classroom destination'),
            TextButton(
              onPressed: () => context.push('/teacher/materials/new'),
              child: const Text('Upload a material'),
            ),
            TextButton(
              onPressed: () => context.push('/teacher/materials/lesson'),
              child: const Text('Open material'),
            ),
          ],
        ),
      ),
    ),
    GoRoute(
      path: '/teacher/materials/new',
      builder: (_, _) => const MaterialUploadScreen(classroomId: 'room'),
    ),
    GoRoute(
      path: '/teacher/materials/:id',
      builder: (_, state) => MaterialDetailScreen(
        materialId: state.pathParameters['id']!,
        classroomId: state.uri.queryParameters['classroomId'],
      ),
    ),
  ],
);

Future<GoRouter> mountApp(
  WidgetTester tester,
  String location, {
  bool fail = false,
}) async {
  final router = navigationRouter(location);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        materialRepositoryProvider.overrideWithValue(
          NavigationMaterials(fail: fail),
        ),
        uploadControllerProvider.overrideWith(SelectedFile.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('Direct material link returns to its classroom Materials tab', (
    tester,
  ) async {
    final router = await mountApp(tester, '/teacher/materials/lesson');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/teacher/classrooms/room?tab=materials',
    );
  });

  testWidgets('Missing material still has a route to the classroom list', (
    tester,
  ) async {
    final router = await mountApp(
      tester,
      '/teacher/materials/missing',
      fail: true,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/teacher/classrooms',
    );
  });

  testWidgets('Opening an existing material preserves the previous classroom', (
    tester,
  ) async {
    final router = await mountApp(tester, '/teacher/classrooms/room');
    await tester.tap(find.text('Open material'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/teacher/classrooms/room',
    );
  });

  testWidgets(
    'Successful upload replaces the form and keeps the classroom beneath it',
    (tester) async {
      final router = await mountApp(tester, '/teacher/classrooms/room');
      await tester.tap(find.text('Upload a material'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Upload and process'));
      await tester.tap(find.text('Upload and process'));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialDetailScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/teacher/classrooms/room',
      );
      expect(find.byType(MaterialUploadScreen), findsNothing);
    },
  );
}
