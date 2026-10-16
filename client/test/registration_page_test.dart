import 'dart:convert';

import 'package:fasty/auth/auth_api.dart';
import 'package:fasty/auth/auth_controller.dart';
import 'package:fasty/auth/auth_token_store.dart';
import 'package:fasty/auth/login_page.dart';
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

  testWidgets('opens beta registration page from login page', (tester) async {
    final controller = _createController(
      MockClient((request) async {
        return http.Response('', 500);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(controller: controller)),
    );

    expect(find.text('Welcome to Fasty'), findsOneWidget);

    final createAccount = find.text('Create account');
    await tester.ensureVisible(createAccount);
    await tester.pumpAndSettle();
    await tester.tap(createAccount);
    await tester.pumpAndSettle();

    expect(find.text('Create your Fasty account'), findsOneWidget);
    expect(
      find.text(
        'Private beta accounts are ready immediately. '
        'No email verification is required.',
      ),
      findsOneWidget,
    );
    expect(find.text('Enter confirmation token'), findsNothing);
    expect(find.text('Back to sign in'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('shows registration unavailable response', (tester) async {
    final controller = _createController(
      MockClient((request) async {
        expect(request.url, Uri.parse('http://fasty.test/api/auth/register'));
        return http.Response('', 404);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(controller: controller)),
    );

    final createAccount = find.text('Create account');
    await tester.ensureVisible(createAccount);
    await tester.pumpAndSettle();
    await tester.tap(createAccount);
    await tester.pumpAndSettle();

    await _fillRegistrationForm(tester);

    final submitButton = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('Registration is currently unavailable.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('successful registration returns to prefilled login', (
    tester,
  ) async {
    final controller = _createController(
      MockClient((request) async {
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
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(controller: controller)),
    );

    final createAccount = find.text('Create account');
    await tester.ensureVisible(createAccount);
    await tester.pumpAndSettle();
    await tester.tap(createAccount);
    await tester.pumpAndSettle();

    await _fillRegistrationForm(tester);

    final submitButton = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Fasty'), findsOneWidget);
    expect(find.text('Create your Fasty account'), findsNothing);

    final loginFields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();

    expect(loginFields, hasLength(2));
    expect(loginFields[0].controller!.text, 'person@example.com');
    expect(loginFields[1].controller!.text, isEmpty);

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
      MaterialApp(home: LoginPage(controller: controller)),
    );

    final createAccount = find.text('Create account');
    await tester.ensureVisible(createAccount);
    await tester.pumpAndSettle();
    await tester.tap(createAccount);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('registration-email')),
      'person@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('registration-password')),
      'StrongPassword123!',
    );
    await tester.enterText(
      find.byKey(const ValueKey('registration-confirm-password')),
      'DifferentPassword123!',
    );

    final submitButton = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(requestCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

Future<void> _fillRegistrationForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('registration-email')),
    'person@example.com',
  );
  await tester.enterText(
    find.byKey(const ValueKey('registration-password')),
    'StrongPassword123!',
  );
  await tester.enterText(
    find.byKey(const ValueKey('registration-confirm-password')),
    'StrongPassword123!',
  );
}

AuthController _createController(http.Client client) {
  return AuthController(
    api: AuthApi(baseUrl: 'http://fasty.test', client: client),
    tokenStore: AuthTokenStore(),
  );
}
