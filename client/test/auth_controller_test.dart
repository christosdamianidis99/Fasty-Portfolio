import 'dart:convert';

import 'package:fasty/auth/auth_api.dart';
import 'package:fasty/auth/auth_controller.dart';
import 'package:fasty/auth/auth_token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('googleLogin saves backend session', () async {
    final store = AuthTokenStore();
    final controller = AuthController(
      api: AuthApi(
        baseUrl: 'http://fasty.test',
        client: MockClient((request) async {
          expect(request.url.path, '/api/auth/google');
          expect(jsonDecode(request.body), {
            'idToken': 'google-token',
            'deviceName': 'Laptop',
          });
          return http.Response(jsonEncode(_googleSessionResponse), 200);
        }),
      ),
      tokenStore: store,
    );

    expect(
      await controller.googleLogin(
        idToken: 'google-token',
        deviceName: 'Laptop',
      ),
      isTrue,
    );
    expect(controller.isSignedIn, isTrue);
    expect(controller.email, 'google@example.com');
    expect(controller.isBusy, isFalse);
    expect((await store.load())?.email, 'google@example.com');
    controller.dispose();
  });

  test('Google session survives controller restart', () async {
    final store = AuthTokenStore();
    final api = AuthApi(
      baseUrl: 'http://fasty.test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/auth/google');
        return http.Response(jsonEncode(_googleSessionResponse), 200);
      }),
    );
    final first = AuthController(api: api, tokenStore: store);
    expect(
      await first.googleLogin(idToken: 'google-token', deviceName: 'Laptop'),
      isTrue,
    );
    first.dispose();

    final restarted = AuthController(api: api, tokenStore: AuthTokenStore());
    await restarted.initialize();
    expect(restarted.isSignedIn, isTrue);
    expect(restarted.email, 'google@example.com');
    restarted.dispose();
  });

  test('restored session fetches authoritative Google link status', () async {
    FlutterSecureStorage.setMockInitialValues(_storedGoogleSession);
    var statusRequests = 0;
    final controller = AuthController(
      api: AuthApi(
        baseUrl: 'http://fasty.test',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/auth/google/link');
          expect(request.headers['authorization'], 'Bearer access-token');
          statusRequests++;
          return http.Response(jsonEncode({'linked': true}), 200);
        }),
      ),
      tokenStore: AuthTokenStore(),
    );

    await controller.initialize();
    expect(controller.isSignedIn, isTrue);
    expect(controller.googleLinked, isTrue);
    await controller.refreshGoogleLinkStatus();
    expect(statusRequests, 2);
    expect(controller.googleLinked, isTrue);
    controller.dispose();
  });

  test(
    'password login fetches Google link status for existing account',
    () async {
      var statusRequests = 0;
      final controller = AuthController(
        api: AuthApi(
          baseUrl: 'http://fasty.test',
          client: MockClient((request) async {
            if (request.url.path == '/api/auth/login') {
              return http.Response(jsonEncode(_googleSessionResponse), 200);
            }
            expect(request.url.path, '/api/auth/google/link');
            expect(request.headers['authorization'], 'Bearer access-token');
            statusRequests++;
            return http.Response(jsonEncode({'linked': true}), 200);
          }),
        ),
        tokenStore: AuthTokenStore(),
      );

      expect(
        await controller.login(
          email: 'google@example.com',
          password: 'password',
          deviceName: 'Laptop',
        ),
        isTrue,
      );
      expect(statusRequests, 1);
      expect(controller.googleLinked, isTrue);
      controller.dispose();
    },
  );

  test('googleLogin exposes account link required code', () async {
    final store = AuthTokenStore();
    final controller = AuthController(
      api: AuthApi(
        baseUrl: 'http://fasty.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 'account_link_required',
              'detail': 'Sign in first, then link Google.',
            }),
            409,
          ),
        ),
      ),
      tokenStore: store,
    );

    expect(
      await controller.googleLogin(
        idToken: 'google-token',
        deviceName: 'Laptop',
      ),
      isFalse,
    );
    expect(controller.errorCode, 'account_link_required');
    expect(controller.errorMessage, 'Sign in first, then link Google.');
    expect(controller.isSignedIn, isFalse);
    expect(await store.load(), isNull);
    controller.clearFeedback();
    expect(controller.errorCode, isNull);
    expect(controller.errorMessage, isNull);
    controller.dispose();
  });

  test('linkGoogle uses access token and preserves session', () async {
    FlutterSecureStorage.setMockInitialValues(_storedGoogleSession);
    final store = AuthTokenStore();
    final controller = AuthController(
      api: AuthApi(
        baseUrl: 'http://fasty.test',
        client: MockClient((request) async {
          expect(request.url.path, '/api/auth/google/link');
          expect(request.headers['authorization'], 'Bearer access-token');
          expect(jsonDecode(request.body), {'idToken': 'google-token'});
          return http.Response(
            jsonEncode({'message': 'Google account linked successfully.'}),
            200,
          );
        }),
      ),
      tokenStore: store,
    );
    await controller.initialize();

    expect(await controller.linkGoogle(idToken: 'google-token'), isTrue);
    expect(controller.message, 'Google account linked successfully.');
    expect(controller.isSignedIn, isTrue);
    expect((await store.load())?.accessToken, 'access-token');
    controller.dispose();
  });

  test('linkGoogle keeps session after backend conflict', () async {
    FlutterSecureStorage.setMockInitialValues(_storedGoogleSession);
    final store = AuthTokenStore();
    final controller = AuthController(
      api: AuthApi(
        baseUrl: 'http://fasty.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'Google email does not match.'}),
            409,
          ),
        ),
      ),
      tokenStore: store,
    );
    await controller.initialize();

    expect(await controller.linkGoogle(idToken: 'google-token'), isFalse);
    expect(controller.errorMessage, 'Google email does not match.');
    expect(controller.isSignedIn, isTrue);
    expect(await store.load(), isNotNull);
    controller.dispose();
  });

  test('linkGoogle requires signed-in session', () async {
    final controller = AuthController(
      api: AuthApi(
        baseUrl: 'http://fasty.test',
        client: MockClient((_) async {
          fail('Unexpected link request.');
        }),
      ),
      tokenStore: AuthTokenStore(),
    );
    await controller.initialize();

    expect(await controller.linkGoogle(idToken: 'google-token'), isFalse);
    expect(
      controller.errorMessage,
      'The authenticated session is no longer valid.',
    );
    controller.dispose();
  });

  test('register stores successful informational message', () async {
    final client = MockClient((request) async {
      expect(request.url, Uri.parse('http://fasty.test/api/auth/register'));

      return http.Response(
        jsonEncode({
          'message':
              'If this email can be registered, '
              'a verification message will be sent.',
        }),
        202,
        headers: const {'content-type': 'application/json'},
      );
    });

    final controller = AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: AuthTokenStore(),
    );

    final succeeded = await controller.register(
      email: 'person@example.com',
      password: 'StrongPassword123!',
    );

    expect(succeeded, isTrue);
    expect(controller.isBusy, isFalse);
    expect(controller.errorMessage, isNull);
    expect(
      controller.message,
      'If this email can be registered, '
      'a verification message will be sent.',
    );

    controller.dispose();
  });

  test('confirmEmail stores backend error message', () async {
    final client = MockClient((request) async {
      expect(
        request.url,
        Uri.parse('http://fasty.test/api/auth/confirm-email'),
      );

      return http.Response(
        jsonEncode({
          'message': 'The confirmation request is invalid or expired.',
        }),
        400,
        headers: const {'content-type': 'application/json'},
      );
    });

    final controller = AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: AuthTokenStore(),
    );

    final succeeded = await controller.confirmEmail(
      email: 'person@example.com',
      token: 'invalid-token',
    );

    expect(succeeded, isFalse);
    expect(controller.isBusy, isFalse);
    expect(controller.message, isNull);
    expect(
      controller.errorMessage,
      'The confirmation request is invalid or expired.',
    );

    controller.dispose();
  });

  test('forgotPassword stores generic success message', () async {
    final client = MockClient((request) async {
      expect(
        request.url,
        Uri.parse('http://fasty.test/api/auth/forgot-password'),
      );

      return http.Response(
        jsonEncode({
          'message':
              'If the account can be recovered, '
              'a password reset message will be sent.',
        }),
        202,
        headers: const {'content-type': 'application/json'},
      );
    });

    final controller = AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: AuthTokenStore(),
    );

    final succeeded = await controller.forgotPassword(
      email: 'person@example.com',
    );

    expect(succeeded, isTrue);
    expect(controller.isBusy, isFalse);
    expect(controller.errorMessage, isNull);
    expect(
      controller.message,
      'If the account can be recovered, '
      'a password reset message will be sent.',
    );

    controller.dispose();
  });

  test('recovery credential redemption stores success message', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'message':
              'Password reset successfully. '
              'Sign in with your new password.',
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final controller = AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: AuthTokenStore(),
    );

    final succeeded = await controller.redeemPasswordRecoveryCredential(
      email: 'person@example.com',
      recoveryCredential: 'temporary-credential',
      newPassword: 'Replacement456!',
    );

    expect(succeeded, isTrue);
    expect(controller.errorMessage, isNull);
    expect(
      controller.message,
      'Password reset successfully. '
      'Sign in with your new password.',
    );

    controller.dispose();
  });
  test('resetPassword stores backend error message', () async {
    final client = MockClient((request) async {
      expect(
        request.url,
        Uri.parse('http://fasty.test/api/auth/reset-password'),
      );

      return http.Response(
        jsonEncode({
          'message': 'The password reset request is invalid or expired.',
        }),
        400,
        headers: const {'content-type': 'application/json'},
      );
    });

    final controller = AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: AuthTokenStore(),
    );

    final succeeded = await controller.resetPassword(
      email: 'person@example.com',
      token: 'invalid-token',
      newPassword: 'Replacement456!',
    );

    expect(succeeded, isFalse);
    expect(controller.isBusy, isFalse);
    expect(controller.message, isNull);
    expect(
      controller.errorMessage,
      'The password reset request is invalid or expired.',
    );

    controller.dispose();
  });

  test('changePassword signs out locally after success', () async {
    final now = DateTime.now().toUtc();

    FlutterSecureStorage.setMockInitialValues({
      'fasty.auth.email': 'person@example.com',
      'fasty.auth.accessToken': 'access-token',
      'fasty.auth.accessTokenExpiresAt': now
          .add(const Duration(minutes: 10))
          .toIso8601String(),
      'fasty.auth.refreshToken': 'refresh-token',
      'fasty.auth.refreshTokenExpiresAt': now
          .add(const Duration(days: 7))
          .toIso8601String(),
      'fasty.auth.refreshSessionId': '11111111-1111-1111-1111-111111111111',
    });

    final client = MockClient((request) async {
      expect(
        request.url,
        Uri.parse('http://fasty.test/api/auth/change-password'),
      );
      expect(request.headers['authorization'], 'Bearer access-token');
      expect(jsonDecode(request.body), {
        'currentPassword': 'StrongPassword123!',
        'newPassword': 'Replacement456!',
      });

      return http.Response(
        jsonEncode({
          'message':
              'Password changed successfully. '
              'Sign in again with your new password.',
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final tokenStore = AuthTokenStore();
    final controller = AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: tokenStore,
    );

    await controller.initialize();

    expect(controller.isSignedIn, isTrue);

    final succeeded = await controller.changePassword(
      currentPassword: 'StrongPassword123!',
      newPassword: 'Replacement456!',
    );

    expect(succeeded, isTrue);
    expect(controller.isBusy, isFalse);
    expect(controller.isSignedIn, isFalse);
    expect(controller.session, isNull);
    expect(controller.errorMessage, isNull);
    expect(
      controller.message,
      'Password changed successfully. '
      'Sign in again with your new password.',
    );
    expect(await tokenStore.load(), isNull);

    controller.dispose();
  });

  test('changePassword keeps session after backend failure', () async {
    final now = DateTime.now().toUtc();

    FlutterSecureStorage.setMockInitialValues({
      'fasty.auth.email': 'person@example.com',
      'fasty.auth.accessToken': 'access-token',
      'fasty.auth.accessTokenExpiresAt': now
          .add(const Duration(minutes: 10))
          .toIso8601String(),
      'fasty.auth.refreshToken': 'refresh-token',
      'fasty.auth.refreshTokenExpiresAt': now
          .add(const Duration(days: 7))
          .toIso8601String(),
      'fasty.auth.refreshSessionId': '11111111-1111-1111-1111-111111111111',
    });

    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'The current password is incorrect.'}),
        400,
        headers: const {'content-type': 'application/json'},
      );
    });

    final tokenStore = AuthTokenStore();
    final controller = AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: tokenStore,
    );

    await controller.initialize();

    final succeeded = await controller.changePassword(
      currentPassword: 'WrongPassword123!',
      newPassword: 'Replacement456!',
    );

    expect(succeeded, isFalse);
    expect(controller.isBusy, isFalse);
    expect(controller.isSignedIn, isTrue);
    expect(controller.session, isNotNull);
    expect(controller.message, isNull);
    expect(controller.errorMessage, 'The current password is incorrect.');
    expect(await tokenStore.load(), isNotNull);

    controller.dispose();
  });

  test('listSessions keeps the current local session', () async {
    final now = DateTime.now().toUtc();

    FlutterSecureStorage.setMockInitialValues({
      'fasty.auth.email': 'person@example.com',
      'fasty.auth.accessToken': 'access-token',
      'fasty.auth.accessTokenExpiresAt': now
          .add(const Duration(minutes: 10))
          .toIso8601String(),
      'fasty.auth.refreshToken': 'refresh-token',
      'fasty.auth.refreshTokenExpiresAt': now
          .add(const Duration(days: 7))
          .toIso8601String(),
      'fasty.auth.refreshSessionId': '11111111-1111-1111-1111-111111111111',
    });

    final client = MockClient((request) async {
      expect(request.url, Uri.parse('http://fasty.test/api/auth/sessions'));
      expect(request.method, 'GET');
      expect(request.headers['authorization'], 'Bearer access-token');

      return http.Response(
        jsonEncode([
          {
            'id': '11111111-1111-1111-1111-111111111111',
            'deviceName': 'Current device',
            'createdAt': '2026-07-30T10:00:00Z',
            'lastUsedAt': null,
            'expiresAt': '2026-08-29T10:00:00Z',
          },
        ]),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final tokenStore = AuthTokenStore();
    final controller = AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: tokenStore,
    );

    await controller.initialize();

    final sessions = await controller.listSessions();

    expect(sessions, hasLength(1));
    expect(controller.isSignedIn, isTrue);
    expect(controller.session, isNotNull);
    expect(await tokenStore.load(), isNotNull);
    expect(controller.errorMessage, isNull);

    controller.dispose();
  });

  test('revokeSession keeps local login for another device', () async {
    final now = DateTime.now().toUtc();

    FlutterSecureStorage.setMockInitialValues({
      'fasty.auth.email': 'person@example.com',
      'fasty.auth.accessToken': 'access-token',
      'fasty.auth.accessTokenExpiresAt': now
          .add(const Duration(minutes: 10))
          .toIso8601String(),
      'fasty.auth.refreshToken': 'refresh-token',
      'fasty.auth.refreshTokenExpiresAt': now
          .add(const Duration(days: 7))
          .toIso8601String(),
      'fasty.auth.refreshSessionId': '11111111-1111-1111-1111-111111111111',
    });

    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(
        request.url,
        Uri.parse(
          'http://fasty.test/api/auth/sessions/'
          '22222222-2222-2222-2222-222222222222',
        ),
      );

      return http.Response('', 204);
    });

    final tokenStore = AuthTokenStore();
    final controller = AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: tokenStore,
    );

    await controller.initialize();

    final succeeded = await controller.revokeSession(
      '22222222-2222-2222-2222-222222222222',
    );

    expect(succeeded, isTrue);
    expect(controller.isSignedIn, isTrue);
    expect(controller.session, isNotNull);
    expect(await tokenStore.load(), isNotNull);
    expect(controller.errorMessage, isNull);

    controller.dispose();
  });

  test('revokeSession signs out when revoking current session', () async {
    final now = DateTime.now().toUtc();

    FlutterSecureStorage.setMockInitialValues({
      'fasty.auth.email': 'person@example.com',
      'fasty.auth.accessToken': 'access-token',
      'fasty.auth.accessTokenExpiresAt': now
          .add(const Duration(minutes: 10))
          .toIso8601String(),
      'fasty.auth.refreshToken': 'refresh-token',
      'fasty.auth.refreshTokenExpiresAt': now
          .add(const Duration(days: 7))
          .toIso8601String(),
      'fasty.auth.refreshSessionId': '11111111-1111-1111-1111-111111111111',
    });

    final client = MockClient((request) async {
      expect(request.method, 'DELETE');

      return http.Response('', 204);
    });

    final tokenStore = AuthTokenStore();
    final controller = AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: tokenStore,
    );

    await controller.initialize();

    final succeeded = await controller.revokeSession(
      '11111111-1111-1111-1111-111111111111',
    );

    expect(succeeded, isTrue);
    expect(controller.isSignedIn, isFalse);
    expect(controller.session, isNull);
    expect(await tokenStore.load(), isNull);
    expect(controller.errorMessage, isNull);

    controller.dispose();
  });
  test('transient refresh connection failure keeps stored login', () async {
    final now = DateTime.now().toUtc();

    FlutterSecureStorage.setMockInitialValues({
      'fasty.auth.email': 'person@example.com',
      'fasty.auth.accessToken': 'expired-access-token',
      'fasty.auth.accessTokenExpiresAt': now
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
      'fasty.auth.refreshToken': 'refresh-token',
      'fasty.auth.refreshTokenExpiresAt': now
          .add(const Duration(days: 7))
          .toIso8601String(),
      'fasty.auth.refreshSessionId': '11111111-1111-1111-1111-111111111111',
    });

    final client = MockClient((request) async {
      throw http.ClientException('Mobile network unavailable');
    });

    final tokenStore = AuthTokenStore();
    final controller = AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: tokenStore,
    );

    await controller.initialize();

    expect(controller.isSignedIn, isTrue);
    expect(controller.session, isNotNull);
    expect(controller.accessToken, 'expired-access-token');
    expect(await tokenStore.load(), isNotNull);

    controller.dispose();
  });

  test('temporary refresh server failure keeps stored login', () async {
    final now = DateTime.now().toUtc();

    FlutterSecureStorage.setMockInitialValues({
      'fasty.auth.email': 'person@example.com',
      'fasty.auth.accessToken': 'expired-access-token',
      'fasty.auth.accessTokenExpiresAt': now
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
      'fasty.auth.refreshToken': 'refresh-token',
      'fasty.auth.refreshTokenExpiresAt': now
          .add(const Duration(days: 7))
          .toIso8601String(),
      'fasty.auth.refreshSessionId': '11111111-1111-1111-1111-111111111111',
    });

    final client = MockClient((request) async {
      return http.Response('Temporary backend failure', 503);
    });

    final tokenStore = AuthTokenStore();
    final controller = AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: tokenStore,
    );

    await controller.initialize();

    expect(controller.isSignedIn, isTrue);
    expect(controller.session, isNotNull);
    expect(await tokenStore.load(), isNotNull);

    controller.dispose();
  });

  test('invalid refresh token still signs out locally', () async {
    final now = DateTime.now().toUtc();

    FlutterSecureStorage.setMockInitialValues({
      'fasty.auth.email': 'person@example.com',
      'fasty.auth.accessToken': 'expired-access-token',
      'fasty.auth.accessTokenExpiresAt': now
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
      'fasty.auth.refreshToken': 'invalid-refresh-token',
      'fasty.auth.refreshTokenExpiresAt': now
          .add(const Duration(days: 7))
          .toIso8601String(),
      'fasty.auth.refreshSessionId': '11111111-1111-1111-1111-111111111111',
    });

    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'The refresh token is invalid or expired.'}),
        401,
        headers: const {'content-type': 'application/json'},
      );
    });

    final tokenStore = AuthTokenStore();
    final controller = AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: tokenStore,
    );

    await controller.initialize();

    expect(controller.isSignedIn, isFalse);
    expect(controller.session, isNull);
    expect(await tokenStore.load(), isNull);

    controller.dispose();
  });
}

const _googleSessionResponse = <String, dynamic>{
  'email': 'google@example.com',
  'accessToken': 'access-token',
  'accessTokenExpiresAt': '2099-01-01T00:00:00Z',
  'refreshToken': 'refresh-token',
  'refreshTokenExpiresAt': '2099-02-01T00:00:00Z',
  'refreshSessionId': '11111111-1111-1111-1111-111111111111',
};

const _storedGoogleSession = <String, String>{
  'fasty.auth.email': 'person@example.com',
  'fasty.auth.accessToken': 'access-token',
  'fasty.auth.accessTokenExpiresAt': '2099-01-01T00:00:00Z',
  'fasty.auth.refreshToken': 'refresh-token',
  'fasty.auth.refreshTokenExpiresAt': '2099-02-01T00:00:00Z',
  'fasty.auth.refreshSessionId': '11111111-1111-1111-1111-111111111111',
};
