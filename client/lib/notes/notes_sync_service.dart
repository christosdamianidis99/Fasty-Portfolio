import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'notes_api.dart';
import 'sync_status.dart';
import 'workspace_state.dart';
import 'workspace_state_merge.dart';
import 'workspace_state_store.dart';

class NotesSyncService {
  NotesSyncService({
    required this.database,
    required this.api,
    this.workspaceStateStore,
  });

  static const _trashRetention = Duration(days: 14);

  final AppDatabase database;
  final NotesApi api;
  final WorkspaceStateStore? workspaceStateStore;
  final ValueNotifier<SyncStatusSnapshot> status = ValueNotifier(
    const SyncStatusSnapshot.idle(),
  );

  Future<SyncSummary>? _activeSync;

  bool get isSyncing => _activeSync != null;

  Future<void> dispose() async {
    final activeSync = _activeSync;

    if (activeSync != null) {
      try {
        await activeSync;
      } on Object {
        // Disposal only needs the active operation to finish.
      }
    }

    status.dispose();
  }

  Future<SyncSummary> syncPendingOperations({bool forceRetry = true}) {
    final activeSync = _activeSync;
    if (activeSync != null) {
      return activeSync;
    }

    final sync = _performSync(forceRetry: forceRetry);
    _activeSync = sync;
    return sync.whenComplete(() {
      if (identical(_activeSync, sync)) {
        _activeSync = null;
      }
    });
  }

  Future<SyncSummary> _performSync({required bool forceRetry}) async {
    status.value = SyncStatusSnapshot(
      state: SyncState.syncing,
      message: 'Synchronizing local and server changes.',
      occurredAt: DateTime.now().toUtc(),
    );

    final failures = <String>[];
    var successfulOperations = 0;
    var connectionFailureDetected = false;

    try {
      final operations = await database.getPendingOperations(
        now: forceRetry ? DateTime.utc(9999, 12, 31) : null,
      );

      for (final operation in operations) {
        try {
          await _processOperation(operation);
          successfulOperations++;
        } catch (error) {
          connectionFailureDetected =
              connectionFailureDetected || error is NotesConnectionException;
          await database.markOperationFailed(
            operationId: operation.id,
            retryCount: operation.retryCount + 1,
            error: error.toString(),
          );
          failures.add('${operation.operation} ${operation.noteId}: $error');
        }
      }

      try {
        await _downloadServerNotes();
      } catch (error) {
        connectionFailureDetected =
            connectionFailureDetected || error is NotesConnectionException;
        failures.add('download: $error');
      }

      try {
        await _syncWorkspaceState();
      } catch (error) {
        connectionFailureDetected =
            connectionFailureDetected || error is NotesConnectionException;
        failures.add('workspace: $error');
      }

      final remainingOperations = await database.getPendingOperations(
        now: DateTime.utc(9999, 12, 31),
      );
      final workspacePending =
          (await workspaceStateStore?.localSnapshot())?.isPending ?? false;
      final pendingCount =
          remainingOperations.length + (workspacePending ? 1 : 0);

      if (failures.isNotEmpty) {
        final exception = NotesSyncException(
          successfulOperations: successfulOperations,
          failureMessages: failures,
        );
        status.value = SyncStatusSnapshot(
          state: connectionFailureDetected
              ? SyncState.unavailable
              : SyncState.failed,
          message: connectionFailureDetected
              ? 'The sync server is currently unreachable. Local changes are safe and will be retried.'
              : exception.toString(),
          occurredAt: DateTime.now().toUtc(),
          successfulOperations: successfulOperations,
          pendingOperations: pendingCount,
          failureMessages: List.unmodifiable(failures),
        );
        throw exception;
      }

      final message = pendingCount > 0
          ? 'Synchronization completed, but $pendingCount change${pendingCount == 1 ? '' : 's'} are still pending.'
          : successfulOperations == 0
          ? 'Sync check completed. Everything is up to date.'
          : '$successfulOperations queued change${successfulOperations == 1 ? '' : 's'} synchronized successfully.';
      status.value = SyncStatusSnapshot(
        state: pendingCount > 0 ? SyncState.failed : SyncState.synchronized,
        message: message,
        occurredAt: DateTime.now().toUtc(),
        successfulOperations: successfulOperations,
        pendingOperations: pendingCount,
      );

      return SyncSummary(
        successfulOperations: successfulOperations,
        remainingOperations: pendingCount,
      );
    } on NotesSyncException {
      rethrow;
    } catch (error) {
      final unavailable = error is NotesConnectionException;
      status.value = SyncStatusSnapshot(
        state: unavailable ? SyncState.unavailable : SyncState.failed,
        message: unavailable
            ? 'The sync server is currently unreachable. Local changes are safe and will be retried.'
            : 'Synchronization failed: $error',
        occurredAt: DateTime.now().toUtc(),
        pendingOperations: (await database.getPendingOperations(
          now: DateTime.utc(9999, 12, 31),
        )).length,
        failureMessages: [error.toString()],
      );
      rethrow;
    }
  }

