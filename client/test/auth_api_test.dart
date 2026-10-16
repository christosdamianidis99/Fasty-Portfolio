import 'dart:convert';

import 'package:fasty/auth/auth_api.dart';
import 'package:fasty/auth/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('login uses backend email from session response', () async {
    final api = AuthApi(
      baseUrl: 'http://fasty.test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/auth/login');
        expect(jsonDecode(request.body), {
          'email': 'entered@example.com',
          'password': 'password',
          'deviceName': 'Laptop',
        });
        return http.Response(
          jsonEncode(_sessionResponse('canonical@example.com')),
          200,
        );
      }),
    );

    final session = await api.login(
      email: ' entered@example.com ',
      password: 'password',
      deviceName: ' Laptop ',
    );
    expect(session.email, 'canonical@example.com');
    api.close();
  });

  test('refresh uses backend email from session response', () async {
    final api = AuthApi(
      baseUrl: 'http://fasty.test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/auth/refresh');
        expect(jsonDecode(request.body), {'refreshToken': 'refresh-token'});
        return http.Response(
          jsonEncode(_sessionResponse('updated@example.com')),
          200,
        );
      }),
    );

    final current = AuthSession.fromLoginResponse(
      json: _sessionResponse('old@example.com'),
    );
    final refreshed = await api.refresh(current);
    expect(refreshed.email, 'updated@example.com');
    api.close();
  });

  test('googleLogin sends token and returns backend session', () async {
    final api = AuthApi(
      baseUrl: 'http://fasty.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/auth/google');
        expect(request.headers['content-type'], 'application/json');
        expect(request.headers['accept'], 'application/json');
        expect(jsonDecode(request.body), {
          'idToken': 'google-id-token',
          'deviceName': 'Android phone',
        });
        return http.Response(
          jsonEncode(_sessionResponse('google@example.com')),
          200,
        );
      }),
    );

    final session = await api.googleLogin(
      idToken: ' google-id-token ',
      deviceName: ' Android phone ',
    );
    expect(session.email, 'google@example.com');
    expect(session.accessToken, 'access-token');
    api.close();
  });

  test('googleLogin exposes account link code and backend detail', () async {
    final api = AuthApi(
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
    );

    await expectLater(
      api.googleLogin(idToken: 'token', deviceName: 'Laptop'),
      throwsA(
        isA<AuthApiException>()
            .having((error) => error.statusCode, 'status', 409)
            .having((error) => error.code, 'code', 'account_link_required')
            .having(
              (error) => error.toString(),
              'message',
              'Sign in first, then link Google.',
            ),
      ),
    );
    api.close();
  });

  test('linkGoogle sends authenticated token and returns message', () async {
    final api = AuthApi(
      baseUrl: 'http://fasty.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/auth/google/link');
        expect(request.headers['authorization'], 'Bearer access-token');
        expect(request.headers['content-type'], 'application/json');
        expect(request.headers['accept'], 'application/json');
        expect(jsonDecode(request.body), {'idToken': 'google-id-token'});
        return http.Response(
          jsonEncode({'message': 'Google account linked successfully.'}),
          200,
        );
      }),
    );

    final message = await api.linkGoogle(
      accessToken: ' access-token ',
      idToken: ' google-id-token ',
    );
    expect(message, 'Google account linked successfully.');
    api.close();
  });

  test('linkGoogle exposes backend conflict detail', () async {
    final api = AuthApi(
      baseUrl: 'http://fasty.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'detail': 'The Google account must use the same email address.',
          }),
          409,
        ),
      ),
    );

    await expectLater(
      api.linkGoogle(accessToken: 'access-token', idToken: 'token'),
      throwsA(
        isA<AuthApiException>()
            .having((error) => error.code, 'code', isNull)
            .having(
              (error) => error.toString(),
              'message',
              'The Google account must use the same email address.',
            ),
      ),
    );
    api.close();
  });

  test('AuthApiException ignores malformed or non-string codes', () {
    expect(
      const AuthApiException(statusCode: 400, responseBody: 'invalid').code,
      isNull,
    );
    expect(
      AuthApiException(
        statusCode: 400,
        responseBody: jsonEncode({'code': 17}),
      ).code,
      isNull,
    );
  });

  test('register sends normalized request and returns message', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url, Uri.parse('http://fasty.test/api/auth/register'));
      expect(request.headers['content-type'], 'application/json');
      expect(request.headers['accept'], 'application/json');
      expect(jsonDecode(request.body), {
        'email': 'person@example.com',
        'password': 'StrongPassword123!',
      });

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

    final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

    final message = await api.register(
      email: '  person@example.com  ',
      password: 'StrongPassword123!',
    );

    expect(
      message,
      'If this email can be registered, '
      'a verification message will be sent.',
    );

    api.close();
  });

  test('register reports when registration is disabled', () async {
    final client = MockClient((request) async {
      return http.Response('', 404);
    });

    final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

    await expectLater(
      api.register(email: 'person@example.com', password: 'StrongPassword123!'),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.toString(),
          'message',
          'Registration is currently unavailable.',
        ),
      ),
    );

    api.close();
  });

  test('register exposes first backend validation error', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'type': 'https://tools.ietf.org/html/rfc9110#section-15.5.1',
          'title': 'One or more validation errors occurred.',
          'status': 400,
          'errors': {
            'PasswordTooShort': ['Passwords must be at least 12 characters.'],
          },
        }),
        400,
        headers: const {'content-type': 'application/problem+json'},
      );
    });

    final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

    await expectLater(
      api.register(email: 'person@example.com', password: 'short'),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.toString(),
          'message',
          'Passwords must be at least 12 characters.',
        ),
      ),
    );

    api.close();
  });

  test('confirmEmail sends normalized request and returns message', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.parse('http://fasty.test/api/auth/confirm-email'),
      );
      expect(request.headers['content-type'], 'application/json');
      expect(request.headers['accept'], 'application/json');
      expect(jsonDecode(request.body), {
        'email': 'person@example.com',
        'token': 'encoded-confirmation-token',
      });

      return http.Response(
        jsonEncode({'message': 'Email address confirmed successfully.'}),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

    final message = await api.confirmEmail(
      email: '  person@example.com  ',
      token: '  encoded-confirmation-token  ',
    );

    expect(message, 'Email address confirmed successfully.');

    api.close();
  });

  test('confirmEmail exposes invalid or expired token message', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'message': 'The confirmation request is invalid or expired.',
        }),
        400,
        headers: const {'content-type': 'application/json'},
      );
    });

    final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

    await expectLater(
      api.confirmEmail(email: 'person@example.com', token: 'invalid-token'),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.toString(),
          'message',
          'The confirmation request is invalid or expired.',
        ),
      ),
    );

    api.close();
  });

  test('forgotPassword sends normalized request and returns message', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.parse('http://fasty.test/api/auth/forgot-password'),
      );
      expect(request.headers['content-type'], 'application/json');
      expect(request.headers['accept'], 'application/json');
      expect(jsonDecode(request.body), {'email': 'person@example.com'});

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

    final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

    final message = await api.forgotPassword(email: '  person@example.com  ');

    expect(
      message,
      'If the account can be recovered, '
      'a password reset message will be sent.',
    );

    api.close();
  });

  test(
    'redeemPasswordRecoveryCredential sends normalized request and returns message',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url,
          Uri.parse('http://fasty.test/api/auth/password-recovery/redeem'),
        );

        expect(jsonDecode(request.body), {
          'email': 'person@example.com',
          'recoveryCredential': 'temporary-credential',
          'newPassword': 'Replacement456!',
        });

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

      final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

      final message = await api.redeemPasswordRecoveryCredential(
        email: '  person@example.com  ',
        recoveryCredential: '  temporary-credential  ',
        newPassword: 'Replacement456!',
      );

      expect(
        message,
        'Password reset successfully. '
        'Sign in with your new password.',
      );

      api.close();
    },
  );

  test(
    'redeemPasswordRecoveryCredential exposes invalid credential message',
    () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'The recovery credential is invalid or expired.',
          }),
          400,
          headers: const {'content-type': 'application/json'},
        );
      });

      final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

      await expectLater(
        api.redeemPasswordRecoveryCredential(
          email: 'person@example.com',
          recoveryCredential: 'invalid',
          newPassword: 'Replacement456!',
        ),
        throwsA(
          isA<AuthApiException>().having(
            (error) => error.toString(),
            'message',
            'The recovery credential is invalid or expired.',
          ),
        ),
      );

      api.close();
    },
  );
  test('resetPassword sends normalized request and returns message', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.parse('http://fasty.test/api/auth/reset-password'),
      );
      expect(request.headers['content-type'], 'application/json');
      expect(request.headers['accept'], 'application/json');
      expect(jsonDecode(request.body), {
        'email': 'person@example.com',
        'token': 'encoded-reset-token',
        'newPassword': 'Replacement456!',
      });

      return http.Response(
        jsonEncode({'message': 'Password reset successfully.'}),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

    final message = await api.resetPassword(
      email: '  person@example.com  ',
      token: '  encoded-reset-token  ',
      newPassword: 'Replacement456!',
    );

    expect(message, 'Password reset successfully.');

    api.close();
  });

  test('resetPassword exposes invalid or expired token message', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'message': 'The password reset request is invalid or expired.',
        }),
        400,
        headers: const {'content-type': 'application/json'},
      );
    });

    final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

    await expectLater(
      api.resetPassword(
        email: 'person@example.com',
        token: 'invalid-token',
        newPassword: 'Replacement456!',
      ),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.toString(),
          'message',
          'The password reset request is invalid or expired.',
        ),
      ),
    );

    api.close();
  });

  test('resetPassword exposes password policy error', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'title': 'One or more validation errors occurred.',
          'status': 400,
          'errors': {
            'PasswordTooShort': ['Passwords must be at least 12 characters.'],
          },
        }),
        400,
        headers: const {'content-type': 'application/problem+json'},
      );
    });

    final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

    await expectLater(
      api.resetPassword(
        email: 'person@example.com',
        token: 'encoded-reset-token',
        newPassword: 'weak',
      ),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.toString(),
          'message',
          'Passwords must be at least 12 characters.',
        ),
      ),
    );

    api.close();
  });

  test(
    'changePassword sends authenticated request and returns message',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url,
          Uri.parse('http://fasty.test/api/auth/change-password'),
        );
        expect(request.headers['authorization'], 'Bearer access-token');
        expect(request.headers['content-type'], 'application/json');
        expect(request.headers['accept'], 'application/json');
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

      final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

      final message = await api.changePassword(
        accessToken: '  access-token  ',
        currentPassword: 'StrongPassword123!',
        newPassword: 'Replacement456!',
      );

      expect(
        message,
        'Password changed successfully. '
        'Sign in again with your new password.',
      );

      api.close();
    },
  );

  test('changePassword exposes incorrect current password message', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'The current password is incorrect.'}),
        400,
        headers: const {'content-type': 'application/json'},
      );
    });

    final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

    await expectLater(
      api.changePassword(
        accessToken: 'access-token',
        currentPassword: 'WrongPassword123!',
        newPassword: 'Replacement456!',
      ),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.toString(),
          'message',
          'The current password is incorrect.',
        ),
      ),
    );

    api.close();
  });

  test('listSessions parses authenticated session metadata', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url, Uri.parse('http://fasty.test/api/auth/sessions'));
      expect(request.headers['authorization'], 'Bearer access-token');
      expect(request.headers['accept'], 'application/json');

      return http.Response(
        jsonEncode([
          {
            'id': '11111111-1111-1111-1111-111111111111',
            'deviceName': 'Windows laptop',
            'createdAt': '2026-07-30T10:00:00Z',
            'lastUsedAt': null,
            'expiresAt': '2026-08-29T10:00:00Z',
          },
          {
            'id': '22222222-2222-2222-2222-222222222222',
            'deviceName': 'Android phone',
            'createdAt': '2026-07-29T10:00:00Z',
            'lastUsedAt': '2026-07-30T11:00:00Z',
            'expiresAt': '2026-08-28T10:00:00Z',
          },
        ]),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

    final sessions = await api.listSessions(accessToken: '  access-token  ');

    expect(sessions, hasLength(2));
    expect(sessions.first.id, '11111111-1111-1111-1111-111111111111');
    expect(sessions.first.deviceName, 'Windows laptop');
    expect(sessions.first.lastUsedAt, isNull);
    expect(sessions.last.lastUsedAt, DateTime.utc(2026, 7, 30, 11));

    api.close();
  });

  test('listSessions rejects invalid response items', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode([
          {'id': '11111111-1111-1111-1111-111111111111'},
        ]),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

    await expectLater(
      api.listSessions(accessToken: 'access-token'),
      throwsFormatException,
    );

    api.close();
  });

  test('revokeSession sends authenticated delete request', () async {
    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(
        request.url,
        Uri.parse(
          'http://fasty.test/api/auth/sessions/'
          '11111111-1111-1111-1111-111111111111',
        ),
      );
      expect(request.headers['authorization'], 'Bearer access-token');

      return http.Response('', 204);
    });

    final api = AuthApi(baseUrl: 'http://fasty.test', client: client);

    await api.revokeSession(
      accessToken: '  access-token  ',
      sessionId: '  11111111-1111-1111-1111-111111111111  ',
    );

    api.close();
  });
}

Map<String, dynamic> _sessionResponse(String email) => {
  'email': email,
  'accessToken': 'access-token',
  'accessTokenExpiresAt': '2099-01-01T00:00:00Z',
  'refreshToken': 'refresh-token',
  'refreshTokenExpiresAt': '2099-02-01T00:00:00Z',
  'refreshSessionId': '11111111-1111-1111-1111-111111111111',
};
