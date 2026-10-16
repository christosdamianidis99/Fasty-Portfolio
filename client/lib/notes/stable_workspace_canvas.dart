import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../database/app_database.dart';
import 'floating_note_card.dart';
import 'task_progression.dart';
import 'workspace_state.dart';

class StableWorkspaceCanvas extends StatefulWidget {
  const StableWorkspaceCanvas({
    super.key,
    required this.workspace,
    required this.notes,
    required this.placements,
    required this.links,
    required this.onEdit,
    required this.onDelete,
    required this.onScaleChanged,
    required this.onLayoutChanged,
    required this.onViewChanged,
    this.onDuplicate,
    this.onConnect,
    this.onShowConnections,
    this.onTogglePinned,
    this.onAddToWorkspace,
    this.onRemoveFromWorkspace,
  });

  final WorkspaceDefinition workspace;
  final List<LocalNote> notes;
  final List<WorkspacePlacement> placements;
  final List<NoteLinkDefinition> links;
  final ValueChanged<LocalNote> onEdit;
  final ValueChanged<LocalNote> onDelete;
  final ValueChanged<double> onScaleChanged;
  final ValueChanged<WorkspacePlacement> onLayoutChanged;
  final void Function(double translationX, double translationY, double scale)
  onViewChanged;
  final ValueChanged<LocalNote>? onDuplicate;
  final ValueChanged<LocalNote>? onConnect;
  final ValueChanged<LocalNote>? onShowConnections;
  final ValueChanged<LocalNote>? onTogglePinned;
  final ValueChanged<LocalNote>? onAddToWorkspace;
  final ValueChanged<LocalNote>? onRemoveFromWorkspace;

  @override
  State<StableWorkspaceCanvas> createState() => StableWorkspaceCanvasState();
}

class StableWorkspaceCanvasState extends State<StableWorkspaceCanvas> {
  static const double _defaultNoteWidth = 270;
  static const double _defaultNoteHeight = 230;
  static const double _minimumNoteWidth = 190;
  static const double _minimumNoteHeight = 150;
  static const double _minimumScale = 0.20;
  static const double _maximumScale = 3.0;
  static const double _canvasMargin = 900;
  static const double _fitMargin = 100;

  final TransformationController _transformation = TransformationController();
  final GlobalKey _viewportKey = GlobalKey();
  final Map<String, ValueNotifier<_NoteLayout>> _layouts = {};
  final ValueNotifier<int> _layoutRevision = ValueNotifier<int>(0);

  Rect _canvasBounds = const Rect.fromLTWH(-800, -600, 1600, 1200);
  Offset? _gestureAnchor;
  double _gestureStartScale = 1;
  double _lastReportedScale = 1;

