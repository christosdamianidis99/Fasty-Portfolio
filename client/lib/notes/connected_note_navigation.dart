import 'workspace_state.dart';

enum ConnectedNoteDirection { outgoing, incoming, undirected }

class ConnectedNoteTarget {
  const ConnectedNoteTarget({
    required this.link,
    required this.noteId,
    required this.direction,
  });

  final NoteLinkDefinition link;
  final String noteId;
  final ConnectedNoteDirection direction;
}

List<ConnectedNoteTarget> connectedNoteTargets({
  required String noteId,
  required Iterable<NoteLinkDefinition> links,
}) {
  final targets = <ConnectedNoteTarget>[];

  for (final link in links) {
    final isSource = link.sourceNoteId == noteId;
    final isTarget = link.targetNoteId == noteId;

    if (!isSource && !isTarget) {
      continue;
    }

    if (!link.directed) {
      targets.add(
        ConnectedNoteTarget(
          link: link,
          noteId: isSource ? link.targetNoteId : link.sourceNoteId,
          direction: ConnectedNoteDirection.undirected,
        ),
      );
      continue;
    }

    targets.add(
      ConnectedNoteTarget(
        link: link,
        noteId: isSource ? link.targetNoteId : link.sourceNoteId,
        direction: isSource
            ? ConnectedNoteDirection.outgoing
            : ConnectedNoteDirection.incoming,
      ),
    );
  }

  return targets;
}
