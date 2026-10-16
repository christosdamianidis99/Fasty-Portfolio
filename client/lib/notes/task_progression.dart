import 'workspace_state.dart';

const taskProgressionLinkLabel = 'Next task';

class MarkdownTaskProgress {
  const MarkdownTaskProgress({required this.total, required this.completed});

  final int total;
  final int completed;

  int get remaining => total - completed;

  bool get hasTasks => total > 0;

  bool get isComplete => hasTasks && remaining == 0;
}

MarkdownTaskProgress markdownTaskProgress(String markdown) {
  final taskPattern = RegExp(r'^\s*(?:[-+*]|\d+[.)])\s+\[([ xX])\]');
  final fencePattern = RegExp(r'^\s*(`{3,}|~{3,})');

  String? activeFence;
  var total = 0;
  var completed = 0;

  for (final line in markdown.split('\n')) {
    final fenceMatch = fencePattern.firstMatch(line);

    if (fenceMatch != null) {
      final marker = fenceMatch.group(1)!;

      if (activeFence == null) {
        activeFence = marker;
      } else if (marker[0] == activeFence[0] &&
          marker.length >= activeFence.length) {
        activeFence = null;
      }

      continue;
    }

    if (activeFence != null) {
      continue;
    }

    final taskMatch = taskPattern.firstMatch(line);
    if (taskMatch == null) {
      continue;
    }

    total++;

    if (taskMatch.group(1)!.trim().isNotEmpty) {
      completed++;
    }
  }

  return MarkdownTaskProgress(total: total, completed: completed);
}

bool isTaskProgressionLink(NoteLinkDefinition link) {
  return link.directed &&
      link.label.trim().toLowerCase() == taskProgressionLinkLabel.toLowerCase();
}

bool isTaskProgressionReady(NoteLinkDefinition link, String sourceMarkdown) {
  return isTaskProgressionLink(link) &&
      markdownTaskProgress(sourceMarkdown).isComplete;
}

Set<String> readyTaskProgressionLinkIds({
  required Iterable<NoteLinkDefinition> links,
  required Map<String, String> noteContents,
}) {
  return {
    for (final link in links)
      if (isTaskProgressionReady(link, noteContents[link.sourceNoteId] ?? ''))
        link.id,
  };
}

Set<String> readyTaskProgressionTargetIds({
  required Iterable<NoteLinkDefinition> links,
  required Map<String, String> noteContents,
}) {
  return {
    for (final link in links)
      if (isTaskProgressionReady(link, noteContents[link.sourceNoteId] ?? ''))
        link.targetNoteId,
  };
}

bool didTaskProgressionBecomeReady({
  required String beforeMarkdown,
  required String afterMarkdown,
}) {
  final before = markdownTaskProgress(beforeMarkdown);
  final after = markdownTaskProgress(afterMarkdown);

  return !before.isComplete && after.isComplete;
}
