import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:fasty/database/app_database.dart';
import 'package:fasty/notes/notes_api.dart';
import 'package:fasty/notes/notes_sync_service.dart';
import 'package:fasty/notes/workspace_state.dart';
import 'package:fasty/notes/workspace_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'failed operation does not prevent later operations from syncing',
    () async {
      const firstId = 'first-note';
      const secondId = 'second-note';

      final firstCreatedAt = DateTime.utc(2026, 7, 23, 10);
      final secondCreatedAt = DateTime.utc(2026, 7, 23, 11);

      await database.saveLocalNote(
        LocalNotesCompanion.insert(
          id: firstId,
          title: 'First note',
          content: 'This upload will fail',
          createdAt: firstCreatedAt,
          updatedAt: firstCreatedAt,
          syncStatus: const drift.Value('pending'),
          isDeleted: const drift.Value(false),
        ),
      );

      await database.saveLocalNote(
        LocalNotesCompanion.insert(
          id: secondId,
          title: 'Second note',
          content: 'This upload will succeed',
          createdAt: secondCreatedAt,
          updatedAt: secondCreatedAt,
          syncStatus: const drift.Value('pending'),
          isDeleted: const drift.Value(false),
        ),
      );

      await database.addOutboxOperation(
        noteId: firstId,
        operation: 'create',
        createdAt: firstCreatedAt,
      );

      await database.addOutboxOperation(
        noteId: secondId,
        operation: 'create',
        createdAt: secondCreatedAt,
      );

      final client = MockClient((request) async {
        if (request.method == 'PUT' && request.url.path.endsWith('/$firstId')) {
          return http.Response('Upload failed', 500);
        }

        if (request.method == 'PUT' &&
            request.url.path.endsWith('/$secondId')) {
          return http.Response(
            jsonEncode({
              'id': secondId,
              'title': 'Second note',
              'content': 'This upload will succeed',
              'createdAt': secondCreatedAt.toIso8601String(),
              'updatedAt': secondCreatedAt.toIso8601String(),
              'isDeleted': false,
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }

        if (request.method == 'GET' && request.url.path == '/api/v1/notes') {
          return http.Response(
            '[]',
            200,
            headers: const {'content-type': 'application/json'},
          );
        }

        return http.Response('Unexpected request', 500);
      });

      final api = NotesApi(baseUrl: 'http://localhost', client: client);
      final syncService = NotesSyncService(database: database, api: api);

      await expectLater(
        syncService.syncPendingOperations(),
        throwsA(
          isA<NotesSyncException>()
              .having(
                (error) => error.successfulOperations,
                'successful operations',
                1,
              )
              .having(
                (error) => error.failureMessages.length,
                'failure count',
                1,
              ),
        ),
      );

      final firstNote = await database.getNoteById(firstId);
      final secondNote = await database.getNoteById(secondId);
      final firstOperations = await database.getOperationsForNote(firstId);
      final secondOperations = await database.getOperationsForNote(secondId);

      expect(firstNote, isNotNull);
      expect(firstNote!.syncStatus, 'pending');
      expect(firstOperations, hasLength(1));
      expect(firstOperations.single.retryCount, 1);
      expect(firstOperations.single.lastError, isNotNull);

      expect(secondNote, isNotNull);
      expect(secondNote!.syncStatus, 'synced');
      expect(secondOperations, isEmpty);

      api.close();
    },
  );

  test('overlapping sync calls process an operation only once', () async {
    const id = 'single-upload-note';
    final createdAt = DateTime.utc(2026, 7, 23, 12);

    await database.saveLocalNote(
      LocalNotesCompanion.insert(
        id: id,
        title: 'Single upload',
        content: 'Must upload once',
        createdAt: createdAt,
        updatedAt: createdAt,
        syncStatus: const drift.Value('pending'),
        isDeleted: const drift.Value(false),
      ),
    );

    await database.addOutboxOperation(
      noteId: id,
      operation: 'create',
      createdAt: createdAt,
    );

    final uploadStarted = Completer<void>();
    final allowUploadToFinish = Completer<void>();
    var uploadCount = 0;
    var downloadCount = 0;

    final client = MockClient((request) async {
      if (request.method == 'PUT' && request.url.path.endsWith('/$id')) {
        uploadCount++;

        if (!uploadStarted.isCompleted) {
          uploadStarted.complete();
        }

        await allowUploadToFinish.future;

        return http.Response(
          jsonEncode({
            'id': id,
            'title': 'Single upload',
            'content': 'Must upload once',
            'createdAt': createdAt.toIso8601String(),
            'updatedAt': createdAt.toIso8601String(),
            'isDeleted': false,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }

      if (request.method == 'GET' && request.url.path == '/api/v1/notes') {
        downloadCount++;
        return http.Response(
          '[]',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }

      return http.Response('Unexpected request', 500);
    });

    final api = NotesApi(baseUrl: 'http://localhost', client: client);
    final syncService = NotesSyncService(database: database, api: api);

    final firstSync = syncService.syncPendingOperations();
    await uploadStarted.future;

    final secondSync = syncService.syncPendingOperations();
    expect(uploadCount, 1);

    allowUploadToFinish.complete();
    final summaries = await Future.wait([firstSync, secondSync]);

    final note = await database.getNoteById(id);
    final operations = await database.getOperationsForNote(id);

    expect(identical(summaries[0], summaries[1]), isTrue);
    expect(uploadCount, 1);
    expect(downloadCount, 1);
    expect(operations, isEmpty);
    expect(note, isNotNull);
    expect(note!.syncStatus, 'synced');

    api.close();
  });

  test(
    'remote workspace deletion does not move notes into another workspace',
    () async {
      const noteId = 'unassigned-note';
      final timestamp = DateTime.utc(2026, 7, 24, 14);
      final store = WorkspaceStateStore(database);

      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/api/v1/notes') {
          return http.Response(
            jsonEncode([
              {
                'id': noteId,
                'title': 'No automatic move',
                'content': 'This note belonged only to a deleted workspace.',
                'createdAt': timestamp.toIso8601String(),
                'updatedAt': timestamp.toIso8601String(),
                'isDeleted': false,
              },
            ]),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }

        if (request.method == 'GET' &&
            request.url.path == '/api/v1/workspace-state') {
          return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'activeWorkspaceId': WorkspaceStateDocument.defaultWorkspaceId,
              'workspaces': [
                {
                  'id': WorkspaceStateDocument.defaultWorkspaceId,
                  'name': 'Remaining workspace',
                  'colorValue': 0xFF625BEB,
                  'cameraX': 0,
                  'cameraY': 0,
                  'scale': 1,
                  'createdAt': timestamp.toIso8601String(),
                  'updatedAt': timestamp.toIso8601String(),
                },
              ],
              'placements': <Object>[],
              'links': <Object>[],
              'updatedAt': timestamp.toIso8601String(),
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }

        return http.Response('Unexpected request', 500);
      });

      final api = NotesApi(baseUrl: 'http://localhost', client: client);
      final syncService = NotesSyncService(
        database: database,
        api: api,
        workspaceStateStore: store,
      );

      await syncService.syncPendingOperations();

      final note = await database.getNoteById(noteId);
      final workspace = await store.currentState();
      expect(note, isNotNull);
      expect(workspace.containsNoteAnywhere(noteId), isFalse);
      expect(workspace.placements, isEmpty);

      api.close();
      await store.dispose();
    },
  );
}
