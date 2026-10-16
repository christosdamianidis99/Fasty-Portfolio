import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'workspace_state.dart';

class WorkspaceStateStore {
  WorkspaceStateStore(this.database);

  static const _uuid = Uuid();
  static const _tableName = 'workspace_state_cache';
  static const _baseTableName = 'workspace_state_sync_base';

  final AppDatabase database;
  final StreamController<WorkspaceStateDocument> _changes =
      StreamController<WorkspaceStateDocument>.broadcast();

  Future<void>? _initialization;
  Future<void> _writeQueue = Future<void>.value();
  WorkspaceStateDocument? _state;
  WorkspaceStateDocument? _baseState;
  String _syncStatus = 'unknown';

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
        state_json TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS $_baseTableName (
        id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
        state_json TEXT NOT NULL
      )
    ''');

    final row = await database
        .customSelect(
          'SELECT state_json, sync_status FROM $_tableName WHERE id = 1',
        )
        .getSingleOrNull();

    if (row == null) {
      final initial = WorkspaceStateDocument.initial();
      _state = initial;
      _syncStatus = 'unknown';
      await _persist(initial, syncStatus: _syncStatus);
      await _loadBaseState(seedFromCurrent: false);
      return;
    }

    try {
      final decoded = jsonDecode(row.read<String>('state_json'));
      _state = WorkspaceStateDocument.fromJson(
        Map<String, dynamic>.from(decoded as Map),
      );
      _syncStatus = row.read<String>('sync_status');
    } catch (_) {
      final recovered = WorkspaceStateDocument.initial();
      _state = recovered;
      _syncStatus = 'unknown';
      await _persist(recovered, syncStatus: _syncStatus);
    }
    await _loadBaseState(seedFromCurrent: _syncStatus == 'synced');
  }

  Future<void> _loadBaseState({required bool seedFromCurrent}) async {
    final row = await database
        .customSelect('SELECT state_json FROM $_baseTableName WHERE id = 1')
        .getSingleOrNull();
    if (row != null) {
      try {
        final decoded = jsonDecode(row.read<String>('state_json'));
        _baseState = WorkspaceStateDocument.fromJson(
          Map<String, dynamic>.from(decoded as Map),
        );
        return;
      } catch (_) {
        _baseState = null;
      }
    }
    if (seedFromCurrent) {
      _baseState = _state;
      await _persistBase(_state!);
    }
  }

  Stream<WorkspaceStateDocument> watchState() async* {
    await ensureInitialized();
    yield _state!;
    yield* _changes.stream;
  }

  Future<WorkspaceStateDocument> currentState() async {
    await ensureInitialized();
    await _writeQueue;
    return _state!;
  }

  Future<WorkspaceLocalSnapshot> localSnapshot() async {
    await ensureInitialized();
    await _writeQueue;
    return WorkspaceLocalSnapshot(
      state: _state!,
      syncStatus: _syncStatus,
      baseState: _baseState,
    );
  }

  Future<void> ensureNotes(Iterable<String> noteIds) {
    return _serialize(() async {
      await ensureInitialized();
      final current = _state!;
      final missing = noteIds
          .where((noteId) => !current.containsNoteAnywhere(noteId))
          .toList(growable: false);
      if (missing.isEmpty) {
        return;
      }

      final nextPlacements = [...current.placements];
      var index = current.placementsFor(current.activeWorkspaceId).length;
      for (final noteId in missing) {
        nextPlacements.add(
          _initialPlacement(
            workspaceId: current.activeWorkspaceId,
            noteId: noteId,
            index: index++,
          ),
        );
      }

      await _savePending(current.copyWith(placements: nextPlacements));
    });
  }

  Future<String> createWorkspace({required String name, int? colorValue}) {
    final completer = Completer<String>();
    _serialize(() async {
      await ensureInitialized();
      final current = _state!;
      final now = DateTime.now().toUtc();
      final id = _uuid.v4();
      final palette = <int>[
        0xFF625BEB,
        0xFF006C4C,
        0xFF9C4146,
        0xFF825500,
        0xFF00639A,
        0xFF7A4EAB,
      ];
      final workspace = WorkspaceDefinition(
        id: id,
        name: _cleanWorkspaceName(name),
        colorValue:
            colorValue ?? palette[current.workspaces.length % palette.length],
        cameraX: 0,
        cameraY: 0,
        scale: 1,
        createdAt: now,
        updatedAt: now,
      );
      await _savePending(
        current.copyWith(
          activeWorkspaceId: id,
          workspaces: [...current.workspaces, workspace],
        ),
      );
      completer.complete(id);
    }).catchError(completer.completeError);
    return completer.future;
  }

  Future<void> selectWorkspace(String workspaceId) {
    return _serialize(() async {
      await ensureInitialized();
      final current = _state!;
      if (workspaceId == current.activeWorkspaceId ||
          !current.workspaces.any((workspace) => workspace.id == workspaceId)) {
        return;
      }
      await _saveLocalView(current.copyWith(activeWorkspaceId: workspaceId));
    });
  }

  Future<void> renameWorkspace(String workspaceId, String name) {
    return _serialize(() async {
      await ensureInitialized();
      final current = _state!;
      final now = DateTime.now().toUtc();
      final cleanedName = _cleanWorkspaceName(name);
      final workspaces = current.workspaces
          .map(
            (workspace) => workspace.id == workspaceId
                ? workspace.copyWith(name: cleanedName, updatedAt: now)
                : workspace,
          )
          .toList(growable: false);
      await _savePending(current.copyWith(workspaces: workspaces));
    });
  }

  Future<bool> deleteWorkspace(String workspaceId) async {
    final completer = Completer<bool>();
    _serialize(() async {
      await ensureInitialized();
      final current = _state!;
      if (current.workspaces.length <= 1 ||
          !current.workspaces.any((workspace) => workspace.id == workspaceId)) {
        completer.complete(false);
        return;
      }

      final remainingWorkspaces = current.workspaces
          .where((workspace) => workspace.id != workspaceId)
          .toList(growable: false);
      final activeWorkspaceId = current.activeWorkspaceId == workspaceId
          ? remainingWorkspaces.first.id
          : current.activeWorkspaceId;
      await _savePending(
        current.copyWith(
          activeWorkspaceId: activeWorkspaceId,
          workspaces: remainingWorkspaces,
          placements: current.placements
              .where((placement) => placement.workspaceId != workspaceId)
              .toList(growable: false),
          links: current.links
              .where((link) => link.workspaceId != workspaceId)
              .toList(growable: false),
        ),
      );
      completer.complete(true);
    }).catchError(completer.completeError);
    return completer.future;
  }

  Future<void> setWorkspaceCamera({
    required String workspaceId,
    required double translationX,
    required double translationY,
    required double scale,
  }) {
    return _serialize(() async {
      await ensureInitialized();
      final current = _state!;
      final workspaces = current.workspaces
          .map(
            (workspace) => workspace.id == workspaceId
                ? workspace.copyWith(
                    cameraX: translationX,
                    cameraY: translationY,
                    scale: scale.clamp(0.45, 2.25).toDouble(),
                  )
                : workspace,
          )
          .toList(growable: false);
      await _saveLocalView(current.copyWith(workspaces: workspaces));
    });
  }

  Future<void> addNoteToWorkspace({
    required String workspaceId,
    required String noteId,
    WorkspacePlacement? placement,
  }) {
    return _serialize(() async {
      await ensureInitialized();
      final current = _state!;
      if (current.containsNoteInWorkspace(workspaceId, noteId)) {
        return;
      }
      final index = current.placementsFor(workspaceId).length;
      final nextPlacement = placement == null
          ? _initialPlacement(
              workspaceId: workspaceId,
              noteId: noteId,
              index: index,
            )
          : WorkspacePlacement(
              workspaceId: workspaceId,
              noteId: noteId,
              x: placement.x + 36,
              y: placement.y + 36,
              width: placement.width,
              height: placement.height,
              zIndex: index,
            );
      await _savePending(
        current.copyWith(placements: [...current.placements, nextPlacement]),
      );
    });
  }

  Future<bool> removeNoteFromWorkspace({
    required String workspaceId,
    required String noteId,
  }) async {
    final completer = Completer<bool>();
    _serialize(() async {
      await ensureInitialized();
      final current = _state!;
      final otherPlacements = current.placements.where(
        (placement) =>
            placement.noteId == noteId && placement.workspaceId != workspaceId,
      );
      if (otherPlacements.isEmpty) {
        completer.complete(false);
        return;
      }

      await _savePending(
        current.copyWith(
          placements: current.placements
              .where(
                (placement) =>
                    placement.workspaceId != workspaceId ||
                    placement.noteId != noteId,
              )
              .toList(growable: false),
          links: current.links
              .where(
                (link) =>
                    link.workspaceId != workspaceId ||
                    (link.sourceNoteId != noteId &&
                        link.targetNoteId != noteId),
              )
              .toList(growable: false),
        ),
      );
      completer.complete(true);
    }).catchError(completer.completeError);
    return completer.future;
  }

  Future<void> removeNoteEverywhere(String noteId) {
    return _serialize(() async {
      await ensureInitialized();
      final current = _state!;
      await _savePending(
        current.copyWith(
          placements: current.placements
              .where((placement) => placement.noteId != noteId)
              .toList(growable: false),
          links: current.links
              .where(
                (link) =>
                    link.sourceNoteId != noteId && link.targetNoteId != noteId,
              )
              .toList(growable: false),
        ),
      );
    });
  }

  Future<void> setNotePinned({
    required String workspaceId,
    required String noteId,
    required bool pinned,
  }) {
    return _serialize(() async {
      await ensureInitialized();
      final current = _state!;
      var changed = false;
      final placements = current.placements
          .map((placement) {
            if (placement.workspaceId != workspaceId ||
                placement.noteId != noteId) {
              return placement;
            }
            if (placement.pinned == pinned) {
              return placement;
            }
            changed = true;
            return placement.copyWith(pinned: pinned);
          })
          .toList(growable: false);

      if (!changed) {
        return;
      }

      await _savePending(current.copyWith(placements: placements));
    });
  }

  Future<void> updatePlacement(WorkspacePlacement placement) {
    return _serialize(() async {
      await ensureInitialized();
      final current = _state!;
      var found = false;
      final placements = current.placements
          .map((existing) {
            if (existing.workspaceId == placement.workspaceId &&
                existing.noteId == placement.noteId) {
              found = true;
              return placement;
            }
            return existing;
          })
          .toList(growable: true);
      if (!found) {
        placements.add(placement);
      }
      await _savePending(current.copyWith(placements: placements));
    });
  }

  Future<String> createLink({
    required String workspaceId,
    required String sourceNoteId,
    required String targetNoteId,
    required int colorValue,
    String label = '',
    bool directed = true,
  }) {
    final completer = Completer<String>();
    _serialize(() async {
      await ensureInitialized();
      if (sourceNoteId == targetNoteId) {
        throw ArgumentError('A note cannot link to itself.');
      }
      final current = _state!;
      if (!current.containsNoteInWorkspace(workspaceId, sourceNoteId) ||
          !current.containsNoteInWorkspace(workspaceId, targetNoteId)) {
        throw StateError('Both notes must be visible in the workspace.');
      }
      final existing = current.links.where(
        (link) =>
            link.workspaceId == workspaceId &&
            link.sourceNoteId == sourceNoteId &&
            link.targetNoteId == targetNoteId,
      );
      if (existing.isNotEmpty) {
        completer.complete(existing.first.id);
        return;
      }

      final now = DateTime.now().toUtc();
      final link = NoteLinkDefinition(
        id: _uuid.v4(),
        workspaceId: workspaceId,
        sourceNoteId: sourceNoteId,
        targetNoteId: targetNoteId,
        colorValue: colorValue,
        label: label.trim(),
        directed: directed,
        createdAt: now,
        updatedAt: now,
      );
      await _savePending(current.copyWith(links: [...current.links, link]));
      completer.complete(link.id);
    }).catchError(completer.completeError);
    return completer.future;
  }

  Future<void> deleteLink(String linkId) {
    return _serialize(() async {
      await ensureInitialized();
      final current = _state!;
      final links = current.links
          .where((link) => link.id != linkId)
          .toList(growable: false);
      if (links.length == current.links.length) {
        return;
      }
      await _savePending(current.copyWith(links: links));
    });
  }

  Future<void> replaceFromServer(WorkspaceStateDocument serverState) {
    return _serialize(() async {
      await ensureInitialized();
      final local = _state!;
      final adapted = _preserveLocalView(serverState, local);
      _state = adapted;
      _baseState = serverState;
      _syncStatus = 'synced';
      await _persist(adapted, syncStatus: _syncStatus);
      await _persistBase(serverState);
      _emit(adapted);
    });
  }

  Future<void> markSynced() {
    return _serialize(() async {
      await ensureInitialized();
      if (_syncStatus == 'synced') {
        return;
      }
      _syncStatus = 'synced';
      _baseState = _state;
      await _persist(_state!, syncStatus: _syncStatus);
      await _persistBase(_state!);
      _emit(_state!);
    });
  }

  Future<void> _saveLocalView(WorkspaceStateDocument next) async {
    _state = next;
    await _persist(next, syncStatus: _syncStatus);
    _emit(next);
  }

  Future<void> _savePending(WorkspaceStateDocument next) async {
    final timestamp = DateTime.now().toUtc();
    final updated = next.copyWith(updatedAt: timestamp);
    _state = updated;
    _syncStatus = 'pending';
    await _persist(updated, syncStatus: _syncStatus);
    _emit(updated);
  }

  Future<void> _persist(
    WorkspaceStateDocument state, {
    required String syncStatus,
  }) {
    return database.customStatement(
      '''
      INSERT INTO $_tableName (id, state_json, updated_at, sync_status)
      VALUES (1, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        state_json = excluded.state_json,
        updated_at = excluded.updated_at,
        sync_status = excluded.sync_status
      ''',
      [
        jsonEncode(state.toJson()),
        state.updatedAt.toUtc().toIso8601String(),
        syncStatus,
      ],
    );
  }

  Future<void> _persistBase(WorkspaceStateDocument state) {
    return database.customStatement(
      '''
      INSERT INTO $_baseTableName (id, state_json)
      VALUES (1, ?)
      ON CONFLICT(id) DO UPDATE SET
        state_json = excluded.state_json
      ''',
      [jsonEncode(state.toJson())],
    );
  }

  WorkspaceStateDocument _preserveLocalView(
    WorkspaceStateDocument server,
    WorkspaceStateDocument local,
  ) {
    final localById = {
      for (final workspace in local.workspaces) workspace.id: workspace,
    };
    final workspaces = server.workspaces
        .map((workspace) {
          final localWorkspace = localById[workspace.id];
          if (localWorkspace == null) return workspace;
          return workspace.copyWith(
            cameraX: localWorkspace.cameraX,
            cameraY: localWorkspace.cameraY,
            scale: localWorkspace.scale,
          );
        })
        .toList(growable: false);
    final activeWorkspaceId =
        workspaces.any((workspace) => workspace.id == local.activeWorkspaceId)
        ? local.activeWorkspaceId
        : server.activeWorkspaceId;
    return server.copyWith(
      activeWorkspaceId: activeWorkspaceId,
      workspaces: workspaces,
    );
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _writeQueue.then((_) => operation());
    _writeQueue = result.catchError((_) {});
    return result;
  }

  void _emit(WorkspaceStateDocument state) {
    if (!_changes.isClosed) {
      _changes.add(state);
    }
  }

  Future<void> dispose() => _changes.close();

  WorkspacePlacement _initialPlacement({
    required String workspaceId,
    required String noteId,
    required int index,
  }) {
    const columns = 5;
    final column = index % columns;
    final row = index ~/ columns;
    return WorkspacePlacement(
      workspaceId: workspaceId,
      noteId: noteId,
      x: 100 + column * 310,
      y: 100 + row * 270,
      width: 270,
      height: 230,
      zIndex: index,
    );
  }

  String _cleanWorkspaceName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Workspace';
    }
    return trimmed.length <= 80 ? trimmed : trimmed.substring(0, 80);
  }
}

class WorkspaceLocalSnapshot {
  const WorkspaceLocalSnapshot({
    required this.state,
    required this.syncStatus,
    this.baseState,
  });

  final WorkspaceStateDocument state;
  final String syncStatus;
  final WorkspaceStateDocument? baseState;

  bool get isPending => syncStatus == 'pending';
  bool get isUnknown => syncStatus == 'unknown';
}
