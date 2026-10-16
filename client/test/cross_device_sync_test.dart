import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:fasty/database/app_database.dart';
import 'package:fasty/notes/local_notes_repository.dart';
import 'package:fasty/notes/notes_api.dart';
import 'package:fasty/notes/notes_sync_service.dart';
import 'package:fasty/notes/sync_status.dart';
import 'package:fasty/notes/workspace_state.dart';
import 'package:fasty/notes/workspace_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('cross-device synchronization', () {
    test('phone-created workspace and note converge on Windows', () async {
      final pair = await _DevicePair.create();
      addTearDown(pair.dispose);
      await pair.bootstrap();

      final workspaceId = await pair.phone.workspaceStore.createWorkspace(
        name: 'Phone workspace',
      );
      const noteId = '018f2e70-0000-7000-8000-000000000001';
      await pair.phone.createPlacedNote(
        id: noteId,
        workspaceId: workspaceId,
        title: 'Created on phone',
        content: 'Must appear on Windows in the same workspace.',
        now: DateTime.utc(2026, 7, 25, 8),
      );

      await pair.phone.sync.syncPendingOperations();
      await pair.windows.sync.syncPendingOperations();

      final note = await pair.windows.database.getNoteById(noteId);
      final state = await pair.windows.workspaceStore.currentState();
      expect(note?.title, 'Created on phone');
      expect(
        state.workspaces.singleWhere((item) => item.id == workspaceId).name,
        'Phone workspace',
      );
      expect(state.containsNoteInWorkspace(workspaceId, noteId), isTrue);
      expect(
        state.containsNoteInWorkspace(
          WorkspaceStateDocument.defaultWorkspaceId,
          noteId,
        ),
        isFalse,
      );
      expect(await pair.phone.repository.getPendingOperations(), isEmpty);
      expect(await pair.windows.repository.getPendingOperations(), isEmpty);
    });

    test(
      'deleted workspace does not reassign notes on another device',
      () async {
        final pair = await _DevicePair.create();
        addTearDown(pair.dispose);
        await pair.bootstrap();

        final workspaceId = await pair.phone.workspaceStore.createWorkspace(
          name: 'Temporary workspace',
        );
        const noteId = '018f2e70-0000-7000-8000-000000000002';
        await pair.phone.createPlacedNote(
          id: noteId,
          workspaceId: workspaceId,
          title: 'Must stay unassigned',
          content: 'Workspace deletion must not choose a destination.',
          now: DateTime.utc(2026, 7, 25, 9),
        );
        await pair.phone.sync.syncPendingOperations();
        await pair.windows.sync.syncPendingOperations();

        expect(
          await pair.phone.workspaceStore.deleteWorkspace(workspaceId),
          isTrue,
        );
        await pair.phone.sync.syncPendingOperations();
        await pair.windows.sync.syncPendingOperations();

        final note = await pair.windows.database.getNoteById(noteId);
        final state = await pair.windows.workspaceStore.currentState();
        expect(note, isNotNull);
        expect(note!.isDeleted, isFalse);
        expect(state.workspaces.any((item) => item.id == workspaceId), isFalse);
        expect(state.containsNoteAnywhere(noteId), isFalse);
        expect(state.placements, isEmpty);
      },
    );

    test('edit and delete changes round-trip between devices', () async {
      final pair = await _DevicePair.create();
      addTearDown(pair.dispose);
      await pair.bootstrap();

      const noteId = '018f2e70-0000-7000-8000-000000000003';
      final createdAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 30),
      );
      await pair.phone.createPlacedNote(
        id: noteId,
        workspaceId: WorkspaceStateDocument.defaultWorkspaceId,
        title: 'Original',
        content: 'Original content',
        now: createdAt,
      );
      await pair.phone.sync.syncPendingOperations();
      await pair.windows.sync.syncPendingOperations();

      await pair.windows.repository.updateNote(
        id: noteId,
        title: 'Edited on Windows',
        content: 'The phone receives this edit.',
        createdAt: createdAt,
        updatedAt: createdAt.add(const Duration(minutes: 5)),
      );
      await pair.windows.sync.syncPendingOperations();
      await pair.phone.sync.syncPendingOperations();
      expect(
        (await pair.phone.database.getNoteById(noteId))?.title,
        'Edited on Windows',
      );

      await pair.phone.repository.deleteNote(
        id: noteId,
        updatedAt: createdAt.add(const Duration(minutes: 10)),
      );
      await pair.phone.sync.syncPendingOperations();
      await pair.windows.sync.syncPendingOperations();

      final deleted = await pair.windows.database.getNoteById(noteId);
      expect(deleted, isNotNull);
      expect(deleted!.isDeleted, isTrue);
      expect(deleted.syncStatus, 'synced');
      expect(await pair.windows.database.getActiveNotes(), isEmpty);
    });

    test(
      'offline changes remain queued and retry immediately when requested',
      () async {
        final pair = await _DevicePair.create();
        addTearDown(pair.dispose);
        await pair.bootstrap();

        const noteId = '018f2e70-0000-7000-8000-000000000004';
        await pair.phone.createPlacedNote(
          id: noteId,
          workspaceId: WorkspaceStateDocument.defaultWorkspaceId,
          title: 'Offline note',
          content: 'This survives a network failure.',
          now: DateTime.utc(2026, 7, 25, 11),
        );

        pair.server.online = false;
        await expectLater(
          pair.phone.sync.syncPendingOperations(),
          throwsA(isA<NotesSyncException>()),
        );

        final failed = await pair.phone.database.getOperationsForNote(noteId);
        expect(failed, hasLength(1));
        expect(failed.single.retryCount, 1);
        expect(failed.single.lastError, isNotEmpty);
        expect(failed.single.nextRetryAt, isNotNull);
        expect(pair.phone.sync.status.value.state, SyncState.unavailable);
        expect(
          (await pair.phone.workspaceStore.localSnapshot()).isPending,
          isTrue,
        );

        pair.server.online = true;
        await pair.phone.sync.syncPendingOperations();
        await pair.windows.sync.syncPendingOperations();

        expect(await pair.phone.database.getOperationsForNote(noteId), isEmpty);
        expect(pair.phone.sync.status.value.state, SyncState.synchronized);
        expect(
          (await pair.windows.database.getNoteById(noteId))?.title,
          'Offline note',
        );
        expect(
          (await pair.windows.workspaceStore.currentState())
              .containsNoteAnywhere(noteId),
          isTrue,
        );
      },
    );

    test('stale offline edit accepts the newer server winner', () async {
      final pair = await _DevicePair.create();
      addTearDown(pair.dispose);
      await pair.bootstrap();

      const noteId = '018f2e70-0000-7000-8000-000000000005';
      final createdAt = DateTime.utc(2026, 7, 25, 12);
      await pair.phone.createPlacedNote(
        id: noteId,
        workspaceId: WorkspaceStateDocument.defaultWorkspaceId,
        title: 'Base',
        content: 'Base content',
        now: createdAt,
      );
      await pair.phone.sync.syncPendingOperations();
      await pair.windows.sync.syncPendingOperations();

      await pair.phone.repository.updateNote(
        id: noteId,
        title: 'Newer phone edit',
        content: 'Server winner',
        createdAt: createdAt,
        updatedAt: DateTime.utc(2026, 7, 25, 12, 10),
      );
      await pair.phone.sync.syncPendingOperations();

      await pair.windows.repository.updateNote(
        id: noteId,
        title: 'Older Windows edit',
        content: 'Must be rejected',
        createdAt: createdAt,
        updatedAt: DateTime.utc(2026, 7, 25, 12, 5),
      );
      await pair.windows.sync.syncPendingOperations();

      final winner = await pair.windows.database.getNoteById(noteId);
      expect(winner?.title, 'Newer phone edit');
      expect(winner?.content, 'Server winner');
      expect(winner?.syncStatus, 'synced');
      expect(await pair.windows.database.getOperationsForNote(noteId), isEmpty);
    });

    test(
      'fresh installation adopts remote graph without uploading default state',
      () async {
        final server = _FakeSyncServer()
          ..workspaceState = _workspaceJson(
            id: 'remote-workspace',
            name: 'Remote workspace',
            timestamp: DateTime.utc(2026, 7, 25, 13),
          );
        final device = await _TestDevice.create(server);
        addTearDown(device.dispose);

        await device.sync.syncPendingOperations();

        final state = await device.workspaceStore.currentState();
        expect(state.workspaces, hasLength(1));
        expect(state.activeWorkspace.id, 'remote-workspace');
        expect(state.activeWorkspace.name, 'Remote workspace');
        expect(server.workspacePutCount, 0);
        expect(
          (await device.workspaceStore.localSnapshot()).isPending,
          isFalse,
        );
      },
    );

    test(
      'one note keeps one identity with placements in two workspaces',
      () async {
        final pair = await _DevicePair.create();
        addTearDown(pair.dispose);
        await pair.bootstrap();

        final secondWorkspaceId = await pair.phone.workspaceStore
            .createWorkspace(name: 'Shared destination');
        const noteId = '018f2e70-0000-7000-8000-000000000006';
        await pair.phone.createPlacedNote(
          id: noteId,
          workspaceId: WorkspaceStateDocument.defaultWorkspaceId,
          title: 'Shared identity',
          content: 'One note, two placements.',
          now: DateTime.utc(2026, 7, 25, 14),
        );
        await pair.phone.workspaceStore.addNoteToWorkspace(
          workspaceId: secondWorkspaceId,
          noteId: noteId,
        );
        await pair.phone.sync.syncPendingOperations();
        await pair.windows.sync.syncPendingOperations();

        final state = await pair.windows.workspaceStore.currentState();
        final placements = state.placements
            .where((item) => item.noteId == noteId)
            .toList(growable: false);
        expect(placements, hasLength(2));
        expect(placements.map((item) => item.workspaceId).toSet(), {
          WorkspaceStateDocument.defaultWorkspaceId,
          secondWorkspaceId,
        });
        expect(
          (await pair.windows.database.getActiveNotes()).where(
            (item) => item.id == noteId,
          ),
          hasLength(1),
        );
      },
    );

    test(
      'phone metadata change cannot erase a Windows-created placement',
      () async {
        final pair = await _DevicePair.create();
        addTearDown(pair.dispose);
        await pair.bootstrap();

        const noteId = '018f2e70-0000-7000-8000-000000000007';
        await pair.windows.createPlacedNote(
          id: noteId,
          workspaceId: WorkspaceStateDocument.defaultWorkspaceId,
          title: 'Created on Windows',
          content: 'The phone must merge this placement.',
          now: DateTime.utc(2026, 7, 25, 15),
        );
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await pair.phone.workspaceStore.renameWorkspace(
          WorkspaceStateDocument.defaultWorkspaceId,
          'Renamed on phone',
        );

        await pair.windows.sync.syncPendingOperations();
        await pair.phone.sync.syncPendingOperations();
        await pair.windows.sync.syncPendingOperations();

        final phoneState = await pair.phone.workspaceStore.currentState();
        final windowsState = await pair.windows.workspaceStore.currentState();
        expect(phoneState.activeWorkspace.name, 'Renamed on phone');
        expect(windowsState.activeWorkspace.name, 'Renamed on phone');
        expect(
          phoneState.containsNoteInWorkspace(
            WorkspaceStateDocument.defaultWorkspaceId,
            noteId,
          ),
          isTrue,
        );
        expect(
          windowsState.containsNoteInWorkspace(
            WorkspaceStateDocument.defaultWorkspaceId,
            noteId,
          ),
          isTrue,
        );
        expect(
          (await pair.phone.database.getNoteById(noteId))?.isDeleted,
          isFalse,
        );
        expect(
          (await pair.windows.database.getNoteById(noteId))?.isDeleted,
          isFalse,
        );
      },
    );
  });
}

