import 'package:drift/native.dart';
import 'package:fasty/auth/auth_api.dart';
import 'package:fasty/auth/auth_controller.dart';
import 'package:fasty/auth/auth_token_store.dart';
import 'package:fasty/auth/email_confirmation_link.dart';
import 'package:fasty/auth/password_reset_link.dart';
import 'package:fasty/database/app_database.dart';
import 'package:fasty/main.dart';
import 'package:fasty/notes/local_notes_repository.dart';
import 'package:fasty/notes/notes_api.dart';
import 'package:fasty/notes/notes_sync_service.dart';
import 'package:fasty/notes/workspace_state_store.dart';
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

  testWidgets('shows login when no initial confirmation link exists', (
    tester,
  ) async {
    final fixture = _createFixture();

    await fixture.authController.initialize();

    await tester.pumpWidget(
      FastyApp(
        repository: fixture.repository,
        syncService: fixture.syncService,
        workspaceStore: fixture.workspaceStore,
        authController: fixture.authController,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Welcome to Fasty'), findsOneWidget);
    expect(find.text('Confirm your email address'), findsNothing);

    await fixture.dispose(tester);
  });

  testWidgets('opens initial confirmation link for a signed-out user', (
    tester,
  ) async {
    final fixture = _createFixture();

    await fixture.authController.initialize();

    await tester.pumpWidget(
      FastyApp(
        repository: fixture.repository,
        syncService: fixture.syncService,
        workspaceStore: fixture.workspaceStore,
        authController: fixture.authController,
        initialConfirmationLink: const EmailConfirmationLink(
          email: 'person@example.com',
          token: 'confirmation-token',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Confirm your email address'), findsOneWidget);

    final emailField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('confirmation-email')),
    );
    final tokenField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('confirmation-token')),
    );

    expect(emailField.controller!.text, 'person@example.com');
    expect(tokenField.controller!.text, 'confirmation-token');

    await fixture.dispose(tester);
  });
  testWidgets('opens initial password reset link for a signed-out user', (
    tester,
  ) async {
    final fixture = _createFixture();

    await fixture.authController.initialize();

    await tester.pumpWidget(
      FastyApp(
        repository: fixture.repository,
        syncService: fixture.syncService,
        workspaceStore: fixture.workspaceStore,
        authController: fixture.authController,
        initialPasswordResetLink: const PasswordResetLink(
          email: 'person@example.com',
          token: 'reset-token',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Reset your password'), findsOneWidget);

    final emailField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('reset-password-email')),
    );

    final tokenField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('reset-password-token')),
    );

    expect(emailField.controller!.text, 'person@example.com');

    expect(tokenField.controller!.text, 'reset-token');

    await fixture.dispose(tester);
  });
}

_TestFixture _createFixture() {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  final repository = LocalNotesRepository(database);
  final workspaceStore = WorkspaceStateStore(database);

  final authController = AuthController(
    api: AuthApi(
      baseUrl: 'http://fasty.test',
      client: MockClient((request) async {
        return http.Response('', 500);
      }),
    ),
    tokenStore: AuthTokenStore(),
  );

  final notesApi = NotesApi(
    baseUrl: 'http://fasty.test',
    accessTokenProvider: authController.getValidAccessToken,
  );

  final syncService = NotesSyncService(
    database: database,
    api: notesApi,
    workspaceStateStore: workspaceStore,
  );

  return _TestFixture(
    database: database,
    repository: repository,
    workspaceStore: workspaceStore,
    authController: authController,
    syncService: syncService,
  );
}

class _TestFixture {
  const _TestFixture({
    required this.database,
    required this.repository,
    required this.workspaceStore,
    required this.authController,
    required this.syncService,
  });

  final AppDatabase database;
  final LocalNotesRepository repository;
  final WorkspaceStateStore workspaceStore;
  final AuthController authController;
  final NotesSyncService syncService;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    authController.dispose();
    await workspaceStore.dispose();
    await database.close();
  }
}
