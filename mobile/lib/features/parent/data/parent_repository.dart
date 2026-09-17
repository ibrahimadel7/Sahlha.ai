import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../materials/domain/material.dart';
import '../domain/child_models.dart';

part 'parent_repository.g.dart';

/// Parent APIs: linked children, child progress/materials, linking.
class ParentRepository {
  ParentRepository(this._dio);

  final Dio _dio;

  Future<List<LinkedChild>> children() async {
    try {
      final res = await _dio.get<dynamic>('/parent/children');
      final items = (res.data as List? ?? []).cast<Map<String, dynamic>>();
      return items.map(LinkedChild.fromJson).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> linkChild(String code) async {
    try {
      await _dio.post<dynamic>(
        '/parent/link-child',
        data: {'link_code': code.trim().toUpperCase()},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> childProgress(String childId) async {
    try {
      final res = await _dio.get<dynamic>('/parent/children/$childId/progress');
      return _asMap(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<Material>> childMaterials(String childId) async {
    try {
      final res = await _dio.get<dynamic>(
        '/parent/children/$childId/materials',
      );
      final items = (res.data as List? ?? []).cast<Map<String, dynamic>>();
      return items.map(Material.fromJson).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

Map<String, dynamic> _asMap(dynamic data) =>
    Map<String, dynamic>.from(data as Map);

@riverpod
ParentRepository parentRepository(Ref ref) =>
    ParentRepository(ref.watch(apiClientProvider).dio);

/// Children linked to the signed-in parent.
@riverpod
Future<List<LinkedChild>> linkedChildren(Ref ref) =>
    ref.watch(parentRepositoryProvider).children();

/// Currently selected child (defaults to the first linked child).
@riverpod
class SelectedChild extends _$SelectedChild {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

/// Progress of the currently selected child.
@riverpod
Future<Map<String, dynamic>> selectedChildProgress(Ref ref) async {
  final children = await ref.watch(linkedChildrenProvider.future);
  if (children.isEmpty) return {'classrooms': []};
  final selected = ref.watch(selectedChildProvider) ?? children.first.id;
  return ref.watch(parentRepositoryProvider).childProgress(selected);
}
