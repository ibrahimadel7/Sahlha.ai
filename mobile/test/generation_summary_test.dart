import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/features/materials/data/material_repository.dart';
import 'package:sahlha/features/materials/domain/material.dart' as models;
import 'package:sahlha/features/materials/presentation/upload_controller.dart';

import 'material_navigation_test.dart'
    show NavigationMaterials, SelectedFile, navigationRouter;

const summary =
    'Created 14 questions for review. Some skills have fewer questions. '
    'No questions for: function list. Re-extract skills or add more lesson content.';

class PartialMaterials extends NavigationMaterials {
  @override
  Future<models.Material> get(String id) async => models.Material(
    id: id,
    classroomId: 'room',
    status: 'banks_ready',
    statusDetail: summary,
  );
}

void main() {
  testWidgets(
    'Teacher can inspect partial generation results on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = navigationRouter('/teacher/materials/lesson');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            materialRepositoryProvider.overrideWithValue(PartialMaterials()),
            uploadControllerProvider.overrideWith(SelectedFile.new),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Question generation summary'));
      await tester.pumpAndSettle();
      expect(find.text(summary), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
