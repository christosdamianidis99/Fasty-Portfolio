import 'workspace_state.dart';

WorkspaceStateDocument mergeWorkspaceStateDocuments({
  required WorkspaceStateDocument local,
  required WorkspaceStateDocument remote,
  WorkspaceStateDocument? base,
}) {
  final mergedWorkspaces = _mergeWorkspaces(local, remote, base);
  final workspaceIds = mergedWorkspaces.map((item) => item.id).toSet();
  final mergedPlacements = _mergePlacements(local, remote, base)
      .where((item) => workspaceIds.contains(item.workspaceId))
      .toList(growable: false);
  final mergedLinks = _mergeLinks(local, remote, base)
      .where(
        (item) =>
            workspaceIds.contains(item.workspaceId) &&
            mergedPlacements.any(
              (placement) =>
                  placement.workspaceId == item.workspaceId &&
                  placement.noteId == item.sourceNoteId,
            ) &&
            mergedPlacements.any(
              (placement) =>
                  placement.workspaceId == item.workspaceId &&
                  placement.noteId == item.targetNoteId,
            ),
      )
      .toList(growable: false);

  final activeWorkspaceId = workspaceIds.contains(local.activeWorkspaceId)
      ? local.activeWorkspaceId
      : workspaceIds.contains(remote.activeWorkspaceId)
      ? remote.activeWorkspaceId
      : mergedWorkspaces.first.id;

  final newestTimestamp = [
    DateTime.now().toUtc(),
    local.updatedAt.toUtc(),
    remote.updatedAt.toUtc(),
  ].reduce((left, right) => left.isAfter(right) ? left : right);

  return WorkspaceStateDocument(
    schemaVersion: WorkspaceStateDocument.currentSchemaVersion,
    activeWorkspaceId: activeWorkspaceId,
    workspaces: mergedWorkspaces,
    placements: mergedPlacements,
    links: mergedLinks,
    updatedAt: newestTimestamp.add(const Duration(microseconds: 1)),
  );
}

List<WorkspaceDefinition> _mergeWorkspaces(
  WorkspaceStateDocument local,
  WorkspaceStateDocument remote,
  WorkspaceStateDocument? base,
) {
  final localMap = {for (final item in local.workspaces) item.id: item};
  final remoteMap = {for (final item in remote.workspaces) item.id: item};
  final baseMap = {
    for (final item in base?.workspaces ?? const <WorkspaceDefinition>[])
      item.id: item,
  };
  final ids = <String>{
    ...local.workspaces.map((item) => item.id),
    ...remote.workspaces.map((item) => item.id),
    ...baseMap.keys,
  };

  final result = <WorkspaceDefinition>[];
  for (final id in ids) {
    final selected = _chooseThreeWay<WorkspaceDefinition>(
      base: baseMap[id],
      local: localMap[id],
      remote: remoteMap[id],
      localDocumentTime: local.updatedAt,
      remoteDocumentTime: remote.updatedAt,
      equals: _workspaceSharedEquals,
      legacyResolver: (left, right) {
        if (left == null) return right;
        if (right == null) return left;
        return left.updatedAt.isAfter(right.updatedAt) ? left : right;
      },
    );
    if (selected == null) continue;

    final localView = localMap[id];
    result.add(
      localView == null
          ? selected
          : selected.copyWith(
              cameraX: localView.cameraX,
              cameraY: localView.cameraY,
              scale: localView.scale,
            ),
    );
  }
  if (result.isEmpty) {
    return WorkspaceStateDocument.initial().workspaces;
  }
  return result;
}

