import 'dart:convert';

import 'package:fasty/auth/active_sessions_page.dart';
import 'package:fasty/auth/auth_api.dart';
import 'package:fasty/auth/auth_controller.dart';
import 'package:fasty/auth/auth_token_store.dart';
import 'package:fasty/settings/app_settings_controller.dart';
import 'package:fasty/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('shows active sessions and marks current device', (tester) async {
    final controller = await _createSignedInController(
      MockClient((request) async {
        expect(request.method, 'GET');
        return _sessionsResponse();
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: ActiveSessionsPage(controller: controller)),
    );

    await tester.pumpAndSettle();

    expect(find.text('Windows laptop'), findsOneWidget);

    expect(find.text('Android phone'), findsOneWidget);

    expect(find.byKey(const ValueKey('current-session-label')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());

    controller.dispose();
  });

  testWidgets('revokes another device and removes it from the list', (
    tester,
  ) async {
    var deleteCount = 0;

    final controller = await _createSignedInController(
      MockClient((request) async {
        if (request.method == 'GET') {
          return _sessionsResponse();
        }

        expect(request.method, 'DELETE');

        expect(
          request.url.path,
          '/api/auth/sessions/'
          '22222222-2222-2222-2222-222222222222',
        );

        deleteCount++;

        return http.Response('', 204);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: ActiveSessionsPage(controller: controller)),
    );

    await tester.pumpAndSettle();

    final remoteSessionButton = find.byKey(
      const ValueKey(
        'revoke-session-'
        '22222222-2222-2222-2222-222222222222',
      ),
    );

    await tester.ensureVisible(remoteSessionButton);
    await tester.pumpAndSettle();

    await tester.tap(remoteSessionButton);
    await tester.pumpAndSettle();

    expect(find.text('Sign out this device session?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-session-revocation')));

    await tester.pumpAndSettle();

    expect(deleteCount, 1);

    expect(find.text('Android phone'), findsNothing);

    expect(controller.isSignedIn, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());

    controller.dispose();
  });

  testWidgets('shows retry after session loading failure', (tester) async {
    var requestCount = 0;

    final controller = await _createSignedInController(
      MockClient((request) async {
        if (request.url.path == '/api/auth/google/link') {
          return http.Response(jsonEncode({'linked': false}), 200);
        }
        requestCount++;

        if (requestCount == 1) {
          return http.Response(
            jsonEncode({'message': 'Session service unavailable.'}),
            503,
            headers: const {'content-type': 'application/json'},
          );
        }

        return _sessionsResponse();
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: ActiveSessionsPage(controller: controller)),
    );

    await tester.pumpAndSettle();

    expect(find.text('Session service unavailable.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('retry-active-sessions')));

    await tester.pumpAndSettle();

    expect(find.text('Windows laptop'), findsOneWidget);

    expect(requestCount, 2);

    await tester.pumpWidget(const SizedBox.shrink());

    controller.dispose();
  });

  testWidgets('revoking current device signs out and returns to first route', (
    tester,
  ) async {
    final controller = await _createSignedInController(
      MockClient((request) async {
        if (request.method == 'GET') {
          return _sessionsResponse();
        }

        expect(request.method, 'DELETE');

        expect(
          request.url.path,
          '/api/auth/sessions/'
          '11111111-1111-1111-1111-111111111111',
        );

        return http.Response('', 204);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          ActiveSessionsPage(controller: controller),
                    ),
                  );
                },
                child: const Text('Open sessions'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open sessions'));

    await tester.pumpAndSettle();

    final currentSessionButton = find.byKey(
      const ValueKey(
        'revoke-session-'
        '11111111-1111-1111-1111-111111111111',
      ),
    );

    await tester.ensureVisible(currentSessionButton);
    await tester.pumpAndSettle();

    await tester.tap(currentSessionButton);
    await tester.pumpAndSettle();

    expect(find.text('Sign out this device?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-session-revocation')));

    await tester.pumpAndSettle();

    expect(find.text('Open sessions'), findsOneWidget);

    expect(controller.isSignedIn, isFalse);
    expect(controller.session, isNull);

    await tester.pumpWidget(const SizedBox.shrink());

    controller.dispose();
  });

  testWidgets('opens active sessions from Settings', (tester) async {
    final controller = await _createSignedInController(
      MockClient((request) async {
        if (request.method == 'GET') {
          return _sessionsResponse();
        }

        return http.Response('', 500);
      }),
    );

    final settings = AppSettingsController.ephemeral();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(controller: settings, authController: controller),
        ),
      ),
    );

    final button = find.byKey(const ValueKey('open-active-sessions'));

    await tester.ensureVisible(button);
    await tester.pumpAndSettle();

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Active sessions'), findsOneWidget);

    expect(find.text('Windows laptop'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());

    settings.dispose();
    controller.dispose();
  });
}

http.Response _sessionsResponse() {
  return http.Response(
    jsonEncode([
      {
        'id': '11111111-1111-1111-1111-111111111111',
        'deviceName': 'Windows laptop',
        'createdAt': '2026-07-30T10:00:00Z',
        'lastUsedAt': '2026-07-30T12:00:00Z',
        'expiresAt': '2026-08-29T10:00:00Z',
      },
      {
        'id': '22222222-2222-2222-2222-222222222222',
        'deviceName': 'Android phone',
        'createdAt': '2026-07-29T10:00:00Z',
        'lastUsedAt': null,
        'expiresAt': '2026-08-28T10:00:00Z',
      },
    ]),
    200,
    headers: const {'content-type': 'application/json'},
  );
}

Future<AuthController> _createSignedInController(http.Client client) async {
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

  final controller = AuthController(
    api: AuthApi(baseUrl: 'http://fasty.test', client: client),
    tokenStore: AuthTokenStore(),
  );

  await controller.initialize();

  return controller;
}
