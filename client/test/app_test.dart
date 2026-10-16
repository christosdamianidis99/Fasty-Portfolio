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
  testWidgets('shows empty local notes state', (tester) async {
    _useDesktopSurface(tester);
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final repository = LocalNotesRepository(database);
    final workspaceStore = WorkspaceStateStore(database);
    final api = NotesApi(baseUrl: 'http://localhost:8080');
    final syncService = NotesSyncService(
      database: database,
      api: api,
      workspaceStateStore: workspaceStore,
    );

    await tester.pumpWidget(
      FastyApp(
        repository: repository,
        syncService: syncService,
        workspaceStore: workspaceStore,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Build your workspace'), findsOneWidget);
    expect(find.text('Create your first note'), findsOneWidget);
    expect(find.text('Workspace'), findsWidgets);
    expect(find.text('Trash'), findsOneWidget);

    await _disposeAppAndDatabase(tester, workspaceStore, database);
  });

  testWidgets('Trash snackbar disappears automatically while keeping Undo', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final repository = LocalNotesRepository(database);
    final workspaceStore = WorkspaceStateStore(database);
    final api = NotesApi(baseUrl: 'http://localhost:8080');
    final syncService = NotesSyncService(
      database: database,
      api: api,
      workspaceStateStore: workspaceStore,
    );

    const noteId = 'trash-snackbar-test-note';

    await repository.createNote(
      id: noteId,
      title: 'Delete me',
      content: 'This note exercises the Trash snackbar.',
      now: DateTime.utc(2026, 8, 21),
    );

    final workspace = await workspaceStore.currentState();
    await workspaceStore.addNoteToWorkspace(
      workspaceId: workspace.activeWorkspaceId,
      noteId: noteId,
    );

    await tester.pumpWidget(
      FastyApp(
        repository: repository,
        syncService: syncService,
        workspaceStore: workspaceStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(noteId)), findsOneWidget);

    await tester.tap(find.byTooltip('Note options'));
    await tester.pumpAndSettle();

    expect(find.text('Move to Trash'), findsOneWidget);

    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();

    const snackbarText = 'Moved to Trash · Recoverable for 14 days';

    expect(find.text(snackbarText), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text(snackbarText), findsNothing);
    expect(find.text('Undo'), findsNothing);

    await _disposeAppAndDatabase(tester, workspaceStore, database);
  });
  testWidgets('Trash snackbar Undo restores the deleted note', (tester) async {
    _useDesktopSurface(tester);
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final repository = LocalNotesRepository(database);
    final workspaceStore = WorkspaceStateStore(database);
    final api = NotesApi(baseUrl: 'http://localhost:8080');
    final syncService = NotesSyncService(
      database: database,
      api: api,
      workspaceStateStore: workspaceStore,
    );

    const noteId = 'trash-snackbar-undo-test-note';

    await repository.createNote(
      id: noteId,
      title: 'Restore me',
      content: 'Undo should restore this note.',
      now: DateTime.utc(2026, 8, 21),
    );

    final workspace = await workspaceStore.currentState();
    await workspaceStore.addNoteToWorkspace(
      workspaceId: workspace.activeWorkspaceId,
      noteId: noteId,
    );

    await tester.pumpWidget(
      FastyApp(
        repository: repository,
        syncService: syncService,
        workspaceStore: workspaceStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(noteId)), findsOneWidget);

    await tester.tap(find.byTooltip('Note options'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(noteId)), findsNothing);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(noteId)), findsOneWidget);
    expect(find.text('Note restored to its workspace.'), findsOneWidget);

    await _disposeAppAndDatabase(tester, workspaceStore, database);
  });
  testWidgets('keeps move and resize gestures active while held', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final repository = LocalNotesRepository(database);
    final workspaceStore = WorkspaceStateStore(database);
    final api = NotesApi(baseUrl: 'http://localhost:8080');
    final syncService = NotesSyncService(
      database: database,
      api: api,
      workspaceStateStore: workspaceStore,
    );

    const noteId = 'gesture-test-note';

    await repository.createNote(
      id: noteId,
      title: 'Drag me',
      content: 'The card must remain mounted during a held gesture.',
      now: DateTime.utc(2026, 7, 24),
    );
    final workspace = await workspaceStore.currentState();
    await workspaceStore.addNoteToWorkspace(
      workspaceId: workspace.activeWorkspaceId,
      noteId: noteId,
    );

    await tester.pumpWidget(
      FastyApp(
        repository: repository,
        syncService: syncService,
        workspaceStore: workspaceStore,
      ),
    );
    await tester.pumpAndSettle();

    final noteFinder = find.byKey(const ValueKey(noteId));
    expect(noteFinder, findsOneWidget);

    final initialPosition = tester.getTopLeft(noteFinder);
    final headerPoint = initialPosition + const Offset(90, 28);
    final moveGesture = await tester.startGesture(headerPoint);

    await moveGesture.moveBy(const Offset(40, 20));
    await tester.pump();
    expect(noteFinder, findsOneWidget);

    await moveGesture.moveBy(const Offset(40, 20));
    await tester.pump();
    expect(noteFinder, findsOneWidget);

    await moveGesture.up();
    await tester.pump();

    final movedPosition = tester.getTopLeft(noteFinder);
    expect(movedPosition.dx, closeTo(initialPosition.dx + 80, 1));
    expect(movedPosition.dy, closeTo(initialPosition.dy + 40, 1));

    final initialSize = tester.getSize(noteFinder);
    final resizeHandle = find.byWidgetPredicate(
      (widget) =>
          widget is MouseRegion &&
          widget.cursor == SystemMouseCursors.resizeDownRight,
      description: 'floating note resize handle',
    );
    expect(resizeHandle, findsOneWidget);

    final resizeGesture = await tester.startGesture(
      tester.getCenter(resizeHandle),
    );

    await resizeGesture.moveBy(const Offset(40, 30));
    await tester.pump();
    expect(noteFinder, findsOneWidget);

    await resizeGesture.moveBy(const Offset(40, 30));
    await tester.pump();
    expect(noteFinder, findsOneWidget);

    await resizeGesture.moveBy(const Offset(40, 30));
    await tester.pump();
    expect(noteFinder, findsOneWidget);

    await resizeGesture.up();
    await tester.pump();

    final resizedSize = tester.getSize(noteFinder);
    expect(resizedSize.width, closeTo(initialSize.width + 80, 1));
    expect(resizedSize.height, closeTo(initialSize.height + 60, 1));

    final state = await workspaceStore.currentState();
    final placement = state.placementFor(state.activeWorkspaceId, noteId);
    expect(placement, isNotNull);
    expect(placement!.x, closeTo(180, 1));
    expect(placement.y, closeTo(140, 1));
    expect(placement.width, closeTo(350, 1));
    expect(placement.height, closeTo(290, 1));

    await _disposeAppAndDatabase(tester, workspaceStore, database);
  });
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
