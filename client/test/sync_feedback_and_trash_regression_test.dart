import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fasty/database/app_database.dart';
import 'package:fasty/notes/notes_api.dart';
import 'package:fasty/notes/notes_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'overlapping sync requests share the real synchronization result',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final requestStarted = Completer<void>();
      final releaseRequest = Completer<void>();
      var requestCount = 0;
      final api = NotesApi(
        baseUrl: 'http://fasty.test',
        client: MockClient((request) async {
          requestCount++;
          if (!requestStarted.isCompleted) {
            requestStarted.complete();
          }
          await releaseRequest.future;
          return http.Response('[]', 200);
        }),
      );
      addTearDown(api.close);

      final service = NotesSyncService(database: database, api: api);
      final firstSync = service.syncPendingOperations();
      await requestStarted.future;
      final secondSync = service.syncPendingOperations();

      releaseRequest.complete();
      final results = await Future.wait([firstSync, secondSync]);

      expect(requestCount, 1);
      expect(results, hasLength(2));
      expect(
        results.every((result) => !result.skippedBecauseAlreadyRunning),
        isTrue,
      );
      expect(
        results.every((result) => result.remainingOperations == 0),
        isTrue,
      );
    },
  );

  test('fresh device imports recent server deletions into Trash', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final now = DateTime.now().toUtc();
    final deletedAt = now.subtract(const Duration(days: 2));
    final api = NotesApi(
      baseUrl: 'http://fasty.test',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'id': '018f2e70-0000-7000-8000-000000000099',
              'title': 'Deleted elsewhere',
              'content': 'Visible in the shared Trash.',
              'createdAt': now
                  .subtract(const Duration(days: 5))
                  .toIso8601String(),
              'updatedAt': deletedAt.toIso8601String(),
              'isDeleted': true,
            },
          ]),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);

    final service = NotesSyncService(database: database, api: api);
    await service.syncPendingOperations();

    final deletedNotes = await database.watchDeletedNotes().first;
    expect(deletedNotes, hasLength(1));
    expect(deletedNotes.single.title, 'Deleted elsewhere');
    expect(deletedNotes.single.syncStatus, 'synced');
  });

  test('fresh device does not import expired server deletions', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final now = DateTime.now().toUtc();
    final api = NotesApi(
      baseUrl: 'http://fasty.test',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'id': '018f2e70-0000-7000-8000-000000000100',
              'title': 'Expired deletion',
              'content': 'Must remain purged.',
              'createdAt': now
                  .subtract(const Duration(days: 30))
                  .toIso8601String(),
              'updatedAt': now
                  .subtract(const Duration(days: 15))
                  .toIso8601String(),
              'isDeleted': true,
            },
          ]),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);

    final service = NotesSyncService(database: database, api: api);
    await service.syncPendingOperations();

    expect(await database.watchDeletedNotes().first, isEmpty);
  });
}
