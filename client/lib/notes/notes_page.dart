import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'floating_note_card.dart';
import 'local_notes_repository.dart';
import 'note_editor.dart';
import 'notes_sync_service.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({
    super.key,
    required this.repository,
    required this.syncService,
  });

  final LocalNotesRepository repository;
  final NotesSyncService syncService;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  static const Uuid _uuid = Uuid();

  static const double _canvasWidth = 1400;
  static const double _canvasHeight = 1800;

  static const double _defaultNoteWidth = 260;
  static const double _defaultNoteHeight = 220;
  static const double _minimumNoteWidth = 190;
  static const double _minimumNoteHeight = 150;
  static const double _maximumNoteWidth = 620;
  static const double _maximumNoteHeight = 560;

  static const double _minimumCanvasScale = 0.5;
  static const double _maximumCanvasScale = 2.0;
  static const double _wheelZoomFactor = 1.12;

  final TransformationController _transformationController =
      TransformationController();
  final GlobalKey _canvasViewportKey = GlobalKey();
  final Map<String, _NoteLayout> _noteLayouts = {};
  final TextEditingController _searchController = TextEditingController();

  late Stream<List<LocalNote>> _notesStream;
  late Stream<List<LocalNote>> _trashStream;

  Offset? _canvasGestureAnchor;
  double _canvasGestureStartScale = 1.0;
  int _selectedDestination = 0;
  int _activityRevision = 0;
  bool _isSynchronizing = false;

  @override
  void initState() {
    super.initState();
    _notesStream = widget.repository.watchNotes();
    _trashStream = widget.repository.watchDeletedNotes();
    _searchController.addListener(_onSearchChanged);
    unawaited(widget.repository.purgeExpiredTrash());
  }

  @override
  void didUpdateWidget(covariant NotesPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.repository, widget.repository)) {
      _notesStream = widget.repository.watchNotes();
      _trashStream = widget.repository.watchDeletedNotes();
      unawaited(widget.repository.purgeExpiredTrash());
    }
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _selectDestination(int index) {
    setState(() {
      _selectedDestination = index;
      if (index == 2) {
        _activityRevision++;
      }
    });
  }

  Future<void> _syncNotes() async {
    if (_isSynchronizing) {
      return;
    }

    setState(() => _isSynchronizing = true);

    try {
      await widget.syncService.syncPendingOperations();
      await widget.repository.purgeExpiredTrash();

      if (!mounted) {
        return;
      }

      setState(() => _activityRevision++);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Notes are up to date.')));
    } catch (error) {
      _showError('Synchronization failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isSynchronizing = false);
      }
    }
  }

  Future<void> _createNote() async {
    final draft = await showNoteEditor(context);

    if (draft == null || !mounted) {
      return;
    }

    try {
      final now = DateTime.now().toUtc();
      final id = _uuid.v4();

      await widget.repository.createNote(
        id: id,
        title: draft.title,
        content: draft.content,
        now: now,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedDestination = 0;
        _noteLayouts[id] = _createLayoutForNewNote();
        _activityRevision++;
      });
    } catch (error) {
      _showError('Could not create note: $error');
    }
  }

  Future<void> _editNote(LocalNote note) async {
    final draft = await showNoteEditor(context, note: note);

    if (draft == null || !mounted) {
      return;
    }

    try {
      await widget.repository.updateNote(
        id: note.id,
        title: draft.title,
        content: draft.content,
        createdAt: note.createdAt,
        updatedAt: DateTime.now().toUtc(),
      );

      if (mounted) {
        setState(() => _activityRevision++);
      }
    } catch (error) {
      _showError('Could not update note: $error');
    }
  }

  Future<void> _moveToTrash(LocalNote note) async {
    try {
      await widget.repository.deleteNote(
        id: note.id,
        updatedAt: DateTime.now().toUtc(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _noteLayouts.remove(note.id);
        _activityRevision++;
      });

      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: const Text('Moved to Trash · Recoverable for 14 days'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              unawaited(_restoreNote(note));
            },
          ),
        ),
      );
    } catch (error) {
      _showError('Could not move note to Trash: $error');
    }
  }

  Future<void> _restoreNote(LocalNote note) async {
    try {
      await widget.repository.restoreNote(
        note: note,
        updatedAt: DateTime.now().toUtc(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedDestination = 0;
        _noteLayouts.putIfAbsent(note.id, _createLayoutForNewNote);
        _activityRevision++;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note restored to the workspace.')),
      );
    } catch (error) {
      _showError('Could not restore note: $error');
    }
  }

  Future<void> _permanentlyDeleteNote(LocalNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_forever_outlined),
        title: const Text('Delete permanently?'),
        content: Text(
          '“${note.title}” will no longer be recoverable on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await widget.repository.permanentlyDeleteNote(note.id);
      if (mounted) {
        setState(() => _activityRevision++);
      }
    } catch (error) {
      _showError('Could not permanently delete note: $error');
    }
  }

  void _moveNote(String noteId, Offset delta) {
    final layout = _noteLayouts[noteId];

    if (layout == null) {
      return;
    }

    final maximumX = _canvasWidth - layout.width;
    final maximumY = _canvasHeight - layout.height;

    setState(() {
      _noteLayouts[noteId] = layout.copyWith(
        x: (layout.x + delta.dx).clamp(0.0, maximumX),
        y: (layout.y + delta.dy).clamp(0.0, maximumY),
      );
    });
  }

  void _resizeNote(String noteId, Offset delta) {
    final layout = _noteLayouts[noteId];

    if (layout == null) {
      return;
    }

    final maximumWidth = (_canvasWidth - layout.x).clamp(
      _minimumNoteWidth,
      _maximumNoteWidth,
    );
    final maximumHeight = (_canvasHeight - layout.y).clamp(
      _minimumNoteHeight,
      _maximumNoteHeight,
    );

    setState(() {
      _noteLayouts[noteId] = layout.copyWith(
        width: (layout.width + delta.dx).clamp(_minimumNoteWidth, maximumWidth),
        height: (layout.height + delta.dy).clamp(
          _minimumNoteHeight,
          maximumHeight,
        ),
      );
    });
  }

  double get _canvasScale {
    return _transformationController.value.getMaxScaleOnAxis();
  }

  Offset _toViewportPosition(Offset globalPosition) {
    final renderObject = _canvasViewportKey.currentContext?.findRenderObject();

    if (renderObject is! RenderBox) {
      return globalPosition;
    }

    return renderObject.globalToLocal(globalPosition);
  }

  void _startCanvasGesture(ScaleStartDetails details) {
    final focalPoint = _toViewportPosition(details.focalPoint);
    _canvasGestureStartScale = _canvasScale;
    _canvasGestureAnchor = _transformationController.toScene(focalPoint);
  }

  void _updateCanvasGesture(ScaleUpdateDetails details) {
    final anchor = _canvasGestureAnchor;

    if (anchor == null) {
      return;
    }

    final focalPoint = _toViewportPosition(details.focalPoint);
    final targetScale = (_canvasGestureStartScale * details.scale)
        .clamp(_minimumCanvasScale, _maximumCanvasScale)
        .toDouble();

    _setCanvasTransform(
      anchor: anchor,
      focalPoint: focalPoint,
      scale: targetScale,
    );
  }

  void _endCanvasGesture(ScaleEndDetails details) {
    _canvasGestureAnchor = null;
  }

  void _handleCanvasPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) {
      return;
    }

    final factor = event.scrollDelta.dy < 0
        ? _wheelZoomFactor
        : 1 / _wheelZoomFactor;

    _zoomCanvasAt(event.position, factor);
  }

  void _zoomCanvasAt(Offset globalFocalPoint, double factor) {
    final focalPoint = _toViewportPosition(globalFocalPoint);
    final anchor = _transformationController.toScene(focalPoint);
    final targetScale = (_canvasScale * factor)
        .clamp(_minimumCanvasScale, _maximumCanvasScale)
        .toDouble();

    _setCanvasTransform(
      anchor: anchor,
      focalPoint: focalPoint,
      scale: targetScale,
    );
  }

  void _zoomCanvasFromCenter(double factor) {
    final renderObject = _canvasViewportKey.currentContext?.findRenderObject();

    if (renderObject is! RenderBox) {
      return;
    }

    final localCenter = renderObject.size.center(Offset.zero);
    _zoomCanvasAt(renderObject.localToGlobal(localCenter), factor);
  }

  void _setCanvasTransform({
    required Offset anchor,
    required Offset focalPoint,
    required double scale,
  }) {
    final translationX = focalPoint.dx - anchor.dx * scale;
    final translationY = focalPoint.dy - anchor.dy * scale;

    _transformationController.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setTranslationRaw(translationX, translationY, 0);
  }

  void _resetCanvasView() {
    _transformationController.value = Matrix4.identity();
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _matchesSearch(LocalNote note) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }

    return note.title.toLowerCase().contains(query) ||
        note.content.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useNavigationRail = constraints.maxWidth >= 900;

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          appBar: _buildAppBar(),
          body: Row(
            children: [
              if (useNavigationRail) _buildNavigationRail(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey(_selectedDestination),
                    child: switch (_selectedDestination) {
                      0 => _buildWorkspace(useNavigationRail),
                      1 => _buildTrash(),
                      _ => _buildActivity(),
                    },
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: useNavigationRail
              ? null
              : NavigationBar(
                  selectedIndex: _selectedDestination,
                  onDestinationSelected: _selectDestination,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.space_dashboard_outlined),
                      selectedIcon: Icon(Icons.space_dashboard),
                      label: 'Workspace',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.delete_outline),
                      selectedIcon: Icon(Icons.delete),
                      label: 'Trash',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.sync_alt_outlined),
                      selectedIcon: Icon(Icons.sync_alt),
                      label: 'Activity',
                    ),
                  ],
                ),
          floatingActionButton: _selectedDestination == 0
              ? FloatingActionButton.extended(
                  onPressed: _createNote,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New note'),
                )
              : null,
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final title = switch (_selectedDestination) {
      0 => 'Workspace',
      1 => 'Trash',
      _ => 'Sync activity',
    };

    return AppBar(
      titleSpacing: 20,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.auto_awesome_mosaic_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Fasty'),
              Text(
                title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Synchronize notes',
          onPressed: _isSynchronizing ? null : _syncNotes,
          icon: _isSynchronizing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_sync_outlined),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildNavigationRail() {
    return NavigationRail(
      selectedIndex: _selectedDestination,
      onDestinationSelected: _selectDestination,
      labelType: NavigationRailLabelType.all,
      groupAlignment: -0.72,
      leading: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: FloatingActionButton.small(
          tooltip: 'New note',
          onPressed: _createNote,
          child: const Icon(Icons.add),
        ),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.space_dashboard_outlined),
          selectedIcon: Icon(Icons.space_dashboard),
          label: Text('Workspace'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.delete_outline),
          selectedIcon: Icon(Icons.delete),
          label: Text('Trash'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.sync_alt_outlined),
          selectedIcon: Icon(Icons.sync_alt),
          label: Text('Activity'),
        ),
      ],
    );
  }

  Widget _buildWorkspace(bool isDesktop) {
    return Column(
      children: [
        _WorkspaceToolbar(
          searchController: _searchController,
          isDesktop: isDesktop,
          scale: _canvasScale,
          onZoomOut: () => _zoomCanvasFromCenter(1 / _wheelZoomFactor),
          onZoomIn: () => _zoomCanvasFromCenter(_wheelZoomFactor),
          onReset: _resetCanvasView,
          onSync: _isSynchronizing ? null : _syncNotes,
        ),
        Expanded(
          child: StreamBuilder<List<LocalNote>>(
            stream: _notesStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return _ErrorState(error: snapshot.error);
              }

              final allNotes = snapshot.data ?? const <LocalNote>[];
              final notes = allNotes.where(_matchesSearch).toList();

              if (allNotes.isEmpty) {
                return _EmptyWorkspace(onCreateNote: _createNote);
              }

              if (notes.isEmpty) {
                return const _NoSearchResults();
              }

              _ensureLayoutsExist(allNotes);
              return _buildCanvas(notes);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTrash() {
    return StreamBuilder<List<LocalNote>>(
      stream: _trashStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _ErrorState(error: snapshot.error);
        }

        final deletedNotes = (snapshot.data ?? const <LocalNote>[])
            .where(_matchesSearch)
            .toList();

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Column(
                  children: [
                    SearchBar(
                      controller: _searchController,
                      hintText: 'Search Trash',
                      leading: const Icon(Icons.search),
                      trailing: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            tooltip: 'Clear search',
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _TrashInfoBanner(count: snapshot.data?.length ?? 0),
                  ],
                ),
              ),
            ),
            if (deletedNotes.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyTrash(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final columns = width >= 1050
                        ? 3
                        : width >= 680
                        ? 2
                        : 1;

                    return SliverGrid.builder(
                      itemCount: deletedNotes.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        mainAxisExtent: 190,
                      ),
                      itemBuilder: (context, index) {
                        final note = deletedNotes[index];
                        return _TrashNoteCard(
                          note: note,
                          daysRemaining: widget.repository.trashDaysRemaining(
                            note,
                          ),
                          onRestore: () => _restoreNote(note),
                          onDeleteForever: () => _permanentlyDeleteNote(note),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildActivity() {
    return FutureBuilder<List<OutboxOperation>>(
      key: ValueKey(_activityRevision),
      future: widget.repository.getPendingOperations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _ErrorState(error: snapshot.error);
        }

        final operations = snapshot.data ?? const <OutboxOperation>[];

        return RefreshIndicator(
          onRefresh: () async {
            await _syncNotes();
            if (mounted) {
              setState(() => _activityRevision++);
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              _ActivityHero(
                operationCount: operations.length,
                isSynchronizing: _isSynchronizing,
                onSync: _isSynchronizing ? null : _syncNotes,
              ),
              const SizedBox(height: 18),
              if (operations.isEmpty)
                const _EmptyActivity()
              else
                ...operations.map(
                  (operation) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _OperationCard(operation: operation),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCanvas(List<LocalNote> notes) {
    return ClipRect(
      key: _canvasViewportKey,
      child: Listener(
        onPointerSignal: _handleCanvasPointerSignal,
        child: AnimatedBuilder(
          animation: _transformationController,
          builder: (context, child) {
            return Transform(
              transform: _transformationController.value,
              alignment: Alignment.topLeft,
              transformHitTests: true,
              child: child,
            );
          },
          child: SizedBox(
            width: _canvasWidth,
            height: _canvasHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _startCanvasGesture,
                    onScaleUpdate: _updateCanvasGesture,
                    onScaleEnd: _endCanvasGesture,
                    child: const _CanvasBackground(),
                  ),
                ),
                for (final note in notes) _buildPositionedNote(note),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPositionedNote(LocalNote note) {
    final layout = _noteLayouts[note.id]!;

    return Positioned(
      key: ValueKey(note.id),
      left: layout.x,
      top: layout.y,
      width: layout.width,
      height: layout.height,
      child: FloatingNoteCard(
        note: note,
        width: layout.width,
        height: layout.height,
        onMove: (delta) => _moveNote(note.id, delta),
        onResize: (delta) => _resizeNote(note.id, delta),
        onEdit: () => _editNote(note),
        onDelete: () => _moveToTrash(note),
      ),
    );
  }

  void _ensureLayoutsExist(List<LocalNote> notes) {
    for (var index = 0; index < notes.length; index++) {
      final note = notes[index];
      _noteLayouts.putIfAbsent(note.id, () => _createInitialLayout(index));
    }

    final activeIds = notes.map((note) => note.id).toSet();
    _noteLayouts.removeWhere((id, _) => !activeIds.contains(id));
  }

  _NoteLayout _createInitialLayout(int index) {
    const horizontalSpacing = 300.0;
    const verticalSpacing = 260.0;
    const columns = 4;

    final column = index % columns;
    final row = index ~/ columns;

    return _NoteLayout(
      x: 70 + column * horizontalSpacing,
      y: 70 + row * verticalSpacing,
      width: _defaultNoteWidth,
      height: _defaultNoteHeight,
    );
  }

  _NoteLayout _createLayoutForNewNote() {
    return _createInitialLayout(_noteLayouts.length);
  }
}

class _WorkspaceToolbar extends StatelessWidget {
  const _WorkspaceToolbar({
    required this.searchController,
    required this.isDesktop,
    required this.scale,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onReset,
    required this.onSync,
  });

  final TextEditingController searchController;
  final bool isDesktop;
  final double scale;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onReset;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: SearchBar(
                controller: searchController,
                hintText: 'Search notes',
                leading: const Icon(Icons.search),
                trailing: [
                  if (searchController.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      onPressed: searchController.clear,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (isDesktop) ...[
              IconButton.filledTonal(
                tooltip: 'Zoom out',
                onPressed: onZoomOut,
                icon: const Icon(Icons.zoom_out),
              ),
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 60),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: Text('${(scale * 100).round()}%'),
              ),
              IconButton.filledTonal(
                tooltip: 'Zoom in',
                onPressed: onZoomIn,
                icon: const Icon(Icons.zoom_in),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Reset canvas view',
                onPressed: onReset,
                icon: const Icon(Icons.center_focus_strong),
              ),
            ] else
              PopupMenuButton<_CanvasAction>(
                tooltip: 'Canvas controls',
                icon: const Icon(Icons.tune),
                onSelected: (action) {
                  switch (action) {
                    case _CanvasAction.zoomOut:
                      onZoomOut();
                    case _CanvasAction.zoomIn:
                      onZoomIn();
                    case _CanvasAction.reset:
                      onReset();
                    case _CanvasAction.sync:
                      onSync?.call();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _CanvasAction.zoomOut,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.zoom_out),
                      title: Text('Zoom out'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _CanvasAction.zoomIn,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.zoom_in),
                      title: Text('Zoom in'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _CanvasAction.reset,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.center_focus_strong),
                      title: Text('Reset view'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _CanvasAction.sync,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.cloud_sync_outlined),
                      title: Text('Sync now'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CanvasBackground extends StatelessWidget {
  const _CanvasBackground();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceContainerLowest, colors.surfaceContainerLow],
        ),
      ),
      child: CustomPaint(
        painter: _DotGridPainter(
          color: colors.outlineVariant.withValues(alpha: 0.46),
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 32.0;
    const dotRadius = 1.25;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace({required this.onCreateNote});

  final VoidCallback onCreateNote;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(34),
                ),
                child: Icon(
                  Icons.dashboard_customize_outlined,
                  size: 52,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 26),
              Text(
                'Build your thinking space',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Create flexible notes, arrange them freely and keep working even when you are offline.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onCreateNote,
                icon: const Icon(Icons.add),
                label: const Text('Create your first note'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 54),
            SizedBox(height: 14),
            Text('No notes match your search.'),
          ],
        ),
      ),
    );
  }
}

class _TrashInfoBanner extends StatelessWidget {
  const _TrashInfoBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(Icons.restore_from_trash, color: colors.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              count == 1
                  ? '1 note is recoverable for up to 14 days.'
                  : '$count notes are recoverable for up to 14 days.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrashNoteCard extends StatelessWidget {
  const _TrashNoteCard({
    required this.note,
    required this.daysRemaining,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final LocalNote note;
  final int daysRemaining;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete permanently',
                  onPressed: onDeleteForever,
                  icon: const Icon(Icons.delete_forever_outlined),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                note.content.trim().isEmpty
                    ? 'No content'
                    : note.content.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    daysRemaining <= 0
                        ? 'Expires soon'
                        : '$daysRemaining days remaining',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Restore'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTrash extends StatelessWidget {
  const _EmptyTrash();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_sweep_outlined, size: 58),
            SizedBox(height: 14),
            Text('Trash is empty'),
            SizedBox(height: 6),
            Text('Deleted notes will stay here for 14 days.'),
          ],
        ),
      ),
    );
  }
}

class _ActivityHero extends StatelessWidget {
  const _ActivityHero({
    required this.operationCount,
    required this.isSynchronizing,
    required this.onSync,
  });

  final int operationCount;
  final bool isSynchronizing;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.cloud_sync_outlined),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  operationCount == 0
                      ? 'Everything is synchronized'
                      : '$operationCount pending actions',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Local changes are stored safely and retried when a connection is available.',
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onSync,
            icon: isSynchronizing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(isSynchronizing ? 'Syncing…' : 'Sync now'),
          ),
        ],
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.operation});

  final OutboxOperation operation;

  @override
  Widget build(BuildContext context) {
    final icon = switch (operation.operation) {
      'create' => Icons.note_add_outlined,
      'update' => Icons.edit_note_outlined,
      'delete' => Icons.delete_outline,
      _ => Icons.sync_problem_outlined,
    };

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(
          '${operation.operation[0].toUpperCase()}${operation.operation.substring(1)} note',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              operation.noteId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (operation.lastError != null) ...[
              const SizedBox(height: 4),
              Text(
                operation.lastError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: operation.retryCount > 0
            ? Chip(label: Text('${operation.retryCount} retries'))
            : const Icon(Icons.schedule),
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 54),
      child: Column(
        children: [
          Icon(Icons.cloud_done_outlined, size: 62),
          SizedBox(height: 14),
          Text('No pending actions'),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storage_outlined, size: 52),
            const SizedBox(height: 16),
            Text(
              'Could not load notes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _NoteLayout {
  const _NoteLayout({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  _NoteLayout copyWith({double? x, double? y, double? width, double? height}) {
    return _NoteLayout(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

enum _CanvasAction { zoomOut, zoomIn, reset, sync }
