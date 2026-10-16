import 'package:fasty/auth/auth_api.dart';
import 'package:fasty/auth/auth_controller.dart';
import 'package:fasty/auth/auth_token_store.dart';
import 'package:fasty/auth/email_confirmation_link.dart';
import 'package:fasty/auth/signed_out_entry.dart';
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

  testWidgets('shows login when no confirmation link exists', (tester) async {
    final controller = _createController();

    await tester.pumpWidget(
      MaterialApp(home: SignedOutEntry(controller: controller)),
    );

    expect(find.text('Welcome to Fasty'), findsOneWidget);
    expect(find.text('Confirm your email address'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('forgot password opens recovery with login email', (
    tester,
  ) async {
    final controller = _createController();

    await tester.pumpWidget(
      MaterialApp(home: SignedOutEntry(controller: controller)),
    );

    final loginEmailField = find.byType(TextFormField).first;

    await tester.enterText(loginEmailField, 'person@example.com');

    final forgotButton = find.byKey(const ValueKey('forgot-password-button'));

    expect(forgotButton, findsOneWidget);

    await tester.ensureVisible(forgotButton);
    await tester.tap(forgotButton);
    await tester.pumpAndSettle();

    expect(find.text('Recover account'), findsOneWidget);
    expect(find.text('Private beta account recovery'), findsOneWidget);

    final recoveryEmailField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('forgot-password-email')),
    );

    expect(recoveryEmailField.controller!.text, 'person@example.com');
    expect(find.byKey(const ValueKey('recovery-credential')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('shows a prefilled confirmation link', (tester) async {
    final controller = _createController();
    var presentedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SignedOutEntry(
          controller: controller,
          initialConfirmationLink: const EmailConfirmationLink(
            email: 'person@example.com',
            token: 'confirmation-token',
          ),
          onConfirmationLinkPresented: () {
            presentedCount++;
          },
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Confirm your email address'), findsOneWidget);
    expect(presentedCount, 1);

    final emailField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('confirmation-email')),
    );
    final tokenField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('confirmation-token')),
    );

    expect(emailField.controller!.text, 'person@example.com');
    expect(tokenField.controller!.text, 'confirmation-token');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('returns from root confirmation page to login', (tester) async {
    final controller = _createController();

    await tester.pumpWidget(
      MaterialApp(
        home: SignedOutEntry(
          controller: controller,
          initialConfirmationLink: const EmailConfirmationLink(
            email: 'person@example.com',
            token: 'confirmation-token',
          ),
        ),
      ),
    );

    expect(find.text('Confirm your email address'), findsOneWidget);

    final backButton = find.text('Back');

    await tester.ensureVisible(backButton);
    await tester.tap(backButton);
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Fasty'), findsOneWidget);
    expect(find.text('Confirm your email address'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('successful root confirmation opens login with confirmed email', (
    tester,
  ) async {
    final controller = _createController(
      MockClient((request) async {
        expect(
          request.url,
          Uri.parse('http://fasty.test/api/auth/confirm-email'),
        );

        return http.Response(
          '{"message":"Email address confirmed successfully."}',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SignedOutEntry(
          controller: controller,
          initialConfirmationLink: const EmailConfirmationLink(
            email: 'person@example.com',
            token: 'confirmation-token',
          ),
        ),
      ),
    );

    final confirmButton = find.widgetWithText(FilledButton, 'Confirm email');

    await tester.ensureVisible(confirmButton);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Fasty'), findsOneWidget);
    expect(find.text('Confirm your email address'), findsNothing);

    final loginEmailField = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );

    expect(loginEmailField.controller!.text, 'person@example.com');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

AuthController _createController([http.Client? client]) {
  return AuthController(
    api: AuthApi(
      baseUrl: 'http://fasty.test',
      client:
          client ??
          MockClient((request) async {
            return http.Response('', 500);
          }),
    ),
    tokenStore: AuthTokenStore(),
  );
}
