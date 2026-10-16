import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_session.dart';

class AuthTokenStore {
  AuthTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _emailKey = 'fasty.auth.email';
  static const _accessTokenKey = 'fasty.auth.accessToken';
  static const _accessTokenExpiryKey = 'fasty.auth.accessTokenExpiresAt';
  static const _refreshTokenKey = 'fasty.auth.refreshToken';
  static const _refreshTokenExpiryKey = 'fasty.auth.refreshTokenExpiresAt';
  static const _refreshSessionIdKey = 'fasty.auth.refreshSessionId';

  final FlutterSecureStorage _storage;

  Future<void> save(AuthSession session) async {
    await Future.wait([
      _storage.write(key: _emailKey, value: session.email),
      _storage.write(key: _accessTokenKey, value: session.accessToken),
      _storage.write(
        key: _accessTokenExpiryKey,
        value: session.accessTokenExpiresAt.toUtc().toIso8601String(),
      ),
      _storage.write(key: _refreshTokenKey, value: session.refreshToken),
      _storage.write(
        key: _refreshTokenExpiryKey,
        value: session.refreshTokenExpiresAt.toUtc().toIso8601String(),
      ),
      _storage.write(
        key: _refreshSessionIdKey,
        value: session.refreshSessionId,
      ),
    ]);
  }

  Future<AuthSession?> load() async {
    final values = await Future.wait([
      _storage.read(key: _emailKey),
      _storage.read(key: _accessTokenKey),
      _storage.read(key: _accessTokenExpiryKey),
      _storage.read(key: _refreshTokenKey),
      _storage.read(key: _refreshTokenExpiryKey),
      _storage.read(key: _refreshSessionIdKey),
    ]);

    if (values.any((value) => value == null || value.trim().isEmpty)) {
      await clear();
      return null;
    }

    try {
      return AuthSession(
        email: values[0]!,
        accessToken: values[1]!,
        accessTokenExpiresAt: DateTime.parse(values[2]!).toUtc(),
        refreshToken: values[3]!,
        refreshTokenExpiresAt: DateTime.parse(values[4]!).toUtc(),
        refreshSessionId: values[5]!,
      );
    } on FormatException {
      await clear();
      return null;
    }
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _emailKey),
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _accessTokenExpiryKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _refreshTokenExpiryKey),
      _storage.delete(key: _refreshSessionIdKey),
    ]);
  }
}
