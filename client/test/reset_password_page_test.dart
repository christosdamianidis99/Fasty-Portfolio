import 'dart:convert';

import 'package:fasty/auth/auth_api.dart';
import 'package:fasty/auth/auth_controller.dart';
import 'package:fasty/auth/auth_token_store.dart';
import 'package:fasty/auth/reset_password_page.dart';
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

  testWidgets('pre-fills email and token', (tester) async {
    final controller = _createController(
      MockClient((request) async {
        return http.Response('', 500);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ResetPasswordPage(
          controller: controller,
          initialEmail: ' person@example.com ',
          initialToken: ' encoded-reset-token ',
        ),
      ),
    );

    final emailField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('reset-password-email')),
    );

    final tokenField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('reset-password-token')),
    );

    expect(emailField.controller!.text, 'person@example.com');

    expect(tokenField.controller!.text, 'encoded-reset-token');

    await tester.pumpWidget(const SizedBox.shrink());

    controller.dispose();
  });

  testWidgets('submits reset request and shows success', (tester) async {
    final controller = _createController(
      MockClient((request) async {
        expect(
          request.url,
          Uri.parse(
            'http://fasty.test'
            '/api/auth/reset-password',
          ),
        );

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
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ResetPasswordPage(
          controller: controller,
          initialEmail: 'person@example.com',
          initialToken: 'encoded-reset-token',
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('reset-password-new-password')),
      'Replacement456!',
    );

    await tester.enterText(
      find.byKey(const ValueKey('reset-password-confirmation')),
      'Replacement456!',
    );

    final submitButton = find.widgetWithText(FilledButton, 'Reset password');

    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);

    await tester.pumpAndSettle();

    expect(find.text('Password reset successfully.'), findsOneWidget);

    final tokenField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('reset-password-token')),
    );

    final passwordField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('reset-password-new-password')),
    );

    final confirmationField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('reset-password-confirmation')),
    );

    expect(tokenField.controller!.text, isEmpty);
    expect(passwordField.controller!.text, isEmpty);
    expect(confirmationField.controller!.text, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());

    controller.dispose();
  });

  testWidgets('shows invalid or expired token response', (tester) async {
    final controller = _createController(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message':
                'The password reset request '
                'is invalid or expired.',
          }),
          400,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ResetPasswordPage(
          controller: controller,
          initialEmail: 'person@example.com',
          initialToken: 'invalid-token',
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('reset-password-new-password')),
      'Replacement456!',
    );

    await tester.enterText(
      find.byKey(const ValueKey('reset-password-confirmation')),
      'Replacement456!',
    );

    final submitButton = find.widgetWithText(FilledButton, 'Reset password');

    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);

    await tester.pumpAndSettle();

    expect(
      find.text(
        'The password reset request '
        'is invalid or expired.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());

    controller.dispose();
  });

  testWidgets('validates weak password locally', (tester) async {
    var requestCount = 0;

    final controller = _createController(
      MockClient((request) async {
        requestCount++;
        return http.Response('', 500);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ResetPasswordPage(
          controller: controller,
          initialEmail: 'person@example.com',
          initialToken: 'encoded-reset-token',
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('reset-password-new-password')),
      'weak',
    );

    await tester.enterText(
      find.byKey(const ValueKey('reset-password-confirmation')),
      'weak',
    );

    final submitButton = find.widgetWithText(FilledButton, 'Reset password');

    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);

    await tester.pump();

    expect(find.text('Use at least 12 characters.'), findsOneWidget);

    expect(requestCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());

    controller.dispose();
  });

  testWidgets('validates mismatched passwords locally', (tester) async {
    var requestCount = 0;

    final controller = _createController(
      MockClient((request) async {
        requestCount++;
        return http.Response('', 500);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ResetPasswordPage(
          controller: controller,
          initialEmail: 'person@example.com',
          initialToken: 'encoded-reset-token',
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('reset-password-new-password')),
      'Replacement456!',
    );

    await tester.enterText(
      find.byKey(const ValueKey('reset-password-confirmation')),
      'Different789!',
    );

    final submitButton = find.widgetWithText(FilledButton, 'Reset password');

    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);

    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);

    expect(requestCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());

    controller.dispose();
  });
}

AuthController _createController(http.Client client) {
  return AuthController(
    api: AuthApi(baseUrl: 'http://fasty.test', client: client),
    tokenStore: AuthTokenStore(),
  );
}