  double get scale => _transformation.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _ensureLayouts();
    _resetCanvasBounds();
    _applyWorkspaceTransform();
    _lastReportedScale = widget.workspace.scale;
    _transformation.addListener(_reportScale);
  }

  @override
  void didUpdateWidget(covariant StableWorkspaceCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.id != widget.workspace.id) {
      for (final layout in _layouts.values) {
        layout.dispose();
      }
      _layouts.clear();
      _ensureLayouts();
      _resetCanvasBounds();
      _applyWorkspaceTransform();
      _lastReportedScale = widget.workspace.scale;
      widget.onScaleChanged(widget.workspace.scale);
      return;
    }
    _ensureLayouts(updateExisting: true);
    _expandCanvasForAllNotes();
  }

  @override
  void dispose() {
    _transformation
      ..removeListener(_reportScale)
      ..dispose();
    _layoutRevision.dispose();
    for (final layout in _layouts.values) {
      layout.dispose();
    }
    super.dispose();
  }

  void _applyWorkspaceTransform() {
    _transformation.value = Matrix4.identity()
      ..setEntry(0, 0, widget.workspace.scale)
      ..setEntry(1, 1, widget.workspace.scale)
      ..setTranslationRaw(
        widget.workspace.cameraX,
        widget.workspace.cameraY,
        0,
      );
  }

  void _ensureLayouts({bool updateExisting = false}) {
    final placements = <String, WorkspacePlacement>{
      for (final placement in widget.placements) placement.noteId: placement,
    };

    for (var index = 0; index < widget.notes.length; index++) {
      final note = widget.notes[index];
      final placement = placements[note.id];
      final next = placement == null
          ? _initialLayout(index)
          : _NoteLayout.fromPlacement(placement);
      final existing = _layouts[note.id];
      if (existing == null) {
        _layouts[note.id] = ValueNotifier<_NoteLayout>(next);
      } else if (updateExisting && existing.value != next) {
        existing.value = next;
      }
    }

    final activeIds = widget.notes.map((note) => note.id).toSet();
    final removedIds = _layouts.keys
        .where((id) => !activeIds.contains(id))
        .toList(growable: false);
    for (final id in removedIds) {
      _layouts.remove(id)?.dispose();
    }
    _bumpLayoutRevision();
  }

  _NoteLayout _initialLayout(int index) {
    const horizontalSpacing = 310.0;
    const verticalSpacing = 270.0;
    const columns = 4;
    final column = index % columns;
    final row = index ~/ columns;

    return _NoteLayout(
      x: column * horizontalSpacing,
      y: row * verticalSpacing,
      width: _defaultNoteWidth,
      height: _defaultNoteHeight,
      zIndex: index,
      pinned: false,
    );
  }

  Rect _notesBounds() {
    if (_layouts.isEmpty) {
      return const Rect.fromLTWH(-400, -300, 800, 600);
    }
    Rect? result;
    for (final layout in _layouts.values) {
      result = result == null
          ? layout.value.rect
          : result.expandToInclude(layout.value.rect);
    }
    return result!;
  }

  void _resetCanvasBounds() {
    final notes = _notesBounds().inflate(_canvasMargin);
    final minimum = Rect.fromCenter(
      center: notes.center,
      width: math.max(1600, notes.width),
      height: math.max(1200, notes.height),
    );
    _canvasBounds = minimum;
  }

  void _expandCanvasForAllNotes() {
    _expandCanvasFor(_notesBounds());
  }

  void _expandCanvasFor(Rect rect) {
    final required = rect.inflate(_canvasMargin);
    final expanded = _canvasBounds.expandToInclude(required);
    if (expanded == _canvasBounds) {
      return;
    }
    setState(() => _canvasBounds = expanded);
  }

  void _reportScale() {
    final current = scale;
    if ((current - _lastReportedScale).abs() < 0.005) {
      return;
    }
    _lastReportedScale = current;
    widget.onScaleChanged(current);
  }

  Offset _toViewport(Offset globalPosition) {
    final renderObject = _viewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) {
      return globalPosition;
    }
    return renderObject.globalToLocal(globalPosition);
  }

  void _onScaleStart(ScaleStartDetails details) {
    final focalPoint = _toViewport(details.focalPoint);
    _gestureStartScale = scale;
    _gestureAnchor = _transformation.toScene(focalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final anchor = _gestureAnchor;
    if (anchor == null) {
      return;
    }

    final focalPoint = _toViewport(details.focalPoint);
    final targetScale = (_gestureStartScale * details.scale)
        .clamp(_minimumScale, _maximumScale)
        .toDouble();
    _setTransform(anchor: anchor, focalPoint: focalPoint, scale: targetScale);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _gestureAnchor = null;
    _persistView();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) {
      return;
    }

    final factor = event.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12;
    zoomAtGlobalPoint(event.position, factor);
    _persistView();
  }

  void zoomFromCenter(double factor) {
    final renderObject = _viewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) {
      return;
    }

    final localCenter = renderObject.size.center(Offset.zero);
    zoomAtGlobalPoint(renderObject.localToGlobal(localCenter), factor);
    _persistView();
  }

  void zoomAtGlobalPoint(Offset globalPoint, double factor) {
    final focalPoint = _toViewport(globalPoint);
    final anchor = _transformation.toScene(focalPoint);
    final targetScale = (scale * factor)
        .clamp(_minimumScale, _maximumScale)
        .toDouble();
    _setTransform(anchor: anchor, focalPoint: focalPoint, scale: targetScale);
  }

  void focusNote(String noteId) {
    final layout = _layouts[noteId]?.value;
    final renderObject = _viewportKey.currentContext?.findRenderObject();

    if (layout == null || renderObject is! RenderBox) {
      return;
    }

    final viewport = renderObject.size;
    if (viewport.isEmpty) {
      return;
    }

    final currentScale = scale;
    final viewportCenter = viewport.center(Offset.zero);
    final targetCenter = layout.rect.center;
    final translationX = viewportCenter.dx - targetCenter.dx * currentScale;
    final translationY = viewportCenter.dy - targetCenter.dy * currentScale;

    _transformation.value = Matrix4.identity()
      ..setEntry(0, 0, currentScale)
      ..setEntry(1, 1, currentScale)
      ..setTranslationRaw(translationX, translationY, 0);

    _persistView();
  }

  /// Centers all notes and chooses the largest scale that fits them.
  /// The existing toolbar's center button calls this method.
  void resetView() {
    final renderObject = _viewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) {
      return;
    }

    final bounds = _notesBounds().inflate(_fitMargin);
    final viewport = renderObject.size;
    if (viewport.isEmpty || bounds.isEmpty) {
      _transformation.value = Matrix4.identity();
      _persistView();
      return;
    }

    final targetScale = math
        .min(viewport.width / bounds.width, viewport.height / bounds.height)
        .clamp(_minimumScale, 1.25)
        .toDouble();
    final translationX = viewport.width / 2 - bounds.center.dx * targetScale;
    final translationY = viewport.height / 2 - bounds.center.dy * targetScale;
    _transformation.value = Matrix4.identity()
      ..setEntry(0, 0, targetScale)
      ..setEntry(1, 1, targetScale)
      ..setTranslationRaw(translationX, translationY, 0);
    _persistView();
  }

  void _persistView() {
    final matrix = _transformation.value;
    widget.onViewChanged(matrix.storage[12], matrix.storage[13], scale);
  }

  void _setTransform({
    required Offset anchor,
    required Offset focalPoint,
    required double scale,
  }) {
    final translationX = focalPoint.dx - anchor.dx * scale;
    final translationY = focalPoint.dy - anchor.dy * scale;

    _transformation.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setTranslationRaw(translationX, translationY, 0);
  }

  void _moveNote(String noteId, Offset viewportDelta) {
    final layout = _layouts[noteId];
    if (layout == null) {
      return;
    }

    final current = layout.value;
    final sceneDelta = viewportDelta / scale;
    final next = current.copyWith(
      x: current.x + sceneDelta.dx,
      y: current.y + sceneDelta.dy,
    );
    layout.value = next;
    _expandCanvasFor(next.rect);
    _bumpLayoutRevision();
  }

  void _resizeNote(String noteId, Offset viewportDelta) {
    final layout = _layouts[noteId];
    if (layout == null) {
      return;
    }

    final current = layout.value;
    final sceneDelta = viewportDelta / scale;
    final next = current.copyWith(
      width: math.max(_minimumNoteWidth, current.width + sceneDelta.dx),
      height: math.max(_minimumNoteHeight, current.height + sceneDelta.dy),
    );
    layout.value = next;
    _expandCanvasFor(next.rect);
    _bumpLayoutRevision();
  }

  void _persistLayout(String noteId) {
    final layout = _layouts[noteId]?.value;
    if (layout == null) {
      return;
    }
    widget.onLayoutChanged(
      layout.toPlacement(workspaceId: widget.workspace.id, noteId: noteId),
    );
  }

  void _bumpLayoutRevision() {
    _layoutRevision.value = _layoutRevision.value + 1;
  }

  Matrix4 _displayTransform() {
    final base = _transformation.value;
    final currentScale = base.getMaxScaleOnAxis();
    return Matrix4.copy(base)..setTranslationRaw(
      base.storage[12] + _canvasBounds.left * currentScale,
      base.storage[13] + _canvasBounds.top * currentScale,
      0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: ColoredBox(
        color: colors.surfaceContainerLowest,
        child: ClipRect(
          key: _viewportKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                onPointerSignal: _onPointerSignal,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: AnimatedBuilder(
                    animation: _transformation,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _InfiniteGridPainter(
                          transform: _transformation.value,
                          background: colors.surfaceContainerLowest,
                          secondaryBackground: colors.surfaceContainerLow,
                          dotColor: colors.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                width: _canvasBounds.width,
                height: _canvasBounds.height,
                child: AnimatedBuilder(
                  animation: _transformation,
                  builder: (context, child) {
                    return Transform(
                      transform: _displayTransform(),
                      alignment: Alignment.topLeft,
                      transformHitTests: true,
                      child: child,
                    );
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: ValueListenableBuilder<int>(
                              valueListenable: _layoutRevision,
                              builder: (context, revision, _) {
                                return CustomPaint(
                                  painter: _NoteLinksPainter(
                                    links: widget.links,
                                    readyLinkIds: readyTaskProgressionLinkIds(
                                      links: widget.links,
                                      noteContents: {
                                        for (final note in widget.notes)
                                          note.id: note.content,
                                      },
                                    ),
                                    layouts: {
                                      for (final entry in _layouts.entries)
                                        entry.key: entry.value.value.rect.shift(
                                          -_canvasBounds.topLeft,
                                        ),
                                    },
                                    revision: revision,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      for (final note in _sortedNotes()) _buildNote(note),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<LocalNote> _sortedNotes() {
    final notes = [...widget.notes];
    notes.sort((left, right) {
      final leftZ = _layouts[left.id]?.value.zIndex ?? 0;
      final rightZ = _layouts[right.id]?.value.zIndex ?? 0;
      return leftZ.compareTo(rightZ);
    });
    return notes;
  }

  Widget _buildNote(LocalNote note) {
    final layout = _layouts[note.id]!;
    final isPinned = layout.value.pinned;
    final hasConnections = widget.links.any(
      (link) => link.sourceNoteId == note.id || link.targetNoteId == note.id,
    );

    return ValueListenableBuilder<_NoteLayout>(
      key: ValueKey(note.id),
      valueListenable: layout,
      builder: (context, value, _) {
        return Positioned(
          left: value.x - _canvasBounds.left,
          top: value.y - _canvasBounds.top,
          width: value.width,
          height: value.height,
          child: RepaintBoundary(
            child: FloatingNoteCard(
              note: note,
              isNextTaskReady: readyTaskProgressionTargetIds(
                links: widget.links,
                noteContents: {
                  for (final item in widget.notes) item.id: item.content,
                },
              ).contains(note.id),
              width: value.width,
              height: value.height,
              onMove: (delta) => _moveNote(note.id, delta),
              onMoveEnd: () => _persistLayout(note.id),
              onResize: (delta) => _resizeNote(note.id, delta),
              onResizeEnd: () => _persistLayout(note.id),
              onEdit: () => widget.onEdit(note),
              onDuplicate: widget.onDuplicate == null
                  ? null
                  : () => widget.onDuplicate!(note),
              onConnect: widget.onConnect == null
                  ? null
                  : () => widget.onConnect!(note),
              onShowConnections:
                  widget.onShowConnections == null || !hasConnections
                  ? null
                  : () => widget.onShowConnections!(note),
              isPinned: isPinned,
              onTogglePinned: widget.onTogglePinned == null
                  ? null
                  : () => widget.onTogglePinned!(note),
              onAddToWorkspace: widget.onAddToWorkspace == null
                  ? null
                  : () => widget.onAddToWorkspace!(note),
              onRemoveFromWorkspace: widget.onRemoveFromWorkspace == null
                  ? null
                  : () => widget.onRemoveFromWorkspace!(note),
              onDelete: () => widget.onDelete(note),
            ),
          ),
        );
      },
    );
  }
}

class _InfiniteGridPainter extends CustomPainter {
  const _InfiniteGridPainter({
    required this.transform,
    required this.background,
    required this.secondaryBackground,
    required this.dotColor,
  });

  final Matrix4 transform;
  final Color background;
  final Color secondaryBackground;
  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [background, secondaryBackground],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final currentScale = transform.getMaxScaleOnAxis();
    final spacing = 32.0 * currentScale;
    if (spacing < 7) {
      return;
    }

    final translationX = transform.storage[12];
    final translationY = transform.storage[13];
    final firstX = translationX % spacing;
    final firstY = translationY % spacing;
    final radius = (1.2 * currentScale).clamp(0.8, 2.2).toDouble();
    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    for (double x = firstX; x < size.width; x += spacing) {
      for (double y = firstY; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_InfiniteGridPainter oldDelegate) {
    return oldDelegate.transform != transform ||
        oldDelegate.background != background ||
        oldDelegate.secondaryBackground != secondaryBackground ||
        oldDelegate.dotColor != dotColor;
  }
}

class _NoteLinksPainter extends CustomPainter {
  const _NoteLinksPainter({
    required this.links,
    required this.readyLinkIds,
    required this.layouts,
    required this.revision,
  });

  final List<NoteLinkDefinition> links;
  final Set<String> readyLinkIds;
  final Map<String, Rect> layouts;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    for (final link in links) {
      final source = layouts[link.sourceNoteId];
      final target = layouts[link.targetNoteId];
      if (source == null || target == null) {
        continue;
      }

      final start = _edgePoint(source, target.center);
      final end = _edgePoint(target, source.center);
      final horizontalDistance = (end.dx - start.dx).abs();
      final curve = math.max(48.0, horizontalDistance * 0.42);
      final direction = end.dx >= start.dx ? 1.0 : -1.0;
      final control1 = Offset(start.dx + curve * direction, start.dy);
      final control2 = Offset(end.dx - curve * direction, end.dy);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          control1.dx,
          control1.dy,
          control2.dx,
          control2.dy,
          end.dx,
          end.dy,
        );
      final baseColor = Color(link.colorValue);
      final progression = isTaskProgressionLink(link);
      final ready = readyLinkIds.contains(link.id);
      final color = progression
          ? baseColor.withValues(alpha: ready ? 1 : 0.32)
          : baseColor;
      final strokeWidth = progression ? (ready ? 4.5 : 2.0) : 3.0;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, paint);

      if (link.directed) {
        _drawArrow(canvas, end, control2, color, strokeWidth);
      }
      if (link.label.trim().isNotEmpty) {
        _drawLabel(canvas, source.center, target.center, link.label, color);
      }
    }
  }

  Offset _edgePoint(Rect rect, Offset toward) {
    final center = rect.center;
    final dx = toward.dx - center.dx;
    final dy = toward.dy - center.dy;
    if (dx == 0 && dy == 0) {
      return center;
    }

    final scaleX = dx == 0 ? double.infinity : rect.width / 2 / dx.abs();
    final scaleY = dy == 0 ? double.infinity : rect.height / 2 / dy.abs();
    final factor = math.min(scaleX, scaleY);
    return center + Offset(dx * factor, dy * factor);
  }

  void _drawArrow(
    Canvas canvas,
    Offset end,
    Offset previous,
    Color color,
    double strokeWidth,
  ) {
    final angle = math.atan2(end.dy - previous.dy, end.dx - previous.dx);
    const arrowLength = 14.0;
    const arrowAngle = math.pi / 7;
    final first =
        end -
        Offset(
          math.cos(angle - arrowAngle) * arrowLength,
          math.sin(angle - arrowAngle) * arrowLength,
        );
    final second =
        end -
        Offset(
          math.cos(angle + arrowAngle) * arrowLength,
          math.sin(angle + arrowAngle) * arrowLength,
        );
    final arrowPath = Path()
      ..moveTo(first.dx, first.dy)
      ..lineTo(end.dx, end.dy)
      ..lineTo(second.dx, second.dy);
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawLabel(
    Canvas canvas,
    Offset source,
    Offset target,
    String label,
    Color color,
  ) {
    final midpoint = Offset(
      (source.dx + target.dx) / 2,
      (source.dy + target.dy) / 2,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          backgroundColor: Colors.white.withValues(alpha: 0.88),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 180);
    painter.paint(
      canvas,
      midpoint - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_NoteLinksPainter oldDelegate) {
    return oldDelegate.revision != revision ||
        oldDelegate.links != links ||
        oldDelegate.readyLinkIds != readyLinkIds ||
        oldDelegate.layouts != layouts;
  }
}

class _NoteLayout {
  const _NoteLayout({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.zIndex,
    required this.pinned,
  });

  factory _NoteLayout.fromPlacement(WorkspacePlacement placement) {
    return _NoteLayout(
      x: placement.x,
      y: placement.y,
      width: placement.width,
      height: placement.height,
      zIndex: placement.zIndex,
      pinned: placement.pinned,
    );
  }

  final double x;
  final double y;
  final double width;
  final double height;
  final int zIndex;
  final bool pinned;

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  WorkspacePlacement toPlacement({
    required String workspaceId,
    required String noteId,
  }) {
    return WorkspacePlacement(
      workspaceId: workspaceId,
      noteId: noteId,
      x: x,
      y: y,
      width: width,
      height: height,
      zIndex: zIndex,
      pinned: pinned,
    );
  }

  _NoteLayout copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    int? zIndex,
    bool? pinned,
  }) {
    return _NoteLayout(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      zIndex: zIndex ?? this.zIndex,
      pinned: pinned ?? this.pinned,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _NoteLayout &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height &&
        other.zIndex == zIndex &&
        other.pinned == pinned;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height, zIndex, pinned);
}
