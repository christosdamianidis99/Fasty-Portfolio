import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'workspace_state.dart';

class LocalNotesRepository {
  LocalNotesRepository(this.database);

  static const trashRetention = Duration(days: 14);
  static const permanentlyDeletedTitle = '__FASTY_PURGED__';

  final AppDatabase database;

  Stream<List<LocalNote>> watchNotes() {
    return database.watchActiveNotes();
  }

  Stream<List<LocalNote>> watchDeletedNotes() {
    return database.watchDeletedNotes().map(
      (notes) => notes
          .where((note) => note.title != permanentlyDeletedTitle)
          .toList(growable: false),
    );
  }

  Future<void> createNote({
    required String id,
    required String title,
    required String content,
    required DateTime now,
  }) {
    return database.transaction(() async {
      await database.saveLocalNote(
        LocalNotesCompanion(
          id: Value(id),
          title: Value(title),
          content: Value(content),
          createdAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
          isDeleted: const Value(false),
        ),
      );

      await database.addOutboxOperation(
        noteId: id,
        operation: 'create',
        createdAt: now,
      );
    });
  }

  Future<void> updateNote({
    required String id,
    required String title,
    required String content,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return database.transaction(() async {
      await database.saveLocalNote(
        LocalNotesCompanion(
          id: Value(id),
          title: Value(title),
          content: Value(content),
          createdAt: Value(createdAt),
          updatedAt: Value(updatedAt),
          syncStatus: const Value('pending'),
          isDeleted: const Value(false),
        ),
      );

      final operations = await database.getOperationsForNote(id);
      final alreadyHasCreate = operations.any(
        (operation) => operation.operation == 'create',
      );

      if (alreadyHasCreate) {
        await database.deleteOperationsForNoteByType(
          noteId: id,
          operationType: 'update',
        );
        return;
      }

      await database.deleteOperationsForNoteByType(
        noteId: id,
        operationType: 'update',
      );

      await database.addOutboxOperation(
        noteId: id,
        operation: 'update',
        createdAt: updatedAt,
      );
    });
  }

  Future<void> deleteNote({required String id, required DateTime updatedAt}) {
    return database.transaction(() async {
      final operations = await database.getOperationsForNote(id);
      final hasPendingCreate = operations.any(
        (operation) => operation.operation == 'create',
      );

      await database.deleteOperationsForNote(id);

      if (hasPendingCreate) {
        await database.markNoteDeleted(
          id: id,
          updatedAt: updatedAt,
          syncStatus: 'localOnly',
        );
        return;
      }

      await database.markNoteDeleted(id: id, updatedAt: updatedAt);
      await database.addOutboxOperation(
        noteId: id,
        operation: 'delete',
        createdAt: updatedAt,
      );
    });
  }

  Future<void> restoreNote({
    required LocalNote note,
    required DateTime updatedAt,
  }) {
    return database.transaction(() async {
      final storedNote = await database.getNoteById(note.id) ?? note;
      final restoreOperation = storedNote.syncStatus == 'localOnly'
          ? 'create'
          : 'update';

      await database.deleteOperationsForNote(note.id);
      await database.restoreDeletedNote(id: note.id, updatedAt: updatedAt);
      await database.addOutboxOperation(
        noteId: note.id,
        operation: restoreOperation,
        createdAt: updatedAt,
      );
    });
  }

  Future<void> permanentlyDeleteNote(String id) {
    return database.transaction(() async {
      final note = await database.getNoteById(id);
      if (note == null) {
        return;
      }

      final operations = await database.getOperationsForNote(id);
      final hasPendingDelete = operations.any(
        (operation) => operation.operation == 'delete',
      );
      final hasPendingPurge = operations.any(
        (operation) => operation.operation == 'purge',
      );

      if (note.syncStatus == 'localOnly') {
        await database.deleteOperationsForNote(id);
      } else {
        if (!hasPendingDelete && note.syncStatus == 'pending') {
          await database.addOutboxOperation(
            noteId: id,
            operation: 'delete',
            createdAt: note.updatedAt,
          );
        }
        if (!hasPendingPurge) {
          final latestQueuedAt = operations.isEmpty
              ? note.updatedAt
              : operations
                    .map((operation) => operation.createdAt)
                    .reduce(
                      (latest, value) => value.isAfter(latest) ? value : latest,
                    );
          final now = DateTime.now().toUtc();
          final purgeAt = now.isAfter(latestQueuedAt)
              ? now
              : latestQueuedAt.add(const Duration(microseconds: 1));
          await database.addOutboxOperation(
            noteId: id,
            operation: 'purge',
            createdAt: purgeAt,
          );
        }
      }

      await database.permanentlyDeleteNote(id);
    });
  }

  Future<int> purgeExpiredTrash({DateTime? now}) {
    final currentTime = (now ?? DateTime.now()).toUtc();
    final cutoff = currentTime.subtract(trashRetention);
    return database.purgeDeletedNotesBefore(cutoff);
  }

  int trashDaysRemaining(LocalNote note, {DateTime? now}) {
    final currentTime = (now ?? DateTime.now()).toUtc();
    final expiresAt = note.updatedAt.toUtc().add(trashRetention);
    final remaining = expiresAt.difference(currentTime);

    if (remaining.isNegative || remaining == Duration.zero) {
      return 0;
    }

    return (remaining.inHours / 24).ceil();
  }

  Future<List<OutboxOperation>> getPendingOperations() {
    return database.getPendingOperations();
  }

  Future<List<PendingOperationDetails>> getPendingOperationDetails(
    WorkspaceStateDocument workspaceState,
  ) async {
    final operations = await database.getPendingOperations(
      now: DateTime.utc(9999, 12, 31),
    );
    final details = <PendingOperationDetails>[];

    for (final operation in operations) {
      final note = await database.getNoteById(operation.noteId);
      final workspaceNames = workspaceState.workspaces
          .where(
            (workspace) => workspaceState.containsNoteInWorkspace(
              workspace.id,
              operation.noteId,
            ),
          )
          .map((workspace) => workspace.name)
          .toList(growable: false);

      details.add(
        PendingOperationDetails(
          operation: operation,
          note: note,
          workspaceNames: workspaceNames,
        ),
      );
    }

    return details;
  }
}

class PendingOperationDetails {
  const PendingOperationDetails({
    required this.operation,
    required this.note,
    required this.workspaceNames,
  });

  final OutboxOperation operation;
  final LocalNote? note;
  final List<String> workspaceNames;

  String get title => note?.title.trim().isNotEmpty == true
      ? note!.title.trim()
      : operation.noteId;

  String get contentPreview {
    final content = note?.content.trim() ?? '';
    if (content.isEmpty) {
      return '';
    }
    return content.length <= 140 ? content : '${content.substring(0, 140)}…';
  }
}
