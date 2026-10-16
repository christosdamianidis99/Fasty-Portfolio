import 'package:fasty/auth/auth_session.dart';
import 'package:fasty/auth/auth_token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('parses refresh session ID from login response', () {
    final session = AuthSession.fromLoginResponse(
      json: {
        'email': 'person@example.com',
        'accessToken': 'access-token',
        'accessTokenExpiresAt': '2026-07-30T18:00:00Z',
        'refreshToken': 'refresh-token',
        'refreshTokenExpiresAt': '2026-08-29T18:00:00Z',
        'refreshSessionId': '11111111-1111-1111-1111-111111111111',
      },
    );

    expect(session.refreshSessionId, '11111111-1111-1111-1111-111111111111');
  });

  test('rejects authentication response without email', () {
    expect(
      () => AuthSession.fromLoginResponse(
        json: {
          'accessToken': 'access-token',
          'accessTokenExpiresAt': '2026-07-30T18:00:00Z',
          'refreshToken': 'refresh-token',
          'refreshTokenExpiresAt': '2026-08-29T18:00:00Z',
          'refreshSessionId': '11111111-1111-1111-1111-111111111111',
        },
      ),
      throwsFormatException,
    );
  });

  test('rejects authentication response without session ID', () {
    expect(
      () => AuthSession.fromLoginResponse(
        json: {
          'email': 'person@example.com',
          'accessToken': 'access-token',
          'accessTokenExpiresAt': '2026-07-30T18:00:00Z',
          'refreshToken': 'refresh-token',
          'refreshTokenExpiresAt': '2026-08-29T18:00:00Z',
        },
      ),
      throwsFormatException,
    );
  });

  test('saves and reloads refresh session ID', () async {
    final store = AuthTokenStore();

    final session = AuthSession(
      email: 'person@example.com',
      accessToken: 'access-token',
      accessTokenExpiresAt: DateTime.parse('2026-07-30T18:00:00Z'),
      refreshToken: 'refresh-token',
      refreshTokenExpiresAt: DateTime.parse('2026-08-29T18:00:00Z'),
      refreshSessionId: '11111111-1111-1111-1111-111111111111',
    );

    await store.save(session);

    final loaded = await store.load();

    expect(loaded, isNotNull);
    expect(loaded!.refreshSessionId, session.refreshSessionId);
  });

  test('clears legacy stored session without session ID', () async {
    FlutterSecureStorage.setMockInitialValues({
      'fasty.auth.email': 'person@example.com',
      'fasty.auth.accessToken': 'access-token',
      'fasty.auth.accessTokenExpiresAt': '2026-07-30T18:00:00Z',
      'fasty.auth.refreshToken': 'refresh-token',
      'fasty.auth.refreshTokenExpiresAt': '2026-08-29T18:00:00Z',
    });

    final store = AuthTokenStore();

    final loaded = await store.load();

    expect(loaded, isNull);

    final storage = FlutterSecureStorage();

    expect(await storage.read(key: 'fasty.auth.email'), isNull);
    expect(await storage.read(key: 'fasty.auth.refreshToken'), isNull);
  });
}
