import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fasty/auth/google_identity_desktop_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('desktop denial returns without exchanging a token', () async {
    final client = MockClient((_) async {
      fail('Denied authentication must not call the Fasty exchange endpoint.');
    });

    final token = await acquireDesktopGoogleIdToken(
      'desktop-client-id',
      apiBaseUrl: 'https://api.example.test',
      client: client,
      openBrowser: (uri) async {
        final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);

        final response = await http.get(
          redirect.replace(
            queryParameters: {
              'state': uri.queryParameters['state']!,
              'error': 'access_denied',
            },
          ),
        );

        expect(response.statusCode, 200);
        return true;
      },
    );

    expect(token, isNull);

    client.close();
  });

  test(
    'desktop sign-in validates state and exchanges PKCE code through Fasty',
    () async {
      late Uri authorizationUri;

      final client = MockClient((request) async {
        expect(
          request.url,
          Uri.parse(
            'https://api.example.test/api/auth/google/desktop/exchange',
          ),
        );

        expect(request.method, 'POST');

        final decoded = jsonDecode(request.body);
        expect(decoded, isA<Map<String, dynamic>>());

        final body = decoded as Map<String, dynamic>;

        expect(body['code'], 'authorization-code');

        expect(
          body['redirectUri'],
          authorizationUri.queryParameters['redirect_uri'],
        );

        final verifier = body['codeVerifier'];
        expect(verifier, isA<String>());

        final challenge = base64Url
            .encode(sha256.convert(ascii.encode(verifier as String)).bytes)
            .replaceAll('=', '');

        expect(authorizationUri.queryParameters['code_challenge'], challenge);

        return http.Response(
          jsonEncode({'idToken': 'google-id-token'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final token = await acquireDesktopGoogleIdToken(
        'desktop-client-id',
        apiBaseUrl: 'https://api.example.test/',
        client: client,
        openBrowser: (uri) async {
          authorizationUri = uri;

          expect(uri.host, 'accounts.google.com');
          expect(uri.queryParameters['scope'], 'openid email profile');

          final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);

          final invalid = await http.get(
            redirect.replace(
              queryParameters: {'state': 'wrong-state', 'code': 'wrong-code'},
            ),
          );

          expect(invalid.statusCode, 400);

          final valid = await http.get(
            redirect.replace(
              queryParameters: {
                'state': uri.queryParameters['state']!,
                'code': 'authorization-code',
              },
            ),
          );

          expect(valid.statusCode, 200);

          return true;
        },
      );

      expect(token, 'google-id-token');

      client.close();
    },
  );
}
