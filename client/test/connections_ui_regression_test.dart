import 'package:drift/native.dart';
import 'package:fasty/database/app_database.dart';
import 'package:fasty/main.dart';
import 'package:fasty/notes/local_notes_repository.dart';
import 'package:fasty/notes/notes_api.dart';
import 'package:fasty/notes/notes_sync_service.dart';
import 'package:fasty/notes/workspace_state_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fasty/notes/stable_workspace_canvas.dart';

void main() {
  testWidgets(
    'desktop connection create, follow, and delete preserve both notes',
    (tester) async {
      _useDesktopSurface(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = LocalNotesRepository(database);
      final store = WorkspaceStateStore(database);
      final api = NotesApi(baseUrl: 'http://localhost:8080');
      final sync = NotesSyncService(
        database: database,
        api: api,
        workspaceStateStore: store,
      );
      final workspaceId = (await store.currentState()).activeWorkspaceId;
      for (final id in ['source', 'target']) {
        await repository.createNote(
          id: id,
          title: 'R3 $id',
          content: 'Keep $id content',
          now: DateTime.utc(2026, 9, 30),
        );
        await store.addNoteToWorkspace(workspaceId: workspaceId, noteId: id);
      }
      final target = (await store.currentState()).placementFor(
        workspaceId,
        'target',
      )!;
      await store.updatePlacement(target.copyWith(x: 1800, y: 1000));
      await tester.pumpWidget(
        FastyApp(
          repository: repository,
          syncService: sync,
          workspaceStore: store,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('source')),
          matching: find.byTooltip('Note options'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect to note'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'R3 link',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      final linked = await store.currentState();
      expect(linked.links, hasLength(1));
      expect(linked.links.single.sourceNoteId, 'source');
      expect(linked.links.single.targetNoteId, 'target');
      expect(linked.links.single.label, 'R3 link');
      expect(linked.links.single.directed, isTrue);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('source')),
          matching: find.byTooltip('Note options'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connected notes'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('R3 target'),
        ),
      );
      await tester.pumpAndSettle();
      final canvasCenter = tester.getCenter(find.byType(StableWorkspaceCanvas));
      final targetCenter = tester.getCenter(
        find.byKey(const ValueKey('target')),
      );
      expect(targetCenter.dx, closeTo(canvasCenter.dx, 1));
      expect(targetCenter.dy, closeTo(canvasCenter.dy, 1));

      await tester.tap(find.byTooltip('Manage connections'));
      await tester.pumpAndSettle();
      expect(find.text('R3 source → R3 target'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete connection'));
      await tester.pumpAndSettle();
      expect((await store.currentState()).links, isEmpty);
      for (final id in ['source', 'target']) {
        final note = await database.getNoteById(id);
        expect(note!.isDeleted, isFalse);
        expect(note.content, 'Keep $id content');
      }
      expect(tester.takeException(), isNull);
      await _disposeAppAndDatabase(tester, store, database);
    },
  );
}

void _useDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _disposeAppAndDatabase(
  WidgetTester tester,
  WorkspaceStateStore workspaceStore,
  AppDatabase database,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await workspaceStore.dispose();
  await database.close();
  await tester.pump(const Duration(milliseconds: 1));
}