class _DevicePair {
  _DevicePair(this.server, this.phone, this.windows);

  final _FakeSyncServer server;
  final _TestDevice phone;
  final _TestDevice windows;

  static Future<_DevicePair> create() async {
    final server = _FakeSyncServer();
    final phone = await _TestDevice.create(server);
    final windows = await _TestDevice.create(server);
    return _DevicePair(server, phone, windows);
  }

  Future<void> bootstrap() async {
    await phone.sync.syncPendingOperations();
    await windows.sync.syncPendingOperations();
  }

  Future<void> dispose() async {
    await phone.dispose();
    await windows.dispose();
  }
}

class _TestDevice {
  _TestDevice(
    this.database,
    this.repository,
    this.workspaceStore,
    this.api,
    this.sync,
  );

  final AppDatabase database;
  final LocalNotesRepository repository;
  final WorkspaceStateStore workspaceStore;
  final NotesApi api;
  final NotesSyncService sync;

  static Future<_TestDevice> create(_FakeSyncServer server) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = LocalNotesRepository(database);
    final workspaceStore = WorkspaceStateStore(database);
    await workspaceStore.ensureInitialized();
    final api = NotesApi(baseUrl: 'http://fasty.test', client: server.client());
    final sync = NotesSyncService(
      database: database,
      api: api,
      workspaceStateStore: workspaceStore,
    );
    return _TestDevice(database, repository, workspaceStore, api, sync);
  }

  Future<void> createPlacedNote({
    required String id,
    required String workspaceId,
    required String title,
    required String content,
    required DateTime now,
  }) async {
    await repository.createNote(
      id: id,
      title: title,
      content: content,
      now: now,
    );
    await workspaceStore.addNoteToWorkspace(
      workspaceId: workspaceId,
      noteId: id,
    );
  }

  Future<void> dispose() async {
    api.close();
    await workspaceStore.dispose();
    await database.close();
  }
}

