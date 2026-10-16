import 'package:fasty/database/app_database.dart';
import 'package:fasty/notes/workspace_note_organization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LocalNote note({
    required String id,
    required String title,
    required String content,
    required DateTime updatedAt,
  }) {
    return LocalNote(
      id: id,
      title: title,
      content: content,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: updatedAt,
      syncStatus: 'synced',
      isDeleted: false,
    );
  }

  final notes = [
    note(
      id: 'alpha',
      title: 'Alpha',
      content: '- [x] Done',
      updatedAt: DateTime.utc(2026, 9, 2),
    ),
    note(
      id: 'charlie',
      title: 'Charlie',
      content: 'Ordinary note',
      updatedAt: DateTime.utc(2026, 9, 1),
    ),
    note(
      id: 'bravo',
      title: 'Bravo',
      content: '- [x] First\n- [ ] Second',
      updatedAt: DateTime.utc(2026, 9, 3),
    ),
  ];

  test('sorts notes by most recently updated', () {
    final result = organizeWorkspaceNotes(
      notes,
      sort: WorkspaceNoteSort.recentlyUpdated,
      filter: WorkspaceNoteFilter.all,
    );

    expect(result.map((note) => note.id), ['bravo', 'alpha', 'charlie']);
  });

  test('sorts notes by oldest update', () {
    final result = organizeWorkspaceNotes(
      notes,
      sort: WorkspaceNoteSort.oldestUpdated,
      filter: WorkspaceNoteFilter.all,
    );

    expect(result.map((note) => note.id), ['charlie', 'alpha', 'bravo']);
  });

  test('sorts notes by title ascending', () {
    final result = organizeWorkspaceNotes(
      notes,
      sort: WorkspaceNoteSort.titleAscending,
      filter: WorkspaceNoteFilter.all,
    );

    expect(result.map((note) => note.title), ['Alpha', 'Bravo', 'Charlie']);
  });

  test('sorts notes by title descending', () {
    final result = organizeWorkspaceNotes(
      notes,
      sort: WorkspaceNoteSort.titleDescending,
      filter: WorkspaceNoteFilter.all,
    );

    expect(result.map((note) => note.title), ['Charlie', 'Bravo', 'Alpha']);
  });

  test('filters to notes containing Markdown tasks', () {
    final result = organizeWorkspaceNotes(
      notes,
      sort: WorkspaceNoteSort.recentlyUpdated,
      filter: WorkspaceNoteFilter.taskNotes,
    );

    expect(result.map((note) => note.id).toSet(), {'alpha', 'bravo'});
  });

  test('filters to notes with incomplete tasks', () {
    final result = organizeWorkspaceNotes(
      notes,
      sort: WorkspaceNoteSort.recentlyUpdated,
      filter: WorkspaceNoteFilter.incompleteTasks,
    );

    expect(result.map((note) => note.id), ['bravo']);
  });

  test('filters to notes whose tasks are all complete', () {
    final result = organizeWorkspaceNotes(
      notes,
      sort: WorkspaceNoteSort.recentlyUpdated,
      filter: WorkspaceNoteFilter.completedTasks,
    );

    expect(result.map((note) => note.id), ['alpha']);
  });

  test('does not mutate the original note order', () {
    final before = notes.map((note) => note.id).toList();

    organizeWorkspaceNotes(
      notes,
      sort: WorkspaceNoteSort.titleDescending,
      filter: WorkspaceNoteFilter.all,
    );

    expect(notes.map((note) => note.id), before);
  });
}
