import 'dart:io';
import 'package:drift/native.dart';
import 'package:fasty/database/app_database.dart';
import 'package:fasty/notes/local_notes_repository.dart';
import 'package:fasty/notes/workspace_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'disk restart preserves pending notes, workspace, pin and connections',
    () async {
      final directory = await Directory.systemTemp.createTemp('fasty-r3-disk-');
      final file = File('${directory.path}/notes.sqlite');
      var database = AppDatabase.forTesting(NativeDatabase(file));
      var store = WorkspaceStateStore(database);
      addTearDown(() async {
        await store.dispose();
        await database.close();
        await directory.delete(recursive: true);
      });
      final repository = LocalNotesRepository(database);
      final workspace = await store.createWorkspace(
        name: 'Persisted workspace',
      );
      for (final id in ['source', 'target']) {
        await repository.createNote(
          id: id,
          title: id,
          content: '- [ ] Survive restart',
          now: DateTime.utc(2026, 9, 30),
        );
        await store.addNoteToWorkspace(workspaceId: workspace, noteId: id);
      }
      await store.selectWorkspace(workspace);
      await store.setNotePinned(
        workspaceId: workspace,
        noteId: 'source',
        pinned: true,
      );
      final link = await store.createLink(
        workspaceId: workspace,
        sourceNoteId: 'source',
        targetNoteId: 'target',
        colorValue: 0xFF006C4C,
        label: 'Next task',
        directed: true,
      );
      await store.dispose();
      await database.close();
      database = AppDatabase.forTesting(NativeDatabase(file));
      store = WorkspaceStateStore(database);
      var state = await store.currentState();
      expect(state.activeWorkspaceId, workspace);
      expect(state.placementFor(workspace, 'source')!.pinned, isTrue);
      expect(state.links.single.id, link);
      expect(
        (await database.getNoteById('source'))!.content,
        '- [ ] Survive restart',
      );
      expect(
        await LocalNotesRepository(database).getPendingOperations(),
        hasLength(2),
      );
      await store.deleteLink(link);
      await store.dispose();
      await database.close();
      database = AppDatabase.forTesting(NativeDatabase(file));
      store = WorkspaceStateStore(database);
      state = await store.currentState();
      expect(state.links, isEmpty);
      expect((await database.getNoteById('target'))!.isDeleted, isFalse);
    },
  );
}
