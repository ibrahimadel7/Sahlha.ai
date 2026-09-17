import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'secure_token_store.g.dart';

/// Auth token persistence (Keychain on iOS / Keystore on Android).
class SecureTokenStore {
  SecureTokenStore(this._storage);

  final FlutterSecureStorage _storage;
  static const _key = 'sahlha_auth_token';

  Future<String?> readToken() => _storage.read(key: _key);
  Future<void> writeToken(String token) =>
      _storage.write(key: _key, value: token);
  Future<void> clear() => _storage.delete(key: _key);
}

@riverpod
SecureTokenStore secureTokenStore(Ref ref) =>
    SecureTokenStore(const FlutterSecureStorage());