List<WorkspacePlacement> _mergePlacements(
  WorkspaceStateDocument local,
  WorkspaceStateDocument remote,
  WorkspaceStateDocument? base,
) {
  String key(WorkspacePlacement item) => '${item.workspaceId}::${item.noteId}';
  final localMap = {for (final item in local.placements) key(item): item};
  final remoteMap = {for (final item in remote.placements) key(item): item};
  final baseMap = {
    for (final item in base?.placements ?? const <WorkspacePlacement>[])
      key(item): item,
  };
  final keys = <String>{...localMap.keys, ...remoteMap.keys, ...baseMap.keys};
  final result = <WorkspacePlacement>[];
  for (final itemKey in keys) {
    final selected = _chooseThreeWay<WorkspacePlacement>(
      base: baseMap[itemKey],
      local: localMap[itemKey],
      remote: remoteMap[itemKey],
      localDocumentTime: local.updatedAt,
      remoteDocumentTime: remote.updatedAt,
      equals: _placementEquals,
      legacyResolver: (left, right) {
        if (left == null) return right;
        if (right == null) return left;
        return local.updatedAt.isAfter(remote.updatedAt) ? left : right;
      },
    );
    if (selected != null) result.add(selected);
  }
  return result;
}

List<NoteLinkDefinition> _mergeLinks(
  WorkspaceStateDocument local,
  WorkspaceStateDocument remote,
  WorkspaceStateDocument? base,
) {
  final localMap = {for (final item in local.links) item.id: item};
  final remoteMap = {for (final item in remote.links) item.id: item};
  final baseMap = {
    for (final item in base?.links ?? const <NoteLinkDefinition>[])
      item.id: item,
  };
  final ids = <String>{...localMap.keys, ...remoteMap.keys, ...baseMap.keys};
  final result = <NoteLinkDefinition>[];
  for (final id in ids) {
    final selected = _chooseThreeWay<NoteLinkDefinition>(
      base: baseMap[id],
      local: localMap[id],
      remote: remoteMap[id],
      localDocumentTime: local.updatedAt,
      remoteDocumentTime: remote.updatedAt,
      equals: _linkEquals,
      legacyResolver: (left, right) {
        if (left == null) return right;
        if (right == null) return left;
        return left.updatedAt.isAfter(right.updatedAt) ? left : right;
      },
    );
    if (selected != null) result.add(selected);
  }
  return result;
}

T? _chooseThreeWay<T>({
  required T? base,
  required T? local,
  required T? remote,
  required DateTime localDocumentTime,
  required DateTime remoteDocumentTime,
  required bool Function(T left, T right) equals,
  required T? Function(T? local, T? remote) legacyResolver,
}) {
  if (base == null) {
    return legacyResolver(local, remote);
  }

  final localChanged = !_nullableEquals(base, local, equals);
  final remoteChanged = !_nullableEquals(base, remote, equals);
  if (localChanged && !remoteChanged) return local;
  if (remoteChanged && !localChanged) return remote;
  if (!localChanged && !remoteChanged) return local ?? remote;
  if (_nullableEquals(local, remote, equals)) return local;
  return localDocumentTime.isAfter(remoteDocumentTime) ? local : remote;
}

bool _nullableEquals<T>(T? left, T? right, bool Function(T, T) equals) {
  if (identical(left, right)) return true;
  if (left == null || right == null) return false;
  return equals(left, right);
}

bool _workspaceSharedEquals(
  WorkspaceDefinition left,
  WorkspaceDefinition right,
) {
  return left.id == right.id &&
      left.name == right.name &&
      left.colorValue == right.colorValue &&
      left.createdAt.isAtSameMomentAs(right.createdAt) &&
      left.updatedAt.isAtSameMomentAs(right.updatedAt);
}

bool _placementEquals(WorkspacePlacement left, WorkspacePlacement right) {
  return left.workspaceId == right.workspaceId &&
      left.noteId == right.noteId &&
      left.x == right.x &&
      left.y == right.y &&
      left.width == right.width &&
      left.height == right.height &&
      left.zIndex == right.zIndex &&
      left.pinned == right.pinned;
}

bool _linkEquals(NoteLinkDefinition left, NoteLinkDefinition right) {
  return left.id == right.id &&
      left.workspaceId == right.workspaceId &&
      left.sourceNoteId == right.sourceNoteId &&
      left.targetNoteId == right.targetNoteId &&
      left.colorValue == right.colorValue &&
      left.label == right.label &&
      left.directed == right.directed &&
      left.createdAt.isAtSameMomentAs(right.createdAt) &&
      left.updatedAt.isAtSameMomentAs(right.updatedAt);
}
