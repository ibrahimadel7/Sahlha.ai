import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sahlha/core/widgets/sahlha_widgets.dart';
import 'package:sahlha/features/classrooms/data/classroom_repository.dart';
import 'package:sahlha/features/materials/data/material_repository.dart';
import 'package:sahlha/features/materials/presentation/material_upload_screen.dart';
import 'package:sahlha/features/materials/presentation/upload_controller.dart';
import 'package:sahlha/features/parent/presentation/supplementary_upload_screen.dart';
import 'package:sahlha/features/parent/data/parent_repository.dart';
import 'package:sahlha/features/parent/domain/child_models.dart';

class PickedUpload extends UploadController {
  @override
  UploadState build() => UploadState(
    fileName: 'lesson.pdf',
    fileBytes: Uint8List.fromList([37, 80, 68, 70]),
  );
  @override
  void reset() {}
}

void main() {
  testWidgets('Browser PDF bytes enable parent uploads', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uploadControllerProvider.overrideWith(PickedUpload.new),
          linkedChildrenProvider.overrideWith(
            (ref) async => [const LinkedChild(id: 'child', name: 'Child')],
          ),
        ],
        child: const MaterialApp(
          home: SupplementaryUploadScreen(childId: 'child'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<SahlhaPrimaryButton>(
      find.byType(SahlhaPrimaryButton),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('Browser PDF bytes enable the teacher upload button', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uploadControllerProvider.overrideWith(PickedUpload.new),
          classroomListProvider.overrideWith(
            (ref) async => const [],
          ),
          materialListProvider.overrideWith(
            (ref, arg) async => const [],
          ),
        ],
        child: const MaterialApp(
          home: MaterialUploadScreen(classroomId: 'classroom'),
        ),
      ),
    );
    await tester.pump();
    final button = tester.widget<SahlhaPrimaryButton>(
      find.byType(SahlhaPrimaryButton),
    );
    expect(button.onPressed, isNotNull);
    expect(find.text('lesson.pdf'), findsOneWidget);
  });

  test(
    'Bytes are sent as multipart and failed processing stays retryable',
    () async {
      final dio = Dio();
      var calls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            final form = options.data as FormData;
            expect(form.files.single.value.filename, 'lesson.pdf');
            expect(form.files.single.value.length, 4);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 201,
                data: {
                  'material': {
                    'id': 'material',
                    'status': calls == 1 ? 'failed' : 'processed',
                    'status_detail': calls == 1 ? 'OCR unavailable' : '',
                  },
                },
              ),
            );
          },
        ),
      );
      final container = ProviderContainer(
        overrides: [
          uploadControllerProvider.overrideWith(PickedUpload.new),
          materialRepositoryProvider.overrideWithValue(MaterialRepository(dio)),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(uploadControllerProvider, (_, _) {});
      addTearDown(sub.close);
      final controller = container.read(uploadControllerProvider.notifier);
      await controller.upload(classroomId: 'classroom');
      expect(sub.read().uploading, isFalse);
      expect(sub.read().error, 'OCR unavailable');
      expect(sub.read().material, isNull);
      await controller.upload(classroomId: 'classroom');
      expect(sub.read().material?.status, 'processed');
      expect(sub.read().error, isNull);
    },
  );

  test('Unexpected response errors clear the upload spinner', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(requestOptions: options, statusCode: 201, data: 'invalid'),
          );
        },
      ),
    );
    final container = ProviderContainer(
      overrides: [
        uploadControllerProvider.overrideWith(PickedUpload.new),
        materialRepositoryProvider.overrideWithValue(MaterialRepository(dio)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(uploadControllerProvider, (_, _) {});
    addTearDown(sub.close);
    await container
        .read(uploadControllerProvider.notifier)
        .upload(classroomId: 'classroom');
    expect(sub.read().uploading, isFalse);
    expect(sub.read().error, isNotNull);
  });
}
