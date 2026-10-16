import 'package:drift/native.dart';
import 'package:fasty/database/app_database.dart';
import 'package:fasty/main.dart';
import 'package:fasty/notes/local_notes_repository.dart';
import 'package:fasty/notes/notes_api.dart';
import 'package:fasty/notes/notes_sync_service.dart';
import 'package:fasty/notes/workspace_state_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'desktop workspace navigation, deletion, and explicit note recovery',
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
      final initial = await store.currentState();
      final homeId = initial.activeWorkspaceId;
      final homeName = initial.activeWorkspace.name;
      final disposable = await store.createWorkspace(name: 'R3 Disposable');
      await repository.createNote(
        id: 'keep-note',
        title: 'Keep this note',
        content: 'Original content survives',
        now: DateTime.utc(2026, 9, 30),
      );
      await store.addNoteToWorkspace(
        workspaceId: disposable,
        noteId: 'keep-note',
      );
      await store.selectWorkspace(disposable);
      await tester.pumpWidget(
        FastyApp(
          repository: repository,
          syncService: sync,
          workspaceStore: store,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('keep-note')), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(homeName).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('keep-note')), findsNothing);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('R3 Disposable').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('keep-note')), findsOneWidget);

      await tester.tap(find.byTooltip('Workspace options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete workspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete workspace'));
      await tester.pumpAndSettle();
      final state = await store.currentState();
      expect(state.workspaces.any((w) => w.id == disposable), isFalse);
      expect(state.containsNoteAnywhere('keep-note'), isFalse);
      expect(find.byKey(const ValueKey('keep-note')), findsNothing);
      final preserved = await database.getNoteById('keep-note');
      expect(preserved!.isDeleted, isFalse);
      expect(preserved.content, 'Original content survives');

      await tester.tap(find.byTooltip('Add existing note'));
      await tester.pumpAndSettle();
      expect(find.text('Keep this note'), findsOneWidget);
      await tester.tap(find.text('Keep this note'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('keep-note')), findsOneWidget);
      expect(
        (await store.currentState()).containsNoteInWorkspace(
          homeId,
          'keep-note',
        ),
        isTrue,
      );
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
