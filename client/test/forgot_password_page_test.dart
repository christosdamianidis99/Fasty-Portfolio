import 'dart:convert';

import 'package:fasty/auth/auth_api.dart';
import 'package:fasty/auth/auth_controller.dart';
import 'package:fasty/auth/auth_token_store.dart';
import 'package:fasty/auth/forgot_password_page.dart';
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

  testWidgets('renders private beta assisted recovery flow', (tester) async {
    final controller = _createController(
      MockClient((request) async => http.Response('', 500)),
    );

    await tester.pumpWidget(
      MaterialApp(home: ForgotPasswordPage(controller: controller)),
    );

    expect(find.text('Private beta account recovery'), findsOneWidget);

    expect(find.textContaining('Contact Christos'), findsOneWidget);

    expect(find.byKey(const ValueKey('recovery-credential')), findsOneWidget);

    expect(find.byKey(const ValueKey('recovery-new-password')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('submits assisted recovery and returns to previous route', (
    tester,
  ) async {
    final controller = _createController(
      MockClient((request) async {
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
                      builder: (_) => ForgotPasswordPage(
                        controller: controller,
                        initialEmail: 'person@example.com',
                      ),
                    ),
                  );
                },
                child: const Text('Open recovery'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open recovery'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('recovery-credential')),
      'temporary-credential',
    );

    await tester.enterText(
      find.byKey(const ValueKey('recovery-new-password')),
      'Replacement456!',
    );

    await tester.enterText(
      find.byKey(const ValueKey('recovery-password-confirmation')),
      'Replacement456!',
    );

    final button = find.widgetWithText(FilledButton, 'Reset password');

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Open recovery'), findsOneWidget);

    expect(
      controller.message,
      'Password reset successfully. '
      'Sign in with your new password.',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('shows invalid recovery credential error', (tester) async {
    final controller = _createController(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'The recovery credential is invalid or expired.',
          }),
          400,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ForgotPasswordPage(
          controller: controller,
          initialEmail: 'person@example.com',
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('recovery-credential')),
      'invalid',
    );

    await tester.enterText(
      find.byKey(const ValueKey('recovery-new-password')),
      'Replacement456!',
    );

    await tester.enterText(
      find.byKey(const ValueKey('recovery-password-confirmation')),
      'Replacement456!',
    );

    final button = find.widgetWithText(FilledButton, 'Reset password');

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(
      find.text('The recovery credential is invalid or expired.'),
      findsOneWidget,
    );

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
        home: ForgotPasswordPage(
          controller: controller,
          initialEmail: 'person@example.com',
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('recovery-credential')),
      'temporary-credential',
    );

    await tester.enterText(
      find.byKey(const ValueKey('recovery-new-password')),
      'Replacement456!',
    );

    await tester.enterText(
      find.byKey(const ValueKey('recovery-password-confirmation')),
      'Different789!',
    );

    final button = find.widgetWithText(FilledButton, 'Reset password');

    await tester.ensureVisible(button);
    await tester.tap(button);
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
