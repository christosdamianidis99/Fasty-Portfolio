import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fasty/account/account_resources.dart';
import 'package:fasty/auth/auth_api.dart';
import 'package:fasty/auth/auth_controller.dart';
import 'package:fasty/auth/auth_token_store.dart';
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

  testWidgets('isolates resources when the signed-in account changes', (
    tester,
  ) async {
    final authController = AuthController(
      api: AuthApi(
        baseUrl: 'http://fasty.test',
        client: MockClient(_handleAuthRequest),
      ),
      tokenStore: AuthTokenStore(),
    );

    await authController.initialize();

    final createdEmails = <String>[];
    final resourcesByEmail = <String, _TrackedResources>{};
    final tokenProviders = <String, AccessTokenProvider>{};

    AccountResources createResources({
      required String email,
      required String apiBaseUrl,
      required AccessTokenProvider accessTokenProvider,
    }) {
      createdEmails.add(email);
      tokenProviders[email] = accessTokenProvider;

      final database = _TrackingDatabase();
      final repository = LocalNotesRepository(database);
      final workspaceStore = WorkspaceStateStore(database);
      final notesApi = NotesApi(
        baseUrl: apiBaseUrl,
        accessTokenProvider: accessTokenProvider,
        client: MockClient((request) async {
          return http.Response('Service unavailable', 503);
        }),
      );
      final syncService = NotesSyncService(
        database: database,
        api: notesApi,
        workspaceStateStore: workspaceStore,
      );

      final resources = _TrackedResources(
        accountResources: AccountResources(
          database: database,
          repository: repository,
          notesApi: notesApi,
          syncService: syncService,
          workspaceStore: workspaceStore,
        ),
        database: database,
      );

      resourcesByEmail[email] = resources;
      return resources.accountResources;
    }

    await tester.pumpWidget(
      FastyApp.production(
        apiBaseUrl: 'http://fasty.test',
        authController: authController,
        accountResourcesFactory: createResources,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Fasty'), findsOneWidget);
    expect(createdEmails, isEmpty);

    final firstLogin = await authController.login(
      email: 'First@Example.com',
      password: 'password',
      deviceName: 'Test device',
    );

    expect(firstLogin, isTrue);

    await tester.pumpAndSettle();

    expect(createdEmails, ['first@example.com']);
    expect(
      find.byKey(const ValueKey('account-first@example.com')),
      findsOneWidget,
    );
    expect(
      await tokenProviders['first@example.com']!(),
      'access-first@example.com',
    );

    final secondLogin = await authController.login(
      email: 'second@example.com',
      password: 'password',
      deviceName: 'Test device',
    );

    expect(secondLogin, isTrue);

    await tester.pumpAndSettle();

    expect(createdEmails, ['first@example.com', 'second@example.com']);
    expect(await tokenProviders['first@example.com']!(), isNull);
    expect(
      await tokenProviders['second@example.com']!(),
      'access-second@example.com',
    );
    expect(resourcesByEmail['first@example.com']!.database.wasClosed, isTrue);
    expect(resourcesByEmail['second@example.com']!.database.wasClosed, isFalse);
    expect(
      find.byKey(const ValueKey('account-first@example.com')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('account-second@example.com')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(resourcesByEmail['second@example.com']!.database.wasClosed, isTrue);

    authController.dispose();
  });
}

Future<http.Response> _handleAuthRequest(http.Request request) async {
  if (request.url.path == '/api/auth/login') {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final email = (body['email'] as String).trim().toLowerCase();

    return http.Response(
      jsonEncode({
        'email': email,
        'accessToken': 'access-$email',
        'accessTokenExpiresAt': '2099-01-01T00:00:00Z',
        'refreshToken': 'refresh-$email',
        'refreshTokenExpiresAt': '2099-02-01T00:00:00Z',
        'refreshSessionId': 'session-$email',
      }),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }

  if (request.url.path == '/api/auth/logout') {
    return http.Response('', 204);
  }

  return http.Response('Not found', 404);
}

class _TrackedResources {
  const _TrackedResources({
    required this.accountResources,
    required this.database,
  });

  final AccountResources accountResources;
  final _TrackingDatabase database;
}

class _TrackingDatabase extends AppDatabase {
  _TrackingDatabase() : super.forTesting(NativeDatabase.memory());

  bool wasClosed = false;

  @override
  Future<void> close() async {
    wasClosed = true;
    await super.close();
  }
}
