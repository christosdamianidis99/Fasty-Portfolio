import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../settings/app_strings.dart';
import 'note_markdown.dart';
import 'note_task_status.dart';

class FloatingNoteCard extends StatelessWidget {
  const FloatingNoteCard({
    super.key,
    required this.note,
    required this.width,
    required this.height,
    required this.onMove,
    required this.onResize,
    required this.onEdit,
    required this.onDelete,
    this.onMoveEnd,
    this.onResizeEnd,
    this.onDuplicate,
    this.onConnect,
    this.onShowConnections,
    this.onTogglePinned,
    this.isPinned = false,
    this.onAddToWorkspace,
    this.onRemoveFromWorkspace,
    this.isNextTaskReady = false,
  });

  final LocalNote note;
  final double width;
  final double height;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onMoveEnd;
  final VoidCallback? onResizeEnd;
  final VoidCallback? onDuplicate;
  final VoidCallback? onConnect;
  final VoidCallback? onShowConnections;
  final VoidCallback? onTogglePinned;
  final bool isPinned;
  final VoidCallback? onAddToWorkspace;
  final VoidCallback? onRemoveFromWorkspace;
  final bool isNextTaskReady;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = _accentFor(note.id, colors);

    return Material(
      elevation: 4,
      shadowColor: colors.shadow.withValues(alpha: 0.18),
      color: colors.surfaceContainerLow,
      surfaceTintColor: accent.background,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: accent.foreground.withValues(alpha: 0.16)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, accent),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                  child: NoteTaskStatus(content: note.content),
                ),
                Expanded(child: _buildContent(context)),
                _buildFooter(context),
              ],
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: _ResizeHandle(
                onResize: onResize,
                onResizeEnd: onResizeEnd,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, _NoteAccent accent) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: accent.background,
        border: Border(
          bottom: BorderSide(color: accent.foreground.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => onMove(details.delta),
                onPanEnd: (_) => onMoveEnd?.call(),
                onPanCancel: onMoveEnd,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: accent.foreground.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 18,
                          color: accent.foreground.withValues(alpha: 0.78),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          note.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: accent.foreground,
                              ),
                        ),
                      ),
                      if (isPinned) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: strings.pinnedNote,
                          child: Icon(
                            Icons.push_pin_rounded,
                            size: 17,
                            color: accent.foreground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isNextTaskReady)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: strings.nextTaskReadyHint,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.flag_rounded,
                        size: 13,
                        color: colors.onPrimaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        strings.nextTaskBadge,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          PopupMenuButton<_FloatingNoteAction>(
            tooltip: strings.noteOptions,
            iconColor: accent.foreground,
            onSelected: (action) {
              switch (action) {
                case _FloatingNoteAction.edit:
                  onEdit();
                case _FloatingNoteAction.duplicate:
                  onDuplicate?.call();
                case _FloatingNoteAction.connect:
                  onConnect?.call();
                case _FloatingNoteAction.connections:
                  onShowConnections?.call();
                case _FloatingNoteAction.pin:
                  onTogglePinned?.call();
                case _FloatingNoteAction.addToWorkspace:
                  onAddToWorkspace?.call();
                case _FloatingNoteAction.removeFromWorkspace:
                  onRemoveFromWorkspace?.call();
                case _FloatingNoteAction.delete:
                  onDelete();
              }
            },
            itemBuilder: (context) => [
              _menuItem(
                _FloatingNoteAction.edit,
                Icons.edit_outlined,
                strings.editNote,
              ),
              if (onDuplicate != null)
                _menuItem(
                  _FloatingNoteAction.duplicate,
                  Icons.copy_all_outlined,
                  strings.duplicateNote,
                ),
              if (onConnect != null)
                _menuItem(
                  _FloatingNoteAction.connect,
                  Icons.polyline_outlined,
                  strings.connectToNote,
                ),
              if (onShowConnections != null)
                _menuItem(
                  _FloatingNoteAction.connections,
                  Icons.hub_outlined,
                  strings.connectedNotes,
                ),
              if (onTogglePinned != null)
                _menuItem(
                  _FloatingNoteAction.pin,
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  isPinned ? strings.unpinNote : strings.pinNote,
                ),
              if (onAddToWorkspace != null)
                _menuItem(
                  _FloatingNoteAction.addToWorkspace,
                  Icons.drive_file_move_outline,
                  strings.showInAnotherWorkspace,
                ),
              if (onRemoveFromWorkspace != null)
                _menuItem(
                  _FloatingNoteAction.removeFromWorkspace,
                  Icons.remove_circle_outline,
                  strings.removeFromThisWorkspace,
                ),
              const PopupMenuDivider(),
              _menuItem(
                _FloatingNoteAction.delete,
                Icons.delete_outline,
                strings.moveToTrash,
              ),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_FloatingNoteAction> _menuItem(
    _FloatingNoteAction value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem(
      value: value,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(label),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final strings = AppStrings.of(context);
    final content = note.content.trim();
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onEdit,
      onDoubleTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        child: Align(
          alignment: Alignment.topLeft,
          child: content.isEmpty
              ? Text(
                  strings.tapToStartWriting,
                  maxLines: _calculateContentLines(),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    color: colors.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : ClipRect(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: IgnorePointer(child: NoteMarkdown(data: content)),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final strings = AppStrings.of(context);
    final isPending = note.syncStatus == 'pending';
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 58, 13),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: isPending
                  ? colors.tertiaryContainer
                  : colors.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPending
                      ? Icons.cloud_upload_outlined
                      : Icons.cloud_done_outlined,
                  size: 14,
                  color: isPending
                      ? colors.onTertiaryContainer
                      : colors.onSecondaryContainer,
                ),
                const SizedBox(width: 5),
                Text(
                  isPending ? strings.pending : strings.synced,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isPending
                        ? colors.onTertiaryContainer
                        : colors.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  int _calculateContentLines() {
    final availableHeight = height - 132;
    return (availableHeight / 21).floor().clamp(1, 22);
  }

  _NoteAccent _accentFor(String id, ColorScheme colors) {
    final accents = [
      _NoteAccent(colors.primaryContainer, colors.onPrimaryContainer),
      _NoteAccent(colors.secondaryContainer, colors.onSecondaryContainer),
      _NoteAccent(colors.tertiaryContainer, colors.onTertiaryContainer),
      _NoteAccent(
        Color.alphaBlend(
          colors.primary.withValues(alpha: 0.10),
          colors.surfaceContainer,
        ),
        colors.onSurface,
      ),
      _NoteAccent(
        Color.alphaBlend(
          colors.tertiary.withValues(alpha: 0.11),
          colors.surfaceContainer,
        ),
        colors.onSurface,
      ),
    ];
    return accents[id.hashCode.abs() % accents.length];
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onResize, this.onResizeEnd});

  final ValueChanged<Offset> onResize;
  final VoidCallback? onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeDownRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onResize(details.delta),
        onPanEnd: (_) => onResizeEnd?.call(),
        onPanCancel: onResizeEnd,
        child: SizedBox(
          width: 58,
          height: 58,
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CustomPaint(
                  painter: _ResizeGripPainter(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResizeGripPainter extends CustomPainter {
  const _ResizeGripPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width - 5, size.height - 13),
      Offset(size.width - 13, size.height - 5),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - 5, size.height - 7),
      Offset(size.width - 7, size.height - 5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ResizeGripPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _NoteAccent {
  const _NoteAccent(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

enum _FloatingNoteAction {
  edit,
  duplicate,
  connect,
  connections,
  pin,
  addToWorkspace,
  removeFromWorkspace,
  delete,
}
