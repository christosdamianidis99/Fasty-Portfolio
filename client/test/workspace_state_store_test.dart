import 'package:drift/native.dart';
import 'package:fasty/database/app_database.dart';
import 'package:fasty/notes/workspace_state.dart';
import 'package:fasty/notes/workspace_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late WorkspaceStateStore store;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    store = WorkspaceStateStore(database);
  });

  tearDown(() async {
    await store.dispose();
    await database.close();
  });

  test('creates a default workspace and persists note placement', () async {
    await store.ensureNotes(const ['note-1']);

    final state = await store.currentState();
    expect(state.workspaces, hasLength(1));
    expect(state.activeWorkspace.name, 'My workspace');

    final placement = state.placementFor(state.activeWorkspaceId, 'note-1');
    expect(placement, isNotNull);
    expect(placement!.x, 100);
    expect(placement.y, 100);

    await store.updatePlacement(
      placement.copyWith(x: 430, y: 280, width: 360, height: 300),
    );

    final updated = await store.currentState();
    final updatedPlacement = updated.placementFor(
      updated.activeWorkspaceId,
      'note-1',
    );
    expect(updatedPlacement!.x, 430);
    expect(updatedPlacement.y, 280);
    expect(updatedPlacement.width, 360);
    expect(updatedPlacement.height, 300);
    expect((await store.localSnapshot()).isPending, isTrue);
  });

  test(
    'shares a note across workspaces without duplicating its identity',
    () async {
      await store.ensureNotes(const ['shared-note']);
      final original = await store.currentState();
      final secondWorkspaceId = await store.createWorkspace(name: 'University');

      await store.addNoteToWorkspace(
        workspaceId: secondWorkspaceId,
        noteId: 'shared-note',
        placement: original.placementFor(
          original.activeWorkspaceId,
          'shared-note',
        ),
      );

      final state = await store.currentState();
      final placements = state.placements
          .where((placement) => placement.noteId == 'shared-note')
          .toList();
      expect(placements, hasLength(2));
      expect(placements.map((placement) => placement.workspaceId).toSet(), {
        WorkspaceStateDocument.defaultWorkspaceId,
        secondWorkspaceId,
      });
    },
  );

  test('workspace selection and camera remain device-local', () async {
    final secondWorkspaceId = await store.createWorkspace(
      name: 'Second workspace',
    );
    await store.markSynced();
    final before = await store.localSnapshot();

    await store.selectWorkspace(WorkspaceStateDocument.defaultWorkspaceId);
    await store.setWorkspaceCamera(
      workspaceId: WorkspaceStateDocument.defaultWorkspaceId,
      translationX: 120,
      translationY: -80,
      scale: 1.4,
    );

    final after = await store.localSnapshot();
    expect(secondWorkspaceId, isNotEmpty);
    expect(after.isPending, isFalse);
    expect(after.state.updatedAt, before.state.updatedAt);
    expect(
      after.state.activeWorkspaceId,
      WorkspaceStateDocument.defaultWorkspaceId,
    );
    expect(after.state.activeWorkspace.cameraX, 120);
    expect(after.state.activeWorkspace.cameraY, -80);
    expect(after.state.activeWorkspace.scale, 1.4);
  });

  test('creates and removes a colored directed connection', () async {
    await store.ensureNotes(const ['source', 'target']);
    final state = await store.currentState();

    final linkId = await store.createLink(
      workspaceId: state.activeWorkspaceId,
      sourceNoteId: 'source',
      targetNoteId: 'target',
      colorValue: 0xFF006C4C,
      label: 'depends on',
      directed: true,
    );

    final linked = await store.currentState();
    expect(linked.links, hasLength(1));
    expect(linked.links.single.id, linkId);
    expect(linked.links.single.colorValue, 0xFF006C4C);
    expect(linked.links.single.label, 'depends on');
    expect(linked.links.single.directed, isTrue);

    await store.deleteLink(linkId);
    expect((await store.currentState()).links, isEmpty);
  });
}
