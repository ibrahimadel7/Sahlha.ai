import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../api/api_client.dart';
import '../storage/secure_token_store.dart';

part 'auth_controller.g.dart';

/// App-wide authentication state. Holds the signed-in user (or null) and
/// keeps the API token in secure storage + the Dio client in sync.
@riverpod
class AuthController extends _$AuthController {
  @override
  Future<AppUser?> build() async {
    final store = ref.watch(secureTokenStoreProvider);
    final token = await store.readToken();
    if (token == null || token.isEmpty) return null;
    ref.read(apiClientProvider).setToken(token);
    try {
      return await ref.read(authRepositoryProvider).me();
    } catch (_) {
      await store.clear();
      ref.read(apiClientProvider).clearToken();
      return null;
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await ref
          .read(authRepositoryProvider)
          .login(email: email, password: password);
      await ref.read(secureTokenStoreProvider).writeToken(result.token);
      ref.read(apiClientProvider).setToken(result.token);
      return result.user;
    });
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await ref
          .read(authRepositoryProvider)
          .register(name: name, email: email, password: password, role: role);
      await ref.read(secureTokenStoreProvider).writeToken(result.token);
      ref.read(apiClientProvider).setToken(result.token);
      return result.user;
    });
  }

  Future<void> logout() async {
    await ref.read(secureTokenStoreProvider).clear();
    ref.read(apiClientProvider).clearToken();
    state = const AsyncData(null);
  }

  /// Server said 401: drop local auth state so the router returns to login.
  Future<void> handleUnauthorized() async {
    await ref.read(secureTokenStoreProvider).clear();
    ref.read(apiClientProvider).clearToken();
    state = const AsyncData(null);
  }

  Future<void> updateName(String name) async {
    final updated = await ref.read(authRepositoryProvider).updateName(name);
    state = AsyncData(updated);
  }
}

/// Convenience: the signed-in user (null when signed out).
@riverpod
AppUser? currentUser(Ref ref) => ref.watch(authControllerProvider).value;
