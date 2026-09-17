import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../teacher/domain/bank_models.dart';
import '../domain/material.dart';

part 'material_repository.g.dart';

/// Official classroom materials (teachers) and supplementary
/// materials (parents): upload, processing state, skills, banks.
class MaterialRepository {
  MaterialRepository(this._dio);

  final Dio _dio;

  Future<List<Material>> list({
    String? classroomId,
    String? childStudentId,
  }) async {
    try {
      final query = <String, dynamic>{};
      if (classroomId != null) query['classroom_id'] = classroomId;
      if (childStudentId != null) query['child_student_id'] = childStudentId;
      final res = await _dio.get<dynamic>('/materials', queryParameters: query);
      final items = (res.data as List? ?? []).cast<Map<String, dynamic>>();
      return items.map(Material.fromJson).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Material> get(String id) async {
    try {
      final res = await _dio.get<dynamic>('/materials/$id');
      return Material.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<GeneratedSkill>> skills(String id) async {
    try {
      final res = await _dio.get<dynamic>('/materials/$id/skills');
      final items = (res.data as List? ?? []).cast<Map<String, dynamic>>();
      return items.map(GeneratedSkill.fromJson).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<BankSummary>> banks(String id) async {
    try {
      final res = await _dio.get<dynamic>('/materials/$id/banks');
      final items = (res.data as List? ?? []).cast<Map<String, dynamic>>();
      return items.map(BankSummary.fromJson).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Material> upload({
    String? filePath,
    Uint8List? fileBytes,
    required String fileName,
    required String title,
    String? classroomId,
    String? childStudentId,
  }) async {
    assert(
      filePath != null || fileBytes != null,
      'Either filePath or fileBytes is required',
    );
    try {
      final fields = <String, dynamic>{'title': title};
      if (classroomId != null) fields['classroom_id'] = classroomId;
      if (childStudentId != null) fields['child_student_id'] = childStudentId;
      fields['file'] = filePath != null
          ? await MultipartFile.fromFile(filePath, filename: fileName)
          : MultipartFile.fromBytes(fileBytes!, filename: fileName);
      final form = FormData.fromMap(fields);
      final res = await _dio.post<dynamic>(
        '/materials/upload',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      final data = _asMap(res.data);
      // POST /materials/upload returns {"material": {...}, ...}.
      final material = data['material'];
      var uploaded = Material.fromJson(material is Map ? _asMap(material) : data);
      // Backend indexing finishes after upload; preserve the existing UI flow.
      for (var attempt = 0; attempt < 60 && uploaded.status == 'processing'; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        uploaded = await get(uploaded.id);
      }
      return uploaded;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> extractSkills(String materialId) async {
    try {
      await _dio.post<dynamic>('/materials/$materialId/extract-skills');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> generateBanks(String materialId) async {
    try {
      await _dio.post<dynamic>(
        '/materials/$materialId/generate-banks',
        data: <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> updateSkill(
    String materialId,
    String skillId, {
    String? name,
    String? description,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (description != null) data['description'] = description;
      await _dio.patch<dynamic>(
        '/materials/$materialId/skills/$skillId',
        data: data,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<GeneratedSkill> createSkill(
    String materialId, {
    required String skillId,
    required String name,
    String? description,
    List<String>? keyConcepts,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '/materials/$materialId/skills',
        data: {
          'skill_id': skillId,
          'name': name,
          if (description != null) 'description': description,
          if (keyConcepts != null) 'key_concepts': keyConcepts,
        },
      );
      return GeneratedSkill.fromJson(_asMap(res.data));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> deleteSkill(String materialId, String skillId) async {
    try {
      await _dio.delete<dynamic>('/materials/$materialId/skills/$skillId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

Map<String, dynamic> _asMap(dynamic data) =>
    Map<String, dynamic>.from(data as Map);

@riverpod
MaterialRepository materialRepository(Ref ref) =>
    MaterialRepository(ref.watch(apiClientProvider).dio);

/// Materials for one classroom (teacher view).
@riverpod
Future<List<Material>> materialList(
  Ref ref, {
  String? classroomId,
  String? childStudentId,
}) => ref
    .watch(materialRepositoryProvider)
    .list(classroomId: classroomId, childStudentId: childStudentId);

/// AI-extracted skills for one material.
@riverpod
Future<List<GeneratedSkill>> materialSkills(Ref ref, String materialId) =>
    ref.watch(materialRepositoryProvider).skills(materialId);
