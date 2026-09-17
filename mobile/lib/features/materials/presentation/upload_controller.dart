import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_exception.dart';
import '../data/material_repository.dart';
import '../domain/material.dart';

part 'upload_controller.freezed.dart';
part 'upload_controller.g.dart';

@freezed
abstract class UploadState with _$UploadState {
  const factory UploadState({
    @Default(false) bool picking,
    String? fileName,
    String? filePath,
    // In-memory bytes when the picked file has no local path.
    Uint8List? fileBytes,
    @Default(false) bool uploading,
    Material? material,
    String? error,
    @Default(false) bool extracting,
    @Default(false) bool generating,
    @Default('') String step,
  }) = _UploadState;
}

@riverpod
class UploadController extends _$UploadController {
  @override
  UploadState build() => const UploadState();

  Future<void> pickFile() async {
    if (state.picking ||
        state.uploading ||
        state.extracting ||
        state.generating) {
      return;
    }
    state = state.copyWith(picking: true, error: null);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'docx',
          'pptx',
          'txt',
          'md',
          'png',
          'jpg',
          'jpeg',
        ],
      );
      if (!ref.mounted) return;
      if (file == null) {
        // User cancelled the picker.
        state = state.copyWith(picking: false);
        return;
      }
      final size = await file.length();
      if (!ref.mounted) return;
      if (size != null && (size <= 0 || size > 25 * 1024 * 1024)) {
        state = state.copyWith(
          picking: false,
          error: size <= 0
              ? 'The file is empty.'
              : 'File is larger than 25 MB.',
        );
        return;
      }
      final path = kIsWeb ? null : file.path;
      if (path != null) {
        state = state.copyWith(
          picking: false,
          material: null,
          fileName: file.name,
          filePath: path,
          fileBytes: null,
        );
      } else {
        // No local path (e.g. content URI): keep the bytes in memory.
        final bytes = await file.readAsBytes();
        if (!ref.mounted) return;
        if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) {
          state = state.copyWith(
            picking: false,
            error: bytes.isEmpty
                ? 'The file is empty.'
                : 'File is larger than 25 MB.',
          );
          return;
        }
        state = state.copyWith(
          picking: false,
          material: null,
          fileName: file.name,
          filePath: null,
          fileBytes: bytes,
        );
      }
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(
        picking: false,
        error: 'Could not open the file picker.',
      );
    }
  }

  Future<void> upload({
    String title = '',
    String? classroomId,
    String? childStudentId,
  }) async {
    if (state.picking ||
        state.uploading ||
        state.extracting ||
        state.generating) {
      return;
    }
    final path = state.filePath;
    final bytes = state.fileBytes;
    final name = state.fileName;
    if (name == null || (path == null && bytes == null)) {
      state = state.copyWith(error: 'Choose a file first.');
      return;
    }
    state = state.copyWith(uploading: true, error: null, step: 'Uploading…');
    try {
      final material = await ref
          .read(materialRepositoryProvider)
          .upload(
            filePath: path,
            fileBytes: bytes,
            fileName: name,
            title: title.isEmpty ? name : title,
            classroomId: classroomId,
            childStudentId: childStudentId,
          );
      if (!ref.mounted) return;
      if (material.isFailed) {
        state = state.copyWith(
          uploading: false,
          step: '',
          error: material.statusDetail.isEmpty
              ? 'Could not process this file.'
              : material.statusDetail,
        );
        ref.invalidate(materialListProvider);
        return;
      }
      state = state.copyWith(uploading: false, material: material, step: '');
      ref.invalidate(materialListProvider);
    } catch (e) {
      if (!ref.mounted) return;
      final error = e is ApiException ? e : ApiException.fromDio(e);
      state = state.copyWith(uploading: false, error: error.message, step: '');
    }
  }

  Future<void> extractSkills(String materialId) async {
    if (state.uploading || state.extracting || state.generating) return;
    state = state.copyWith(
      extracting: true,
      error: null,
      step: 'Finding learning skills…',
    );
    try {
      await ref.read(materialRepositoryProvider).extractSkills(materialId);
      if (!ref.mounted) return;
      final material = await ref
          .read(materialRepositoryProvider)
          .get(materialId);
      if (!ref.mounted) return;
      state = state.copyWith(extracting: false, material: material, step: '');
      ref.invalidate(materialSkillsProvider);
      ref.invalidate(materialListProvider);
    } catch (e) {
      if (!ref.mounted) return;
      final error = e is ApiException ? e : ApiException.fromDio(e);
      state = state.copyWith(extracting: false, error: error.message, step: '');
    }
  }

  Future<void> generateBanks(String materialId) async {
    if (state.uploading || state.extracting || state.generating) return;
    state = state.copyWith(
      generating: true,
      error: null,
      step: 'Generating practice…',
    );
    try {
      await ref.read(materialRepositoryProvider).generateBanks(materialId);
      if (!ref.mounted) return;
      final material = await ref
          .read(materialRepositoryProvider)
          .get(materialId);
      if (!ref.mounted) return;
      state = state.copyWith(generating: false, material: material, step: '');
      ref.invalidate(materialListProvider);
    } catch (e) {
      if (!ref.mounted) return;
      final error = e is ApiException ? e : ApiException.fromDio(e);
      state = state.copyWith(generating: false, error: error.message, step: '');
    }
  }

  void reset() => state = const UploadState();
}