class _FakeSyncServer {
  final Map<String, Map<String, dynamic>> _notes = {};

  bool online = true;
  Map<String, dynamic>? workspaceState;
  int workspacePutCount = 0;

  MockClient client() => MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    if (!online) {
      throw http.ClientException('Simulated network outage', request.url);
    }

    final path = request.url.path;
    if (request.method == 'GET' && path == '/api/v1/notes') {
      return _json(_notes.values.toList(growable: false));
    }

    if (path.startsWith('/api/v1/notes/')) {
      final noteId = path.substring('/api/v1/notes/'.length);
      if (request.method == 'PUT') {
        return _upsertNote(noteId, request.body);
      }
      if (request.method == 'DELETE') {
        return _deleteNote(noteId, request.url.queryParameters['updatedAt']);
      }
    }

    if (request.method == 'GET' && path == '/api/v1/workspace-state') {
      return workspaceState == null
          ? http.Response('', 204)
          : _json(_clone(workspaceState!));
    }

    if (request.method == 'PUT' && path == '/api/v1/workspace-state') {
      workspacePutCount++;
      final incoming = Map<String, dynamic>.from(
        jsonDecode(request.body) as Map,
      );
      final stored = workspaceState;
      if (stored == null ||
          DateTime.parse(
            incoming['updatedAt'] as String,
          ).isAfter(DateTime.parse(stored['updatedAt'] as String))) {
        workspaceState = _clone(incoming);
      }
      return _json(_clone(workspaceState!));
    }

