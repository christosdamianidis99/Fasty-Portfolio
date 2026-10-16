import 'dart:convert';

import 'package:fasty/auth/auth_api.dart';
import 'package:fasty/auth/auth_controller.dart';
import 'package:fasty/auth/auth_token_store.dart';
import 'package:fasty/auth/google_identity_service.dart';
import 'package:fasty/auth/link_google_page.dart';
import 'package:fasty/auth/login_page.dart';
import 'package:fasty/settings/app_settings_controller.dart';
import 'package:fasty/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Google sign-in bypasses password form and stores session', (
    tester,
  ) async {
    final store = AuthTokenStore();
    final controller = _controller(
      store,
      MockClient((request) async {
        expect(request.url.path, '/api/auth/google');
        expect(jsonDecode(request.body)['idToken'], 'google-token');
        return http.Response(jsonEncode(_sessionResponse), 200);
      }),
    );
    final identity = _FakeGoogleIdentityService('google-token');

    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          controller: controller,
          googleIdentityService: identity,
        ),
      ),
    );
    final button = find.byKey(const ValueKey('google-sign-in-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(identity.calls, 1);
    expect(controller.isSignedIn, isTrue);
    expect((await store.load())?.email, 'google@example.com');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('existing account conflict guides user to linking', (
    tester,
  ) async {
    final controller = _controller(
      AuthTokenStore(),
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'account_link_required',
            'detail': 'Sign in first, then link Google.',
          }),
          409,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          controller: controller,
          googleIdentityService: _FakeGoogleIdentityService('google-token'),
        ),
      ),
    );
    final button = find.byKey(const ValueKey('google-sign-in-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Sign in first, then link Google.'), findsOneWidget);
    expect(
      find.text('Sign in with your password, then link Google in Settings.'),
      findsOneWidget,
    );
    expect(controller.isSignedIn, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('link page sends token for current account and shows result', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues(_storedSession);
    final store = AuthTokenStore();
    final controller = _controller(
      store,
      MockClient((request) async {
        expect(request.url.path, '/api/auth/google/link');
        expect(request.headers['authorization'], 'Bearer access-token');
        expect(jsonDecode(request.body), {'idToken': 'google-token'});
        return http.Response(
          jsonEncode({'message': 'Google account linked successfully.'}),
          200,
        );
      }),
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: LinkGooglePage(
          controller: controller,
          googleIdentityService: _FakeGoogleIdentityService('google-token'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('link-google-button')));
    await tester.pumpAndSettle();

    expect(find.text('Google account linked'), findsOneWidget);
    expect(
      find.text('Would you like to sign out now and sign in with Google?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Stay signed in'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link-google-button')), findsNothing);
    expect(controller.isSignedIn, isTrue);
    expect(await store.load(), isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('settings shows linked status after restored session', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues(_storedSession);
    final controller = _controller(
      AuthTokenStore(),
      MockClient((request) async {
        expect(request.url.path, '/api/auth/google/link');
        return http.Response(jsonEncode({'linked': true}), 200);
      }),
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            controller: AppSettingsController.ephemeral(),
            authController: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Google account linked'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-link-google')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('settings explains outdated server and retry recovers', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues(_storedSession);
    var requests = 0;
    final controller = _controller(
      AuthTokenStore(),
      MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/auth/google/link');
        requests++;
        return requests <= 2
            ? http.Response('', 405)
            : http.Response(jsonEncode({'linked': true}), 200);
      }),
    );
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            controller: AppSettingsController.ephemeral(),
            authController: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The server needs an update before it can check Google linking.',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Google account linked'), findsOneWidget);
    expect(requests, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('settings opens Google linking page', (tester) async {
    FlutterSecureStorage.setMockInitialValues(_storedSession);
    final controller = _controller(
      AuthTokenStore(),
      MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/auth/google/link') {
          return http.Response(jsonEncode({'linked': false}), 200);
        }
        return http.Response('', 500);
      }),
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            controller: AppSettingsController.ephemeral(),
            authController: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('open-link-google'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byType(LinkGooglePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

AuthController _controller(AuthTokenStore store, http.Client client) =>
    AuthController(
      api: AuthApi(baseUrl: 'http://fasty.test', client: client),
      tokenStore: store,
    );

class _FakeGoogleIdentityService implements GoogleIdentityService {
  _FakeGoogleIdentityService(this.token);

  final String? token;
  int calls = 0;

  @override
  bool get isAvailable => true;

  @override
  String? get unavailableReason => null;

  @override
  Future<String?> acquireIdToken() async {
    calls++;
    return token;
  }
}

const _sessionResponse = <String, dynamic>{
  'email': 'google@example.com',
  'accessToken': 'access-token',
  'accessTokenExpiresAt': '2099-01-01T00:00:00Z',
  'refreshToken': 'refresh-token',
  'refreshTokenExpiresAt': '2099-02-01T00:00:00Z',
  'refreshSessionId': '11111111-1111-1111-1111-111111111111',
};

const _storedSession = <String, String>{
  'fasty.auth.email': 'person@example.com',
  'fasty.auth.accessToken': 'access-token',
  'fasty.auth.accessTokenExpiresAt': '2099-01-01T00:00:00Z',
  'fasty.auth.refreshToken': 'refresh-token',
  'fasty.auth.refreshTokenExpiresAt': '2099-02-01T00:00:00Z',
  'fasty.auth.refreshSessionId': '11111111-1111-1111-1111-111111111111',
};
