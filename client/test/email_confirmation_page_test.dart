import 'dart:convert';

import 'package:fasty/auth/auth_api.dart';
import 'package:fasty/auth/auth_controller.dart';
import 'package:fasty/auth/auth_token_store.dart';
import 'package:fasty/auth/email_confirmation_page.dart';
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

  testWidgets('renders email confirmation page directly', (tester) async {
    final controller = _createController(
      MockClient((request) async => http.Response('', 500)),
    );

    await tester.pumpWidget(
      MaterialApp(home: EmailConfirmationPage(controller: controller)),
    );

    expect(find.text('Confirm your email address'), findsOneWidget);
    expect(find.byKey(const ValueKey('confirmation-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('confirmation-token')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('pre-fills email and token from confirmation link', (
    tester,
  ) async {
    final controller = _createController(
      MockClient((request) async => http.Response('', 500)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EmailConfirmationPage(
          controller: controller,
          initialEmail: ' person@example.com ',
          initialToken: ' encoded-confirmation-token ',
        ),
      ),
    );

    final emailField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('confirmation-email')),
    );
    final tokenField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('confirmation-token')),
    );

    expect(emailField.controller!.text, 'person@example.com');
    expect(tokenField.controller!.text, 'encoded-confirmation-token');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('reports successful email confirmation', (tester) async {
    String? confirmedEmail;
    final controller = _createController(
      MockClient((request) async {
        expect(
          request.url,
          Uri.parse('http://fasty.test/api/auth/confirm-email'),
        );
        expect(jsonDecode(request.body), {
          'email': 'person@example.com',
          'token': 'encoded-confirmation-token',
        });

        return http.Response(
          jsonEncode({'message': 'Email address confirmed successfully.'}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EmailConfirmationPage(
          controller: controller,
          onConfirmed: (email) => confirmedEmail = email,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('confirmation-email')),
      'person@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('confirmation-token')),
      'encoded-confirmation-token',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm email'));
    await tester.pumpAndSettle();

    expect(confirmedEmail, 'person@example.com');
    expect(find.text('Email address confirmed successfully.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('shows invalid or expired confirmation response', (tester) async {
    final controller = _createController(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'The confirmation request is invalid or expired.',
          }),
          400,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: EmailConfirmationPage(controller: controller)),
    );

    await tester.enterText(
      find.byKey(const ValueKey('confirmation-email')),
      'person@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('confirmation-token')),
      'invalid-token',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm email'));
    await tester.pumpAndSettle();

    expect(
      find.text('The confirmation request is invalid or expired.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('validates missing confirmation token locally', (tester) async {
    var requestCount = 0;
    final controller = _createController(
      MockClient((request) async {
        requestCount++;
        return http.Response('', 500);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: EmailConfirmationPage(controller: controller)),
    );

    await tester.enterText(
      find.byKey(const ValueKey('confirmation-email')),
      'person@example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm email'));
    await tester.pump();

    expect(find.text('Enter the confirmation token.'), findsOneWidget);
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