  Future<void> _processOperation(OutboxOperation operation) async {
    switch (operation.operation) {
      case 'create':
      case 'update':
        await _syncUpsert(operation);
        break;
      case 'delete':
      case 'purge':
        await _syncDelete(operation);
        break;
      default:
        throw StateError('Unknown outbox operation: ${operation.operation}');
    }
  }

  Future<void> _downloadServerNotes() async {
    final serverNotes = await api.listNotes();
    final trashCutoff = DateTime.now().toUtc().subtract(_trashRetention);

    await database.transaction(() async {
      for (final note in serverNotes) {
        if (note.isDeleted && !note.updatedAt.isAfter(trashCutoff)) {
          continue;
        }

        final existing = await database.getNoteById(note.id);
        if (note.isDeleted && existing == null) {
          await database.saveLocalNote(
            LocalNotesCompanion(
              id: Value(note.id),
              title: Value(note.title),
              content: Value(note.content),
              createdAt: Value(note.createdAt),
              updatedAt: Value(note.updatedAt),
              syncStatus: const Value('synced'),
              isDeleted: const Value(true),
            ),
          );
          continue;
        }

        await database.mergeServerNote(
          id: note.id,
          title: note.title,
          content: note.content,
          createdAt: note.createdAt,
          updatedAt: note.updatedAt,
          isDeleted: note.isDeleted,
        );
      }
    });
  }

  Future<void> _syncWorkspaceState() async {
    final store = workspaceStateStore;
    if (store == null) {
      return;
    }

    final local = await store.localSnapshot();
    final remote = await api.getWorkspaceState();

    if (local.isUnknown) {
      if (remote == null) {
        final winner = await api.upsertWorkspaceState(local.state);
        await _acceptWorkspaceWinner(store, local, winner);
      } else {
        await _acceptWorkspaceWinner(store, local, remote);
      }
      return;
    }

    if (local.isPending) {
      if (remote == null) {
        final winner = await api.upsertWorkspaceState(local.state);
        await _acceptWorkspaceWinner(store, local, winner);
      } else {
        final merged = mergeWorkspaceStateDocuments(
          local: local.state,
          remote: remote,
          base: local.baseState,
        );
        final winner = await api.upsertWorkspaceState(merged);
        await _acceptWorkspaceWinner(store, local, winner);
      }
      return;
    }

    if (remote == null) {
      final winner = await api.upsertWorkspaceState(local.state);
      await _acceptWorkspaceWinner(store, local, winner);
    } else if (remote.updatedAt.isAfter(local.state.updatedAt)) {
      await _acceptWorkspaceWinner(store, local, remote);
    } else if (local.state.updatedAt.isAfter(remote.updatedAt)) {
      final winner = await api.upsertWorkspaceState(local.state);
      await _acceptWorkspaceWinner(store, local, winner);
    } else {
      await store.markSynced();
    }
  }

  Future<bool> _acceptWorkspaceWinner(
    WorkspaceStateStore store,
    WorkspaceLocalSnapshot expectedLocal,
    WorkspaceStateDocument winner,
  ) async {
    final latest = await store.localSnapshot();
    final localChangedDuringRequest =
        !latest.state.updatedAt.isAtSameMomentAs(
          expectedLocal.state.updatedAt,
        ) ||
        latest.syncStatus != expectedLocal.syncStatus;
    if (localChangedDuringRequest) {
      return false;
    }

    await store.replaceFromServer(winner);
    return true;
  }

  Future<void> _syncUpsert(OutboxOperation operation) async {
    final note = await database.getNoteById(operation.noteId);

    if (note == null || note.isDeleted) {
      await database.deleteOutboxOperation(operation.id);
      return;
    }

    final winner = await api.upsertNote(
      id: note.id,
      title: note.title,
      content: note.content,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
    );

    await database.transaction(() async {
      await database.deleteOutboxOperation(operation.id);
      await database.markNoteSyncedIfNoPendingOperations(note.id);
      await database.mergeServerNote(
        id: winner.id,
        title: winner.title,
        content: winner.content,
        createdAt: winner.createdAt,
        updatedAt: winner.updatedAt,
        isDeleted: winner.isDeleted,
      );
    });
  }

  Future<void> _syncDelete(OutboxOperation operation) async {
    await api.deleteNote(id: operation.noteId, updatedAt: operation.createdAt);

    await database.transaction(() async {
      await database.deleteOutboxOperation(operation.id);
      await database.markNoteSyncedIfNoPendingOperations(operation.noteId);
    });
  }
}

class SyncSummary {
  const SyncSummary({
    this.successfulOperations = 0,
    this.remainingOperations = 0,
    this.skippedBecauseAlreadyRunning = false,
  });

  final int successfulOperations;
  final int remainingOperations;
  final bool skippedBecauseAlreadyRunning;
}

class NotesSyncException implements Exception {
  const NotesSyncException({
    required this.successfulOperations,
    required this.failureMessages,
  });

  final int successfulOperations;
  final List<String> failureMessages;

  @override
  String toString() {
    final summary = successfulOperations == 0
        ? 'No changes were synchronized.'
        : '$successfulOperations changes synchronized; some still need retry.';
    return '$summary ${failureMessages.first}';
  }
}
