import 'package:fasty/notes/connected_note_navigation.dart';
import 'package:fasty/notes/workspace_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NoteLinkDefinition link({
    required String id,
    required String source,
    required String target,
    bool directed = true,
  }) {
    final now = DateTime.utc(2026, 9, 9);

    return NoteLinkDefinition(
      id: id,
      workspaceId: 'workspace',
      sourceNoteId: source,
      targetNoteId: target,
      colorValue: 0xFF625BEB,
      label: '',
      directed: directed,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('returns outgoing directed connection target', () {
    final targets = connectedNoteTargets(
      noteId: 'a',
      links: [link(id: 'link', source: 'a', target: 'b')],
    );

    expect(targets, hasLength(1));
    expect(targets.single.noteId, 'b');
    expect(targets.single.direction, ConnectedNoteDirection.outgoing);
  });

  test('returns incoming directed connection source', () {
    final targets = connectedNoteTargets(
      noteId: 'b',
      links: [link(id: 'link', source: 'a', target: 'b')],
    );

    expect(targets, hasLength(1));
    expect(targets.single.noteId, 'a');
    expect(targets.single.direction, ConnectedNoteDirection.incoming);
  });

  test('returns undirected neighbour and ignores unrelated links', () {
    final targets = connectedNoteTargets(
      noteId: 'a',
      links: [
        link(id: 'connected', source: 'a', target: 'b', directed: false),
        link(id: 'unrelated', source: 'c', target: 'd'),
      ],
    );

    expect(targets, hasLength(1));
    expect(targets.single.noteId, 'b');
    expect(targets.single.direction, ConnectedNoteDirection.undirected);
  });
}
