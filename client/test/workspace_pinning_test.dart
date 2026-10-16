import 'package:drift/native.dart';
import 'package:fasty/database/app_database.dart';
import 'package:fasty/notes/workspace_note_organization.dart';
import 'package:fasty/notes/workspace_state.dart';
import 'package:fasty/notes/workspace_state_merge.dart';
import 'package:fasty/notes/workspace_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LocalNote note(String id, String title) {
    final now = DateTime.utc(2026, 9, 10);

    return LocalNote(
      id: id,
      title: title,
      content: '',
      createdAt: now,
      updatedAt: now,
      syncStatus: 'synced',
      isDeleted: false,
    );
  }

  test('legacy placement JSON defaults pinned to false', () {
    final placement = WorkspacePlacement.fromJson({
      'workspaceId': 'workspace',
      'noteId': 'note',
      'x': 10,
      'y': 20,
      'width': 270,
      'height': 230,
      'zIndex': 0,
    });

    expect(placement.pinned, isFalse);
    expect(placement.toJson()['pinned'], isFalse);
  });

  test('store pins and unpins a note within one workspace', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final store = WorkspaceStateStore(database);

    addTearDown(() async {
      await store.dispose();
      await database.close();
    });

    await store.ensureNotes(const ['note']);
    final workspaceId = (await store.currentState()).activeWorkspaceId;

    await store.setNotePinned(
      workspaceId: workspaceId,
      noteId: 'note',
      pinned: true,
    );

    var state = await store.currentState();
    expect(state.placementFor(workspaceId, 'note')!.pinned, isTrue);
    expect((await store.localSnapshot()).isPending, isTrue);

    await store.setNotePinned(
      workspaceId: workspaceId,
      noteId: 'note',
      pinned: false,
    );

    state = await store.currentState();
    expect(state.placementFor(workspaceId, 'note')!.pinned, isFalse);
  });

  test('pinning is workspace specific', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final store = WorkspaceStateStore(database);

    addTearDown(() async {
      await store.dispose();
      await database.close();
    });

    await store.ensureNotes(const ['note']);
    final initial = await store.currentState();
    final firstWorkspaceId = initial.activeWorkspaceId;
    final secondWorkspaceId = await store.createWorkspace(name: 'Second');

    await store.addNoteToWorkspace(
      workspaceId: secondWorkspaceId,
      noteId: 'note',
    );

    await store.setNotePinned(
      workspaceId: firstWorkspaceId,
      noteId: 'note',
      pinned: true,
    );

    final state = await store.currentState();

    expect(state.placementFor(firstWorkspaceId, 'note')!.pinned, isTrue);
    expect(state.placementFor(secondWorkspaceId, 'note')!.pinned, isFalse);
  });

  test('merge keeps a pin changed on one device', () {
    final now = DateTime.utc(2026, 9, 10, 10);
    const workspaceId = WorkspaceStateDocument.defaultWorkspaceId;

    final workspace = WorkspaceDefinition(
      id: workspaceId,
      name: 'My workspace',
      colorValue: 0xFF625BEB,
      cameraX: 0,
      cameraY: 0,
      scale: 1,
      createdAt: now,
      updatedAt: now,
    );

    const basePlacement = WorkspacePlacement(
      workspaceId: workspaceId,
      noteId: 'note',
      x: 100,
      y: 100,
      width: 270,
      height: 230,
      zIndex: 0,
    );

    WorkspaceStateDocument document({
      required WorkspacePlacement placement,
      required DateTime updatedAt,
    }) {
      return WorkspaceStateDocument(
        schemaVersion: WorkspaceStateDocument.currentSchemaVersion,
        activeWorkspaceId: workspaceId,
        workspaces: [workspace],
        placements: [placement],
        links: const [],
        updatedAt: updatedAt,
      );
    }

    final base = document(placement: basePlacement, updatedAt: now);
    final local = document(
      placement: basePlacement.copyWith(pinned: true),
      updatedAt: now.add(const Duration(seconds: 2)),
    );
    final remote = document(
      placement: basePlacement,
      updatedAt: now.add(const Duration(seconds: 1)),
    );

    final merged = mergeWorkspaceStateDocuments(
      local: local,
      remote: remote,
      base: base,
    );

    expect(merged.placementFor(workspaceId, 'note')!.pinned, isTrue);
  });

  test('pinned notes sort before unpinned notes', () {
    final organized = organizeWorkspaceNotes(
      [note('a', 'Alpha'), note('b', 'Beta'), note('c', 'Charlie')],
      sort: WorkspaceNoteSort.titleAscending,
      filter: WorkspaceNoteFilter.all,
      pinnedNoteIds: const {'c'},
    );

    expect(organized.map((item) => item.id).toList(), ['c', 'a', 'b']);
  });
}
