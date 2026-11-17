import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores OpenCode session cookies outside SQLite.
abstract class TokenStore {
  Future<String?> read(int accountId);
  Future<void> write(int accountId, String token);
  Future<void> delete(int accountId);
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(int accountId) => 'quotaroom_token_$accountId';

  @override
  Future<String?> read(int accountId) async {
    try {
      final value = await _storage.read(key: _key(accountId));
      if (value == null || value.trim().isEmpty) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(int accountId, String token) async {
    await _storage.write(key: _key(accountId), value: token);
  }

  @override
  Future<void> delete(int accountId) async {
    try {
      await _storage.delete(key: _key(accountId));
    } catch (_) {
      // A broken keystore entry should not block account deletion.
    }
  }
}

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([Map<int, String>? initial])
    : _tokens = {...?initial};

  final Map<int, String> _tokens;

  @override
  Future<String?> read(int accountId) async => _tokens[accountId];

  @override
  Future<void> write(int accountId, String token) async {
    _tokens[accountId] = token;
  }

  @override
  Future<void> delete(int accountId) async {
    _tokens.remove(accountId);
  }
}
