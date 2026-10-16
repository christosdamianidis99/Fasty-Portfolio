import 'dart:convert';

import 'package:fasty/auth/auth_api.dart';
import 'package:fasty/auth/auth_controller.dart';
import 'package:fasty/auth/auth_token_store.dart';
import 'package:fasty/auth/change_password_page.dart';
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

  testWidgets('validates mismatched passwords locally', (tester) async {
    var requestCount = 0;

    final controller = await _createSignedInController(
      MockClient((request) async {
        if (request.url.path == '/api/auth/google/link') {
          return http.Response(jsonEncode({'linked': false}), 200);
        }
        requestCount++;
        return http.Response('', 500);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChangePasswordPage(controller: controller)),
    );

    await tester.enterText(
      find.byKey(const ValueKey('change-password-current-password')),
      'StrongPassword123!',
    );

    await tester.enterText(
      find.byKey(const ValueKey('change-password-new-password')),
      'Replacement456!',
    );

    await tester.enterText(
      find.byKey(const ValueKey('change-password-confirmation')),
      'Different789!',
    );

    final submitButton = find.widgetWithText(FilledButton, 'Change password');

    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(requestCount, 0);
    expect(controller.isSignedIn, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('shows incorrect current password response', (tester) async {
    final controller = await _createSignedInController(
      MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'The current password is incorrect.'}),
          400,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChangePasswordPage(controller: controller)),
    );

    await _enterValidPasswords(tester);

    final submitButton = find.widgetWithText(FilledButton, 'Change password');

    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('The current password is incorrect.'), findsOneWidget);
    expect(controller.isSignedIn, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('returns to first route and signs out after success', (
    tester,
  ) async {
    final controller = await _createSignedInController(
      MockClient((request) async {
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
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) =>
                            ChangePasswordPage(controller: controller),
                      ),
                    );
                  },
                  child: const Text('Open password page'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open password page'));
    await tester.pumpAndSettle();

    await _enterValidPasswords(tester);

    final submitButton = find.widgetWithText(FilledButton, 'Change password');

    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('Open password page'), findsOneWidget);
    expect(find.text('Change your password'), findsNothing);

    expect(controller.isSignedIn, isFalse);
    expect(controller.session, isNull);
    expect(
      controller.message,
      'Password changed successfully. '
      'Sign in again with your new password.',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  testWidgets('opens change-password page from Settings', (tester) async {
    final controller = await _createSignedInController(
      MockClient((request) async {
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

    final changePasswordButton = find.widgetWithText(
      FilledButton,
      'Change password',
    );

    await tester.ensureVisible(changePasswordButton);
    await tester.pumpAndSettle();
    await tester.tap(changePasswordButton);
    await tester.pumpAndSettle();

    expect(find.text('Change your password'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('change-password-current-password')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());

    settings.dispose();
    controller.dispose();
  });
}

Future<void> _enterValidPasswords(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('change-password-current-password')),
    'StrongPassword123!',
  );

  await tester.enterText(
    find.byKey(const ValueKey('change-password-new-password')),
    'Replacement456!',
  );

  await tester.enterText(
    find.byKey(const ValueKey('change-password-confirmation')),
    'Replacement456!',
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