    return http.Response('Unexpected ${request.method} $path', 500);
  }

  http.Response _upsertNote(String noteId, String body) {
    final incoming = Map<String, dynamic>.from(jsonDecode(body) as Map);
    final existing = _notes[noteId];
    if (existing == null ||
        DateTime.parse(
          incoming['updatedAt'] as String,
        ).isAfter(DateTime.parse(existing['updatedAt'] as String))) {
      _notes[noteId] = {
        'id': noteId,
        'title': incoming['title'],
        'content': incoming['content'],
        'createdAt': incoming['createdAt'],
        'updatedAt': incoming['updatedAt'],
        'isDeleted': false,
      };
    }
    return _json(_clone(_notes[noteId]!));
  }

  http.Response _deleteNote(String noteId, String? updatedAtValue) {
    final existing = _notes[noteId];
    if (existing != null) {
      final deletedAt = DateTime.parse(updatedAtValue!);
      if (deletedAt.isAfter(DateTime.parse(existing['updatedAt'] as String))) {
        existing['updatedAt'] = deletedAt.toUtc().toIso8601String();
        existing['isDeleted'] = true;
      }
    }
    return http.Response('', 204);
  }

  http.Response _json(Object value) => http.Response(
    jsonEncode(value),
    200,
    headers: const {'content-type': 'application/json'},
  );

  Map<String, dynamic> _clone(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
}

Map<String, dynamic> _workspaceJson({
  required String id,
  required String name,
  required DateTime timestamp,
}) {
  final serialized = timestamp.toUtc().toIso8601String();
  return {
    'schemaVersion': WorkspaceStateDocument.currentSchemaVersion,
    'activeWorkspaceId': id,
    'workspaces': [
      {
        'id': id,
        'name': name,
        'colorValue': 0xFF625BEB,
        'cameraX': 0,
        'cameraY': 0,
        'scale': 1,
        'createdAt': serialized,
        'updatedAt': serialized,
      },
    ],
    'placements': <Object>[],
    'links': <Object>[],
    'updatedAt': serialized,
  };
}
