class WorkspaceStateDocument {
  const WorkspaceStateDocument({
    required this.schemaVersion,
    required this.activeWorkspaceId,
    required this.workspaces,
    required this.placements,
    required this.links,
    required this.updatedAt,
  });

  static const currentSchemaVersion = 1;
  static const defaultWorkspaceId = 'default-workspace';

  final int schemaVersion;
  final String activeWorkspaceId;
  final List<WorkspaceDefinition> workspaces;
  final List<WorkspacePlacement> placements;
  final List<NoteLinkDefinition> links;
  final DateTime updatedAt;

  factory WorkspaceStateDocument.initial({DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return WorkspaceStateDocument(
      schemaVersion: currentSchemaVersion,
      activeWorkspaceId: defaultWorkspaceId,
      workspaces: [
        WorkspaceDefinition(
          id: defaultWorkspaceId,
          name: 'My workspace',
          colorValue: 0xFF625BEB,
          cameraX: 0,
          cameraY: 0,
          scale: 1,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      ],
      placements: const [],
      links: const [],
      updatedAt: timestamp,
    );
  }

  factory WorkspaceStateDocument.fromJson(Map<String, dynamic> json) {
    final parsedWorkspaces = (json['workspaces'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(WorkspaceDefinition.fromJson)
        .toList(growable: false);

    final fallback = WorkspaceStateDocument.initial(
      now: _readDateTime(json['updatedAt'], DateTime.now().toUtc()),
    );
    final workspaces = parsedWorkspaces.isEmpty
        ? fallback.workspaces
        : parsedWorkspaces;
    final requestedActiveId = json['activeWorkspaceId'] as String?;
    final activeWorkspaceId =
        workspaces.any((workspace) => workspace.id == requestedActiveId)
        ? requestedActiveId!
        : workspaces.first.id;

    return WorkspaceStateDocument(
      schemaVersion: _readInt(json['schemaVersion'], currentSchemaVersion),
      activeWorkspaceId: activeWorkspaceId,
      workspaces: workspaces,
      placements: (json['placements'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(WorkspacePlacement.fromJson)
          .toList(growable: false),
      links: (json['links'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(NoteLinkDefinition.fromJson)
          .toList(growable: false),
      updatedAt: _readDateTime(json['updatedAt'], fallback.updatedAt),
    );
  }

  WorkspaceDefinition get activeWorkspace => workspaces.firstWhere(
    (workspace) => workspace.id == activeWorkspaceId,
    orElse: () => workspaces.first,
  );

  List<WorkspacePlacement> placementsFor(String workspaceId) => placements
      .where((placement) => placement.workspaceId == workspaceId)
      .toList(growable: false);

  List<NoteLinkDefinition> linksFor(String workspaceId) => links
      .where((link) => link.workspaceId == workspaceId)
      .toList(growable: false);

  WorkspacePlacement? placementFor(String workspaceId, String noteId) {
    for (final placement in placements) {
      if (placement.workspaceId == workspaceId && placement.noteId == noteId) {
        return placement;
      }
    }
    return null;
  }

  bool containsNoteInWorkspace(String workspaceId, String noteId) {
    return placementFor(workspaceId, noteId) != null;
  }

  bool containsNoteAnywhere(String noteId) {
    return placements.any((placement) => placement.noteId == noteId);
  }

  WorkspaceStateDocument copyWith({
    int? schemaVersion,
    String? activeWorkspaceId,
    List<WorkspaceDefinition>? workspaces,
    List<WorkspacePlacement>? placements,
    List<NoteLinkDefinition>? links,
    DateTime? updatedAt,
  }) {
    return WorkspaceStateDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      activeWorkspaceId: activeWorkspaceId ?? this.activeWorkspaceId,
      workspaces: workspaces ?? this.workspaces,
      placements: placements ?? this.placements,
      links: links ?? this.links,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'activeWorkspaceId': activeWorkspaceId,
    'workspaces': workspaces.map((workspace) => workspace.toJson()).toList(),
    'placements': placements.map((placement) => placement.toJson()).toList(),
    'links': links.map((link) => link.toJson()).toList(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

class WorkspaceDefinition {
  const WorkspaceDefinition({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.cameraX,
    required this.cameraY,
    required this.scale,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int colorValue;
  final double cameraX;
  final double cameraY;
  final double scale;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory WorkspaceDefinition.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    return WorkspaceDefinition(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? json['id'] as String
          : WorkspaceStateDocument.defaultWorkspaceId,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Workspace',
      colorValue: _readInt(json['colorValue'], 0xFF625BEB),
      cameraX: _readDouble(json['cameraX'], 0),
      cameraY: _readDouble(json['cameraY'], 0),
      scale: _readDouble(json['scale'], 1).clamp(0.45, 2.25).toDouble(),
      createdAt: _readDateTime(json['createdAt'], now),
      updatedAt: _readDateTime(json['updatedAt'], now),
    );
  }

  WorkspaceDefinition copyWith({
    String? name,
    int? colorValue,
    double? cameraX,
    double? cameraY,
    double? scale,
    DateTime? updatedAt,
  }) {
    return WorkspaceDefinition(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      cameraX: cameraX ?? this.cameraX,
      cameraY: cameraY ?? this.cameraY,
      scale: scale ?? this.scale,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'cameraX': cameraX,
    'cameraY': cameraY,
    'scale': scale,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

class WorkspacePlacement {
  const WorkspacePlacement({
    required this.workspaceId,
    required this.noteId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.zIndex,
    this.pinned = false,
  });

  final String workspaceId;
  final String noteId;
  final double x;
  final double y;
  final double width;
  final double height;
  final int zIndex;
  final bool pinned;

  factory WorkspacePlacement.fromJson(Map<String, dynamic> json) {
    return WorkspacePlacement(
      workspaceId: json['workspaceId'] as String? ?? '',
      noteId: json['noteId'] as String? ?? '',
      x: _readDouble(json['x'], 100),
      y: _readDouble(json['y'], 100),
      width: _readDouble(json['width'], 270),
      height: _readDouble(json['height'], 230),
      zIndex: _readInt(json['zIndex'], 0),
      pinned: json['pinned'] as bool? ?? false,
    );
  }

  WorkspacePlacement copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    int? zIndex,
    bool? pinned,
  }) {
    return WorkspacePlacement(
      workspaceId: workspaceId,
      noteId: noteId,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      zIndex: zIndex ?? this.zIndex,
      pinned: pinned ?? this.pinned,
    );
  }

  Map<String, dynamic> toJson() => {
    'workspaceId': workspaceId,
    'noteId': noteId,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'zIndex': zIndex,
    'pinned': pinned,
  };
}

class NoteLinkDefinition {
  const NoteLinkDefinition({
    required this.id,
    required this.workspaceId,
    required this.sourceNoteId,
    required this.targetNoteId,
    required this.colorValue,
    required this.label,
    required this.directed,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String workspaceId;
  final String sourceNoteId;
  final String targetNoteId;
  final int colorValue;
  final String label;
  final bool directed;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory NoteLinkDefinition.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    return NoteLinkDefinition(
      id: json['id'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? '',
      sourceNoteId: json['sourceNoteId'] as String? ?? '',
      targetNoteId: json['targetNoteId'] as String? ?? '',
      colorValue: _readInt(json['colorValue'], 0xFF625BEB),
      label: json['label'] as String? ?? '',
      directed: json['directed'] as bool? ?? true,
      createdAt: _readDateTime(json['createdAt'], now),
      updatedAt: _readDateTime(json['updatedAt'], now),
    );
  }

  NoteLinkDefinition copyWith({
    int? colorValue,
    String? label,
    bool? directed,
    DateTime? updatedAt,
  }) {
    return NoteLinkDefinition(
      id: id,
      workspaceId: workspaceId,
      sourceNoteId: sourceNoteId,
      targetNoteId: targetNoteId,
      colorValue: colorValue ?? this.colorValue,
      label: label ?? this.label,
      directed: directed ?? this.directed,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'workspaceId': workspaceId,
    'sourceNoteId': sourceNoteId,
    'targetNoteId': targetNoteId,
    'colorValue': colorValue,
    'label': label,
    'directed': directed,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

int _readInt(dynamic value, int fallback) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('$value') ?? fallback;
}

double _readDouble(dynamic value, double fallback) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse('$value') ?? fallback;
}

DateTime _readDateTime(dynamic value, DateTime fallback) {
  if (value is DateTime) {
    return value.toUtc();
  }
  return DateTime.tryParse('$value')?.toUtc() ?? fallback.toUtc();
}
