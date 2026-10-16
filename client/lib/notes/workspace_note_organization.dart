import '../database/app_database.dart';
import 'task_progression.dart';

enum WorkspaceNoteSort {
  recentlyUpdated,
  oldestUpdated,
  titleAscending,
  titleDescending,
}

enum WorkspaceNoteFilter { all, taskNotes, incompleteTasks, completedTasks }

List<LocalNote> organizeWorkspaceNotes(
  Iterable<LocalNote> notes, {
  required WorkspaceNoteSort sort,
  required WorkspaceNoteFilter filter,
  Set<String> pinnedNoteIds = const <String>{},
}) {
  final organized = notes
      .where((note) {
        final progress = markdownTaskProgress(note.content);

        return switch (filter) {
          WorkspaceNoteFilter.all => true,
          WorkspaceNoteFilter.taskNotes => progress.hasTasks,
          WorkspaceNoteFilter.incompleteTasks =>
            progress.hasTasks && !progress.isComplete,
          WorkspaceNoteFilter.completedTasks => progress.isComplete,
        };
      })
      .toList(growable: true);

  organized.sort((a, b) {
    final aPinned = pinnedNoteIds.contains(a.id);
    final bPinned = pinnedNoteIds.contains(b.id);

    if (aPinned != bPinned) {
      return aPinned ? -1 : 1;
    }

    final comparison = switch (sort) {
      WorkspaceNoteSort.recentlyUpdated => b.updatedAt.compareTo(a.updatedAt),
      WorkspaceNoteSort.oldestUpdated => a.updatedAt.compareTo(b.updatedAt),
      WorkspaceNoteSort.titleAscending => a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      ),
      WorkspaceNoteSort.titleDescending => b.title.toLowerCase().compareTo(
        a.title.toLowerCase(),
      ),
    };

    if (comparison != 0) {
      return comparison;
    }

    return a.id.compareTo(b.id);
  });

  return organized;
}
