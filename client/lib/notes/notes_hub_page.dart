import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../settings/app_strings.dart';
import 'connected_note_navigation.dart';
import 'local_notes_repository.dart';
import 'note_editor.dart';
import 'note_markdown.dart';
import 'task_progression.dart';
import 'workspace_note_organization.dart';
import 'notes_sync_service.dart';
import 'stable_workspace_canvas.dart';
import 'workspace_name_dialog.dart';
import 'workspace_state.dart';
import 'workspace_state_store.dart';

class NotesHubPage extends StatefulWidget {
  const NotesHubPage({
    super.key,
    required this.repository,
    required this.syncService,
    required this.workspaceStore,
    required this.onOpenSettings,
    required this.onOpenSyncDetails,
  });

  final LocalNotesRepository repository;
  final NotesSyncService syncService;
  final WorkspaceStateStore workspaceStore;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenSyncDetails;

  @override
  State<NotesHubPage> createState() => _NotesHubPageState();
}

class _NotesHubPageState extends State<NotesHubPage> {
  static const _uuid = Uuid();

  final GlobalKey<StableWorkspaceCanvasState> _canvasKey = GlobalKey();
  final TextEditingController _workspaceSearch = TextEditingController();
  final TextEditingController _trashSearch = TextEditingController();

  late Stream<List<LocalNote>> _notesStream;
  late Stream<List<LocalNote>> _trashStream;
  late Stream<WorkspaceStateDocument> _workspaceStream;

  List<LocalNote> _latestAllNotes = const [];
  int _selectedDestination = 0;
  int _activityRevision = 0;
  double _canvasScale = 1;
  bool _isSynchronizing = false;
  WorkspaceNoteSort _workspaceSort = WorkspaceNoteSort.recentlyUpdated;
  WorkspaceNoteFilter _workspaceFilter = WorkspaceNoteFilter.all;

  @override
  void initState() {
    super.initState();
    _notesStream = widget.repository.watchNotes();
    _trashStream = widget.repository.watchDeletedNotes();
    _workspaceStream = widget.workspaceStore.watchState();
    _workspaceSearch.addListener(_refreshSearch);
    _trashSearch.addListener(_refreshSearch);
    unawaited(widget.workspaceStore.ensureInitialized());
    unawaited(widget.repository.purgeExpiredTrash());
  }

  @override
  void didUpdateWidget(covariant NotesHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      _notesStream = widget.repository.watchNotes();
      _trashStream = widget.repository.watchDeletedNotes();
    }
    if (!identical(oldWidget.workspaceStore, widget.workspaceStore)) {
      _workspaceStream = widget.workspaceStore.watchState();
    }
  }

  @override
  void dispose() {
    _workspaceSearch
      ..removeListener(_refreshSearch)
      ..dispose();
    _trashSearch
      ..removeListener(_refreshSearch)
      ..dispose();
    super.dispose();
  }

  List<_HubDestination> _destinations(AppStrings strings) => [
    _HubDestination(
      label: strings.workspace,
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard_rounded,
    ),
    _HubDestination(
      label: strings.trash,
      icon: Icons.delete_outline,
      selectedIcon: Icons.delete_rounded,
    ),
    _HubDestination(
      label: strings.activity,
      icon: Icons.sync_alt_outlined,
      selectedIcon: Icons.sync_alt_rounded,
    ),
  ];

  void _refreshSearch() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _syncNotes() async {
    if (_isSynchronizing) {
      return;
    }

    setState(() => _isSynchronizing = true);
    final strings = AppStrings.of(context);
    try {
      final summary = await widget.syncService.syncPendingOperations();
      await widget.repository.purgeExpiredTrash();
      if (!mounted) {
        return;
      }
      setState(() => _activityRevision++);
      final message = summary.successfulOperations == 0
          ? strings.syncCheckComplete
          : strings.synchronizedChanges(summary.successfulOperations);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedDestination = 2;
        _activityRevision++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.syncService.status.value.state.name == 'unavailable'
                ? strings.serverUnavailable
                : '${strings.failed}: $error',
          ),
          action: SnackBarAction(
            label: strings.activity,
            onPressed: () => setState(() => _selectedDestination = 2),
          ),
        ),
      );
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

    final strings = AppStrings.of(context);
    try {
      final state = await widget.workspaceStore.currentState();
      final now = DateTime.now().toUtc();
      final id = _uuid.v4();
      await widget.repository.createNote(
        id: id,
        title: draft.title,
        content: draft.content,
        now: now,
      );
      await widget.workspaceStore.addNoteToWorkspace(
        workspaceId: state.activeWorkspaceId,
        noteId: id,
      );
      if (mounted) {
        setState(() {
          _selectedDestination = 0;
          _activityRevision++;
        });
      }
    } catch (error) {
      _showError(strings.operationFailed(strings.createNote, error));
    }
  }

  Future<void> _editNote(LocalNote note) async {
    final draft = await showNoteEditor(context, note: note);
    if (draft == null || !mounted) {
      return;
    }

    final strings = AppStrings.of(context);
    final becameReady = didTaskProgressionBecomeReady(
      beforeMarkdown: note.content,
      afterMarkdown: draft.content,
    );
    try {
      await widget.repository.updateNote(
        id: note.id,
        title: draft.title,
        content: draft.content,
        createdAt: note.createdAt,
        updatedAt: DateTime.now().toUtc(),
      );

      LocalNote? readyTarget;

      if (becameReady) {
        final state = await widget.workspaceStore.currentState();
        final links = state.linksFor(state.activeWorkspaceId);

        for (final link in links) {
          if (link.sourceNoteId != note.id || !isTaskProgressionLink(link)) {
            continue;
          }

          for (final candidate in _latestAllNotes) {
            if (candidate.id == link.targetNoteId && !candidate.isDeleted) {
              readyTarget = candidate;
              break;
            }
          }

          if (readyTarget != null) {
            break;
          }
        }
      }
      if (mounted) {
        setState(() => _activityRevision++);

        if (readyTarget != null) {
          final target = readyTarget;
          final messenger = ScaffoldMessenger.of(context);

          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(strings.nextTaskReadyMessage(target.title)),
              action: SnackBarAction(
                label: strings.openNextTask,
                onPressed: () {
                  if (mounted) {
                    unawaited(_editNote(target));
                  }
                },
              ),
            ),
          );
        }
      }
    } catch (error) {
      _showError(strings.operationFailed(strings.editNote, error));
    }
  }

  Future<void> _duplicateNote(LocalNote note) async {
    final strings = AppStrings.of(context);
    try {
      final state = await widget.workspaceStore.currentState();
      final workspaceId = state.activeWorkspaceId;
      final sourcePlacement = state.placementFor(workspaceId, note.id);
      final now = DateTime.now().toUtc();
      final id = _uuid.v4();
      final suffix = strings.isGreek ? ' αντίγραφο' : ' copy';
      final maximumBaseLength = 300 - suffix.length;
      final baseTitle = note.title.length > maximumBaseLength
          ? note.title.substring(0, maximumBaseLength)
          : note.title;
      await widget.repository.createNote(
        id: id,
        title: '$baseTitle$suffix',
        content: note.content,
        now: now,
      );
      await widget.workspaceStore.addNoteToWorkspace(
        workspaceId: workspaceId,
        noteId: id,
        placement: sourcePlacement,
      );
      if (mounted) {
        setState(() => _activityRevision++);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.noteDuplicated)));
      }
    } catch (error) {
      _showError(strings.operationFailed(strings.duplicateNote, error));
    }
  }

  Future<void> _moveToTrash(LocalNote note) async {
    final strings = AppStrings.of(context);
    try {
      await widget.repository.deleteNote(
        id: note.id,
        updatedAt: DateTime.now().toUtc(),
      );
      if (!mounted) {
        return;
      }
      setState(() => _activityRevision++);
      final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(strings.movedToTrash),
          persist: false,
          action: SnackBarAction(
            label: strings.undo,
            onPressed: () => unawaited(_restoreNote(note)),
          ),
        ),
      );
    } catch (error) {
      _showError(strings.operationFailed(strings.moveToTrash, error));
    }
  }

  Future<void> _restoreNote(LocalNote note) async {
    final strings = AppStrings.of(context);
    try {
      await widget.repository.restoreNote(
        note: note,
        updatedAt: DateTime.now().toUtc(),
      );
      final state = await widget.workspaceStore.currentState();
      if (!state.containsNoteAnywhere(note.id)) {
        await widget.workspaceStore.addNoteToWorkspace(
          workspaceId: state.activeWorkspaceId,
          noteId: note.id,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedDestination = 0;
        _activityRevision++;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.noteRestored)));
    } catch (error) {
      _showError(strings.operationFailed(strings.restore, error));
    }
  }

  Future<void> _deleteForever(LocalNote note) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_forever_outlined),
        title: Text(strings.deletePermanentlyQuestion),
        content: Text(strings.deletePermanentlyMessage(note.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.deletePermanently),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await widget.repository.permanentlyDeleteNote(note.id);
      await widget.workspaceStore.removeNoteEverywhere(note.id);
      if (mounted) {
        setState(() => _activityRevision++);
      }
    } catch (error) {
      _showError(strings.operationFailed(strings.deletePermanently, error));
    }
  }

  Future<void> _createWorkspace() async {
    final strings = AppStrings.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => WorkspaceNameDialog(
        icon: Icons.create_new_folder_outlined,
        title: strings.createWorkspace,
        label: strings.workspaceName,
        hintText: strings.workspaceNameHint,
        cancelLabel: strings.cancel,
        confirmLabel: strings.create,
      ),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }

    try {
      await widget.workspaceStore.createWorkspace(name: name);
      _canvasScale = 1;
    } catch (error) {
      _showError(strings.operationFailed(strings.createWorkspace, error));
    }
  }

  Future<void> _renameWorkspace(WorkspaceDefinition workspace) async {
    final strings = AppStrings.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => WorkspaceNameDialog(
        title: strings.renameWorkspace,
        label: strings.workspaceName,
        cancelLabel: strings.cancel,
        confirmLabel: strings.save,
        initialValue: workspace.name,
      ),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    try {
      await widget.workspaceStore.renameWorkspace(workspace.id, name);
    } catch (error) {
      _showError(strings.operationFailed(strings.renameWorkspace, error));
    }
  }

  Future<void> _deleteWorkspace(WorkspaceStateDocument state) async {
    final strings = AppStrings.of(context);
    if (state.workspaces.length <= 1) {
      _showError(strings.atLeastOneWorkspace);
      return;
    }
    final workspace = state.activeWorkspace;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.folder_delete_outlined),
        title: Text(strings.deleteWorkspaceQuestion),
        content: Text(strings.deleteWorkspaceMessage(workspace.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.deleteWorkspace),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.workspaceStore.deleteWorkspace(workspace.id);
    }
  }

  Future<void> _addExistingNote() async {
    final strings = AppStrings.of(context);
    final state = await widget.workspaceStore.currentState();
    final candidates = _latestAllNotes
        .where(
          (note) =>
              !state.containsNoteInWorkspace(state.activeWorkspaceId, note.id),
        )
        .toList(growable: false);
    if (!mounted) {
      return;
    }
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.everyNoteAlreadyHere)));
      return;
    }

    final note = await showDialog<LocalNote>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(strings.addExistingNote),
        children: [
          for (final candidate in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, candidate),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.note_outlined),
                title: Text(candidate.title),
                subtitle: candidate.content.trim().isEmpty
                    ? null
                    : SizedBox(
                        height: 28,
                        child: ClipRect(
                          child: IgnorePointer(
                            child: NoteMarkdown(data: candidate.content.trim()),
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
    if (note != null) {
      await widget.workspaceStore.addNoteToWorkspace(
        workspaceId: state.activeWorkspaceId,
        noteId: note.id,
      );
    }
  }

  Future<void> _showNoteInAnotherWorkspace(LocalNote note) async {
    final strings = AppStrings.of(context);
    final state = await widget.workspaceStore.currentState();
    final available = state.workspaces
        .where(
          (workspace) => !state.containsNoteInWorkspace(workspace.id, note.id),
        )
        .toList(growable: false);
    if (!mounted) {
      return;
    }
    if (available.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.noteAlreadyEverywhere)));
      return;
    }

    final workspace = await showDialog<WorkspaceDefinition>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(strings.showNoteInWorkspace),
        children: [
          for (final candidate in available)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, candidate),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Color(candidate.colorValue),
                  radius: 10,
                ),
                title: Text(candidate.name),
              ),
            ),
        ],
      ),
    );
    if (workspace == null) {
      return;
    }
    final source = state.placementFor(state.activeWorkspaceId, note.id);
    await widget.workspaceStore.addNoteToWorkspace(
      workspaceId: workspace.id,
      noteId: note.id,
      placement: source,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.noteAddedToWorkspace(workspace.name))),
      );
    }
  }

  Future<void> _removeNoteFromWorkspace(LocalNote note) async {
    final strings = AppStrings.of(context);
    final state = await widget.workspaceStore.currentState();
    final removed = await widget.workspaceStore.removeNoteFromWorkspace(
      workspaceId: state.activeWorkspaceId,
      noteId: note.id,
    );
    if (mounted && !removed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.moveBeforeRemoving)));
    }
  }

  Future<void> _connectNote(LocalNote source) async {
    final strings = AppStrings.of(context);
    final state = await widget.workspaceStore.currentState();
    final workspaceNoteIds = state
        .placementsFor(state.activeWorkspaceId)
        .map((placement) => placement.noteId)
        .toSet();
    final candidates = _latestAllNotes
        .where(
          (note) => note.id != source.id && workspaceNoteIds.contains(note.id),
        )
        .toList(growable: false);
    if (!mounted) {
      return;
    }
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.addAnotherBeforeConnecting)),
      );
      return;
    }

    final draft = await showDialog<_LinkDraft>(
      context: context,
      builder: (context) =>
          _CreateLinkDialog(source: source, candidates: candidates),
    );
    if (draft == null) {
      return;
    }

    try {
      await widget.workspaceStore.createLink(
        workspaceId: state.activeWorkspaceId,
        sourceNoteId: source.id,
        targetNoteId: draft.targetNoteId,
        colorValue: draft.colorValue,
        label: draft.label,
        directed: draft.directed,
      );
    } catch (error) {
      _showError(strings.operationFailed(strings.createConnection, error));
    }
  }

  Future<void> _togglePinnedNote(
    LocalNote note,
    WorkspaceStateDocument state,
  ) async {
    final placement = state.placementFor(state.activeWorkspaceId, note.id);
    if (placement == null) {
      return;
    }

    await widget.workspaceStore.setNotePinned(
      workspaceId: state.activeWorkspaceId,
      noteId: note.id,
      pinned: !placement.pinned,
    );
  }

  Future<void> _showConnectedNotes(
    LocalNote note,
    WorkspaceStateDocument state,
  ) async {
    final strings = AppStrings.of(context);
    final targets = connectedNoteTargets(
      noteId: note.id,
      links: state.linksFor(state.activeWorkspaceId),
    );

    if (!mounted || targets.isEmpty) {
      return;
    }

    final notesById = <String, LocalNote>{
      for (final candidate in _latestAllNotes) candidate.id: candidate,
    };

    final selectedNoteId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              strings.connectedNotes,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final target in targets)
              Card(
                child: ListTile(
                  leading: Icon(switch (target.direction) {
                    ConnectedNoteDirection.outgoing => Icons.call_made_rounded,
                    ConnectedNoteDirection.incoming =>
                      Icons.call_received_rounded,
                    ConnectedNoteDirection.undirected =>
                      Icons.swap_horiz_rounded,
                  }, color: Color(target.link.colorValue)),
                  title: Text(notesById[target.noteId]?.title ?? strings.note),
                  subtitle: Text(
                    [
                      switch (target.direction) {
                        ConnectedNoteDirection.outgoing =>
                          strings.outgoingConnection,
                        ConnectedNoteDirection.incoming =>
                          strings.incomingConnection,
                        ConnectedNoteDirection.undirected =>
                          strings.undirectedConnection,
                      },
                      if (target.link.label.trim().isNotEmpty)
                        target.link.label.trim(),
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.center_focus_strong_outlined),
                  onTap: () => Navigator.pop(context, target.noteId),
                ),
              ),
          ],
        ),
      ),
    );

    if (selectedNoteId != null) {
      _canvasKey.currentState?.focusNote(selectedNoteId);
    }
  }

  Future<void> _manageLinks(WorkspaceStateDocument state) async {
    final strings = AppStrings.of(context);
    final links = state.linksFor(state.activeWorkspaceId);
    final noteNames = <String, String>{
      for (final note in _latestAllNotes) note.id: note.title,
    };
    if (!mounted) {
      return;
    }
    if (links.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.noConnections)));
      return;
    }

    final canFocusCanvas = _canvasKey.currentState != null;
    final action = await showModalBottomSheet<({bool focus, String id})>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              strings.connections,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final item in links)
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.polyline_rounded,
                    color: Color(item.colorValue),
                  ),
                  title: Text(
                    '${noteNames[item.sourceNoteId] ?? strings.note} '
                    '${item.directed ? '→' : '—'} '
                    '${noteNames[item.targetNoteId] ?? strings.note}',
                  ),
                  subtitle: item.label.isEmpty ? null : Text(item.label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canFocusCanvas)
                        IconButton(
                          tooltip: strings.focusTargetNote,
                          onPressed: () => Navigator.pop(context, (
                            focus: true,
                            id: item.targetNoteId,
                          )),
                          icon: const Icon(Icons.center_focus_strong_outlined),
                        ),
                      IconButton(
                        tooltip: strings.deleteConnection,
                        onPressed: () =>
                            Navigator.pop(context, (focus: false, id: item.id)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (action == null) {
      return;
    }

    if (action.focus) {
      _canvasKey.currentState?.focusNote(action.id);
      return;
    }

    await widget.workspaceStore.deleteLink(action.id);
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _matches(LocalNote note, String query) {
    final normalized = query.trim().toLowerCase();
    return normalized.isEmpty ||
        note.title.toLowerCase().contains(normalized) ||
        note.content.toLowerCase().contains(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final destinations = _destinations(strings);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 920;
        final useMobileCards = constraints.maxWidth < 700;
        return Scaffold(
          drawer: useRail ? null : _buildMobileDrawer(destinations, strings),
          appBar: _buildAppBar(
            destinations,
            strings,
            showDesktopActions: useRail,
          ),
          body: Row(
            children: [
              if (useRail) _buildRail(destinations, strings),
              Expanded(
                child: IndexedStack(
                  index: _selectedDestination,
                  children: [
                    _buildWorkspace(useRail, useMobileCards),
                    _buildTrash(),
                    _buildActivity(),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: useRail
              ? null
              : _buildBottomNavigation(destinations),
          floatingActionButtonLocation: useMobileCards
              ? FloatingActionButtonLocation.centerFloat
              : FloatingActionButtonLocation.endFloat,
          floatingActionButton: _selectedDestination == 0
              ? FloatingActionButton.extended(
                  onPressed: _createNote,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(strings.newNote),
                )
              : null,
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    List<_HubDestination> destinations,
    AppStrings strings, {
    required bool showDesktopActions,
  }) {
    final destination = destinations[_selectedDestination];
    final colors = Theme.of(context).colorScheme;

    return AppBar(
      titleSpacing: 18,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.auto_awesome_mosaic_rounded,
              size: 20,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 11),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.appName),
                Text(
                  destination.label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: showDesktopActions
          ? [
              IconButton(
                tooltip: strings.syncDetails,
                onPressed: widget.onOpenSyncDetails,
                icon: const Icon(Icons.cloud_outlined),
              ),
              IconButton(
                tooltip: strings.synchronizeTooltip,
                onPressed: _isSynchronizing ? null : _syncNotes,
                icon: _isSynchronizing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync_outlined),
              ),
              IconButton(
                tooltip: strings.settings,
                onPressed: widget.onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 8),
            ]
          : null,
    );
  }

  Widget _buildMobileDrawer(
    List<_HubDestination> destinations,
    AppStrings strings,
  ) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Text(
                strings.appName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            for (var index = 0; index < destinations.length; index++)
              ListTile(
                selected: _selectedDestination == index,
                leading: Icon(
                  _selectedDestination == index
                      ? destinations[index].selectedIcon
                      : destinations[index].icon,
                ),
                title: Text(destinations[index].label),
                onTap: () {
                  Navigator.of(context).pop();
                  _selectDestination(index);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: Text(strings.syncDetails),
              onTap: () =>
                  unawaited(_openAfterClosingDrawer(widget.onOpenSyncDetails)),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(strings.settings),
              onTap: () =>
                  unawaited(_openAfterClosingDrawer(widget.onOpenSettings)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAfterClosingDrawer(VoidCallback action) async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted) action();
  }

  Widget _buildRail(List<_HubDestination> destinations, AppStrings strings) {
    return NavigationRail(
      selectedIndex: _selectedDestination,
      onDestinationSelected: _selectDestination,
      labelType: NavigationRailLabelType.all,
      groupAlignment: -0.72,
      leading: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: FloatingActionButton.small(
          tooltip: strings.newNote,
          onPressed: _createNote,
          child: const Icon(Icons.add),
        ),
      ),
      destinations: [
        for (final destination in destinations)
          NavigationRailDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: Text(destination.label),
          ),
      ],
    );
  }

  Widget _buildBottomNavigation(List<_HubDestination> destinations) {
    return NavigationBar(
      selectedIndex: _selectedDestination,
      onDestinationSelected: _selectDestination,
      destinations: [
        for (final destination in destinations)
          NavigationDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: destination.label,
          ),
      ],
    );
  }

  void _selectDestination(int index) {
    setState(() {
      _selectedDestination = index;
      if (index == 2) {
        _activityRevision++;
      }
    });
  }

  Widget _buildWorkspace(bool isDesktop, bool useMobileCards) {
    final strings = AppStrings.of(context);
    return StreamBuilder<WorkspaceStateDocument>(
      stream: _workspaceStream,
      builder: (context, workspaceSnapshot) {
        if (!workspaceSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final state = workspaceSnapshot.data!;
        final workspace = state.activeWorkspace;

        return Column(
          children: [
            _WorkspaceToolbar(
              controller: _workspaceSearch,
              compact: useMobileCards,
              state: state,
              scale: _canvasScale,
              sort: _workspaceSort,
              filter: _workspaceFilter,
              onSortChanged: (value) {
                setState(() => _workspaceSort = value);
              },
              onFilterChanged: (value) {
                setState(() => _workspaceFilter = value);
              },
              onWorkspaceChanged: (id) {
                unawaited(widget.workspaceStore.selectWorkspace(id));
              },
              onCreateWorkspace: _createWorkspace,
              onRenameWorkspace: () => _renameWorkspace(workspace),
              onDeleteWorkspace: () => _deleteWorkspace(state),
              onAddExistingNote: _addExistingNote,
              onManageLinks: () => _manageLinks(state),
              onZoomOut: () =>
                  _canvasKey.currentState?.zoomFromCenter(1 / 1.12),
              onZoomIn: () => _canvasKey.currentState?.zoomFromCenter(1.12),
              onReset: () => _canvasKey.currentState?.resetView(),
            ),
            Expanded(
              child: StreamBuilder<List<LocalNote>>(
                stream: _notesStream,
                builder: (context, notesSnapshot) {
                  if (notesSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (notesSnapshot.hasError) {
                    return _ErrorState(error: notesSnapshot.error);
                  }

                  final allNotes = notesSnapshot.data ?? const <LocalNote>[];
                  _latestAllNotes = allNotes;
                  final workspaceNoteIds = state
                      .placementsFor(workspace.id)
                      .map((placement) => placement.noteId)
                      .toSet();
                  final workspaceNotes = allNotes
                      .where((note) => workspaceNoteIds.contains(note.id))
                      .toList(growable: false);
                  final pinnedNoteIds = state
                      .placementsFor(workspace.id)
                      .where((placement) => placement.pinned)
                      .map((placement) => placement.noteId)
                      .toSet();
                  final visibleNotes = organizeWorkspaceNotes(
                    workspaceNotes.where(
                      (note) => _matches(note, _workspaceSearch.text),
                    ),
                    sort: _workspaceSort,
                    filter: _workspaceFilter,
                    pinnedNoteIds: pinnedNoteIds,
                  );

                  if (allNotes.isEmpty) {
                    return _EmptyWorkspace(
                      title: strings.buildWorkspace,
                      message: strings.createFirstNoteMessage,
                      primaryLabel: strings.createFirstNote,
                      onPrimary: _createNote,
                    );
                  }
                  if (workspaceNotes.isEmpty) {
                    return _EmptyWorkspace(
                      title: strings.workspaceEmptyTitle(workspace.name),
                      message: strings.workspaceEmptyMessage,
                      primaryLabel: strings.createNote,
                      onPrimary: _createNote,
                      secondaryLabel: strings.addExistingNote,
                      onSecondary: _addExistingNote,
                    );
                  }
                  if (visibleNotes.isEmpty) {
                    return _NoResults(message: strings.noSearchResults);
                  }

                  if (useMobileCards) {
                    return _MobileWorkspaceCards(
                      notes: visibleNotes,
                      onEdit: _editNote,
                      onDelete: _moveToTrash,
                      onDuplicate: _duplicateNote,
                      onConnect: _connectNote,
                      pinnedNoteIds: pinnedNoteIds,
                      onTogglePinned: (note) => _togglePinnedNote(note, state),
                      onAddToWorkspace: _showNoteInAnotherWorkspace,
                      onRemoveFromWorkspace: _removeNoteFromWorkspace,
                    );
                  }

                  return StableWorkspaceCanvas(
                    key: _canvasKey,
                    workspace: workspace,
                    notes: visibleNotes,
                    placements: state.placementsFor(workspace.id),
                    links: state.linksFor(workspace.id),
                    onEdit: _editNote,
                    onDelete: _moveToTrash,
                    onDuplicate: _duplicateNote,
                    onConnect: _connectNote,
                    onShowConnections: (note) =>
                        _showConnectedNotes(note, state),
                    onTogglePinned: (note) => _togglePinnedNote(note, state),
                    onAddToWorkspace: _showNoteInAnotherWorkspace,
                    onRemoveFromWorkspace: _removeNoteFromWorkspace,
                    onLayoutChanged: (placement) {
                      unawaited(
                        widget.workspaceStore.updatePlacement(placement),
                      );
                    },
                    onViewChanged: (x, y, scale) {
                      unawaited(
                        widget.workspaceStore.setWorkspaceCamera(
                          workspaceId: workspace.id,
                          translationX: x,
                          translationY: y,
                          scale: scale,
                        ),
                      );
                    },
                    onScaleChanged: (value) {
                      if (mounted && (value - _canvasScale).abs() >= 0.01) {
                        setState(() => _canvasScale = value);
                      }
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

  Widget _buildTrash() {
    final strings = AppStrings.of(context);
    return StreamBuilder<List<LocalNote>>(
      stream: _trashStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState(error: snapshot.error);
        }

        final allNotes = snapshot.data ?? const <LocalNote>[];
        final notes = allNotes
            .where((note) => _matches(note, _trashSearch.text))
            .toList(growable: false);

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SearchField(
                      controller: _trashSearch,
                      hintText: strings.searchTrash,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.restore_from_trash_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                strings.deletedNotesSummary(allNotes.length),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (notes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(strings.trashEmpty)),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                sliver: SliverGrid.builder(
                  itemCount: notes.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 430,
                    mainAxisExtent: 220,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    return _TrashCard(
                      note: note,
                      daysRemaining: widget.repository.trashDaysRemaining(note),
                      onRestore: () => _restoreNote(note),
                      onDeleteForever: () => _deleteForever(note),
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
    return _ActivityView(
      key: ValueKey(_activityRevision),
      repository: widget.repository,
      workspaceStore: widget.workspaceStore,
      onSync: _isSynchronizing ? null : _syncNotes,
    );
  }
}

class _WorkspaceToolbar extends StatelessWidget {
  const _WorkspaceToolbar({
    required this.controller,
    required this.compact,
    required this.state,
    required this.scale,
    required this.sort,
    required this.filter,
    required this.onSortChanged,
    required this.onFilterChanged,
    required this.onWorkspaceChanged,
    required this.onCreateWorkspace,
    required this.onRenameWorkspace,
    required this.onDeleteWorkspace,
    required this.onAddExistingNote,
    required this.onManageLinks,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onReset,
  });

  final TextEditingController controller;
  final bool compact;
  final WorkspaceStateDocument state;
  final double scale;
  final WorkspaceNoteSort sort;
  final WorkspaceNoteFilter filter;
  final ValueChanged<WorkspaceNoteSort> onSortChanged;
  final ValueChanged<WorkspaceNoteFilter> onFilterChanged;
  final ValueChanged<String> onWorkspaceChanged;
  final VoidCallback onCreateWorkspace;
  final VoidCallback onRenameWorkspace;
  final VoidCallback onDeleteWorkspace;
  final VoidCallback onAddExistingNote;
  final VoidCallback onManageLinks;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final workspace = state.activeWorkspace;
    final workspaceSelector = Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: workspace.id,
          items: [
            for (final item in state.workspaces)
              DropdownMenuItem(
                value: item.id,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 6,
                      backgroundColor: Color(item.colorValue),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              onWorkspaceChanged(value);
            }
          },
        ),
      ),
    );

    final sortMenu = PopupMenuButton<WorkspaceNoteSort>(
      tooltip: strings.sortNotes,
      initialValue: sort,
      onSelected: onSortChanged,
      icon: const Icon(Icons.sort_rounded),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: WorkspaceNoteSort.recentlyUpdated,
          checked: sort == WorkspaceNoteSort.recentlyUpdated,
          child: Text(strings.sortRecentlyUpdated),
        ),
        CheckedPopupMenuItem(
          value: WorkspaceNoteSort.oldestUpdated,
          checked: sort == WorkspaceNoteSort.oldestUpdated,
          child: Text(strings.sortOldestUpdated),
        ),
        CheckedPopupMenuItem(
          value: WorkspaceNoteSort.titleAscending,
          checked: sort == WorkspaceNoteSort.titleAscending,
          child: Text(strings.sortTitleAscending),
        ),
        CheckedPopupMenuItem(
          value: WorkspaceNoteSort.titleDescending,
          checked: sort == WorkspaceNoteSort.titleDescending,
          child: Text(strings.sortTitleDescending),
        ),
      ],
    );

    final filterMenu = PopupMenuButton<WorkspaceNoteFilter>(
      tooltip: strings.filterNotes,
      initialValue: filter,
      onSelected: onFilterChanged,
      icon: Icon(
        filter == WorkspaceNoteFilter.all
            ? Icons.filter_alt_outlined
            : Icons.filter_alt_rounded,
      ),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: WorkspaceNoteFilter.all,
          checked: filter == WorkspaceNoteFilter.all,
          child: Text(strings.filterAllNotes),
        ),
        CheckedPopupMenuItem(
          value: WorkspaceNoteFilter.taskNotes,
          checked: filter == WorkspaceNoteFilter.taskNotes,
          child: Text(strings.filterTaskNotes),
        ),
        CheckedPopupMenuItem(
          value: WorkspaceNoteFilter.incompleteTasks,
          checked: filter == WorkspaceNoteFilter.incompleteTasks,
          child: Text(strings.filterIncompleteTasks),
        ),
        CheckedPopupMenuItem(
          value: WorkspaceNoteFilter.completedTasks,
          checked: filter == WorkspaceNoteFilter.completedTasks,
          child: Text(strings.filterCompletedTasks),
        ),
      ],
    );

    final workspaceMenu = PopupMenuButton<_WorkspaceAction>(
      tooltip: strings.workspaceOptions,
      onSelected: (action) {
        switch (action) {
          case _WorkspaceAction.rename:
            onRenameWorkspace();
          case _WorkspaceAction.delete:
            onDeleteWorkspace();
          case _WorkspaceAction.addExisting:
            onAddExistingNote();
          case _WorkspaceAction.connections:
            onManageLinks();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _WorkspaceAction.addExisting,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.playlist_add_rounded),
            title: Text(strings.addExistingNote),
          ),
        ),
        PopupMenuItem(
          value: _WorkspaceAction.connections,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.polyline_outlined),
            title: Text(strings.manageConnections),
          ),
        ),
        PopupMenuItem(
          value: _WorkspaceAction.rename,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined),
            title: Text(strings.renameWorkspace),
          ),
        ),
        PopupMenuItem(
          value: _WorkspaceAction.delete,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_delete_outlined),
            title: Text(strings.deleteWorkspace),
          ),
        ),
      ],
    );

    final desktopCanvasActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        filterMenu,
        const SizedBox(width: 4),
        IconButton(
          tooltip: strings.addExistingNote,
          onPressed: onAddExistingNote,
          icon: const Icon(Icons.playlist_add_rounded),
        ),
        IconButton(
          tooltip: strings.manageConnections,
          onPressed: onManageLinks,
          icon: const Icon(Icons.polyline_outlined),
        ),
        IconButton(
          tooltip: strings.zoomOut,
          onPressed: onZoomOut,
          icon: const Icon(Icons.remove),
        ),
        Text('${(scale * 100).round()}%'),
        IconButton(
          tooltip: strings.zoomIn,
          onPressed: onZoomIn,
          icon: const Icon(Icons.add),
        ),
        IconButton(
          tooltip: strings.fitNotes,
          onPressed: onReset,
          icon: const Icon(Icons.center_focus_strong_outlined),
        ),
      ],
    );

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: compact
            ? Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: workspaceSelector),
                      IconButton(
                        tooltip: strings.createWorkspace,
                        onPressed: onCreateWorkspace,
                        icon: const Icon(Icons.create_new_folder_outlined),
                      ),
                      workspaceMenu,
                    ],
                  ),
                  const SizedBox(height: 8),
                  _SearchField(
                    controller: controller,
                    hintText: strings.searchWorkspace,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [sortMenu, filterMenu],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.view_agenda_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.mobileCardsExplanation,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final useTwoRows = constraints.maxWidth < 900;

                  if (!useTwoRows) {
                    return Row(
                      children: [
                        workspaceSelector,
                        IconButton(
                          tooltip: strings.createWorkspace,
                          onPressed: onCreateWorkspace,
                          icon: const Icon(Icons.create_new_folder_outlined),
                        ),
                        workspaceMenu,
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SearchField(
                            controller: controller,
                            hintText: strings.searchWorkspace,
                          ),
                        ),
                        const SizedBox(width: 8),
                        desktopCanvasActions,
                      ],
                    );
                  }

                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: workspaceSelector),
                          IconButton(
                            tooltip: strings.createWorkspace,
                            onPressed: onCreateWorkspace,
                            icon: const Icon(Icons.create_new_folder_outlined),
                          ),
                          workspaceMenu,
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _SearchField(
                              controller: controller,
                              hintText: strings.searchWorkspace,
                            ),
                          ),
                          const SizedBox(width: 8),
                          desktopCanvasActions,
                        ],
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.hintText});

  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: strings.clearSearch,
                onPressed: controller.clear,
                icon: const Icon(Icons.close),
              ),
      ),
    );
  }
}

class _MobileWorkspaceCards extends StatelessWidget {
  const _MobileWorkspaceCards({
    required this.notes,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onConnect,
    required this.onAddToWorkspace,
    required this.onRemoveFromWorkspace,
    required this.pinnedNoteIds,
    required this.onTogglePinned,
  });

  final List<LocalNote> notes;
  final ValueChanged<LocalNote> onEdit;
  final ValueChanged<LocalNote> onDelete;
  final ValueChanged<LocalNote> onDuplicate;
  final ValueChanged<LocalNote> onConnect;
  final ValueChanged<LocalNote> onAddToWorkspace;
  final ValueChanged<LocalNote> onRemoveFromWorkspace;
  final Set<String> pinnedNoteIds;
  final ValueChanged<LocalNote> onTogglePinned;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
      itemCount: notes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final note = notes[index];
        return _MobileNoteCard(
          note: note,
          isPinned: pinnedNoteIds.contains(note.id),
          onEdit: () => onEdit(note),
          onDelete: () => onDelete(note),
          onDuplicate: () => onDuplicate(note),
          onConnect: () => onConnect(note),
          onAddToWorkspace: () => onAddToWorkspace(note),
          onRemoveFromWorkspace: () => onRemoveFromWorkspace(note),
          onTogglePinned: () => onTogglePinned(note),
        );
      },
    );
  }
}

class _MobileNoteCard extends StatelessWidget {
  const _MobileNoteCard({
    required this.note,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onConnect,
    required this.onAddToWorkspace,
    required this.onRemoveFromWorkspace,
    required this.isPinned,
    required this.onTogglePinned,
  });

  final LocalNote note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onConnect;
  final VoidCallback onAddToWorkspace;
  final VoidCallback onRemoveFromWorkspace;
  final bool isPinned;
  final VoidCallback onTogglePinned;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final pending = note.syncStatus == 'pending';
    final preview = note.content.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.note_alt_outlined,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isPinned)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message: strings.pinnedNote,
                        child: Icon(
                          Icons.push_pin_rounded,
                          size: 17,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  PopupMenuButton<_MobileNoteAction>(
                    tooltip: strings.noteOptions,
                    onSelected: (action) {
                      switch (action) {
                        case _MobileNoteAction.edit:
                          onEdit();
                        case _MobileNoteAction.duplicate:
                          onDuplicate();
                        case _MobileNoteAction.connect:
                          onConnect();
                        case _MobileNoteAction.pin:
                          onTogglePinned();
                        case _MobileNoteAction.addToWorkspace:
                          onAddToWorkspace();
                        case _MobileNoteAction.removeFromWorkspace:
                          onRemoveFromWorkspace();
                        case _MobileNoteAction.delete:
                          onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      _mobileMenuItem(
                        _MobileNoteAction.edit,
                        Icons.edit_outlined,
                        strings.editNote,
                      ),
                      _mobileMenuItem(
                        _MobileNoteAction.duplicate,
                        Icons.copy_all_outlined,
                        strings.duplicateNote,
                      ),
                      _mobileMenuItem(
                        _MobileNoteAction.connect,
                        Icons.polyline_outlined,
                        strings.connectToNote,
                      ),
                      _mobileMenuItem(
                        _MobileNoteAction.pin,
                        isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                        isPinned ? strings.unpinNote : strings.pinNote,
                      ),
                      _mobileMenuItem(
                        _MobileNoteAction.addToWorkspace,
                        Icons.drive_file_move_outline,
                        strings.showInAnotherWorkspace,
                      ),
                      _mobileMenuItem(
                        _MobileNoteAction.removeFromWorkspace,
                        Icons.remove_circle_outline,
                        strings.removeFromThisWorkspace,
                      ),
                      const PopupMenuDivider(),
                      _mobileMenuItem(
                        _MobileNoteAction.delete,
                        Icons.delete_outline,
                        strings.moveToTrash,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (preview.isEmpty)
                Text(
                  strings.tapToStartWriting,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    color: colors.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                NoteMarkdown(data: preview),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    pending
                        ? Icons.cloud_upload_outlined
                        : Icons.cloud_done_outlined,
                    size: 16,
                    color: pending ? colors.tertiary : colors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    pending ? strings.pending : strings.synced,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const Spacer(),
                  Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(note.updatedAt.toLocal()),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<_MobileNoteAction> _mobileMenuItem(
    _MobileNoteAction value,
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
}

class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace({
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 400;
        final padding = compact ? 16.0 : 32.0;
        final iconSize = compact ? 48.0 : 72.0;
        final iconGap = compact ? 10.0 : 20.0;
        final titleGap = compact ? 6.0 : 10.0;
        final actionsGap = compact ? 12.0 : 22.0;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dashboard_customize_outlined, size: iconSize),
                  SizedBox(height: iconGap),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: titleGap),
                  Text(message, textAlign: TextAlign.center),
                  SizedBox(height: actionsGap),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: onPrimary,
                        icon: const Icon(Icons.add),
                        label: Text(primaryLabel),
                      ),
                      if (secondaryLabel != null && onSecondary != null)
                        OutlinedButton.icon(
                          onPressed: onSecondary,
                          icon: const Icon(Icons.playlist_add),
                          label: Text(secondaryLabel!),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, size: 54),
          const SizedBox(height: 12),
          Text(message),
        ],
      ),
    );
  }
}

class _TrashCard extends StatelessWidget {
  const _TrashCard({
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
    final strings = AppStrings.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              note.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: note.content.trim().isEmpty
                  ? const SizedBox.shrink()
                  : ClipRect(
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: IgnorePointer(
                          child: NoteMarkdown(data: note.content.trim()),
                        ),
                      ),
                    ),
            ),
            Text(strings.daysRemaining(daysRemaining)),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore),
                  label: Text(strings.restore),
                ),
                const Spacer(),
                IconButton(
                  tooltip: strings.deletePermanently,
                  onPressed: onDeleteForever,
                  icon: const Icon(Icons.delete_forever_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityView extends StatelessWidget {
  const _ActivityView({
    super.key,
    required this.repository,
    required this.workspaceStore,
    required this.onSync,
  });

  final LocalNotesRepository repository;
  final WorkspaceStateStore workspaceStore;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<
      (List<PendingOperationDetails>, WorkspaceLocalSnapshot)
    >(
      future: _load(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final operations = snapshot.data!.$1;
        final workspace = snapshot.data!.$2;
        final pendingCount = operations.length + (workspace.isPending ? 1 : 0);

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      pendingCount == 0
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_upload_outlined,
                      size: 36,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        pendingCount == 0
                            ? strings.everythingSynchronized
                            : strings.pendingChangeCount(pendingCount),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: onSync,
                      icon: const Icon(Icons.sync),
                      label: Text(strings.syncNow),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (workspace.isPending)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.space_dashboard_outlined),
                  title: Text(strings.workspaceChanges),
                  subtitle: Text(strings.queued),
                ),
              ),
            if (operations.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(strings.noPendingNoteOperations),
                ),
              )
            else
              for (final detail in operations)
                _PendingOperationTile(detail: detail),
          ],
        );
      },
    );
  }

  Future<(List<PendingOperationDetails>, WorkspaceLocalSnapshot)>
  _load() async {
    final workspace = await workspaceStore.localSnapshot();
    final operations = await repository.getPendingOperationDetails(
      workspace.state,
    );
    return (operations, workspace);
  }
}

class _PendingOperationTile extends StatelessWidget {
  const _PendingOperationTile({required this.detail});

  final PendingOperationDetails detail;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final operation = detail.operation;
    final action = switch (operation.operation) {
      'create' => strings.createdNote,
      'update' => strings.editedNote,
      'delete' => strings.deletedNote,
      _ => operation.operation,
    };

    return Card(
      child: ListTile(
        leading: Icon(switch (operation.operation) {
          'create' => Icons.note_add_outlined,
          'update' => Icons.edit_note_outlined,
          'delete' => Icons.delete_outline,
          _ => Icons.pending_actions_outlined,
        }),
        title: Text('$action · ${detail.title}'),
        subtitle: Text(
          [
            if (detail.workspaceNames.isNotEmpty)
              '${strings.workspaces}: ${detail.workspaceNames.join(', ')}',
            if (detail.contentPreview.isNotEmpty) detail.contentPreview,
            '${strings.queued}: ${operation.createdAt.toLocal()}',
            if (operation.retryCount > 0)
              '${strings.retry}: ${operation.retryCount}',
            if (operation.lastError?.trim().isNotEmpty == true)
              operation.lastError!,
          ].join('\n'),
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _CreateLinkDialog extends StatefulWidget {
  const _CreateLinkDialog({required this.source, required this.candidates});

  final LocalNote source;
  final List<LocalNote> candidates;

  @override
  State<_CreateLinkDialog> createState() => _CreateLinkDialogState();
}

class _CreateLinkDialogState extends State<_CreateLinkDialog> {
  static const _colors = <int>[
    0xFF625BEB,
    0xFF006C4C,
    0xFF0061A4,
    0xFF9C4146,
    0xFF825500,
  ];

  late String _targetId;
  final TextEditingController _label = TextEditingController();
  int _color = _colors.first;
  bool _directed = true;
  bool _taskProgression = false;

  @override
  void initState() {
    super.initState();
    _targetId = widget.candidates.first.id;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      icon: const Icon(Icons.polyline_outlined),
      title: Text(strings.createConnection),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _targetId,
              decoration: InputDecoration(labelText: strings.targetNote),
              items: [
                for (final note in widget.candidates)
                  DropdownMenuItem(value: note.id, child: Text(note.title)),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _targetId = value);
                }
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.nextTaskProgression),
              subtitle: Text(strings.nextTaskProgressionHint),
              value: _taskProgression,
              onChanged: (value) {
                setState(() {
                  _taskProgression = value;

                  if (value) {
                    _label.text = taskProgressionLinkLabel;
                    _directed = true;
                  } else if (_label.text.trim().toLowerCase() ==
                      taskProgressionLinkLabel.toLowerCase()) {
                    _label.clear();
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              enabled: !_taskProgression,
              decoration: InputDecoration(labelText: strings.connectionLabel),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.directedConnection),
              value: _directed,
              onChanged: _taskProgression
                  ? null
                  : (value) => setState(() => _directed = value),
            ),
            Wrap(
              spacing: 10,
              children: [
                for (final color in _colors)
                  ChoiceChip(
                    label: CircleAvatar(
                      radius: 9,
                      backgroundColor: Color(color),
                    ),
                    selected: color == _color,
                    onSelected: (_) => setState(() => _color = color),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _LinkDraft(
              targetNoteId: _targetId,
              colorValue: _color,
              label: _taskProgression
                  ? taskProgressionLinkLabel
                  : _label.text.trim(),
              directed: _taskProgression ? true : _directed,
            ),
          ),
          child: Text(strings.create),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('${strings.failed}: $error', textAlign: TextAlign.center),
      ),
    );
  }
}

class _HubDestination {
  const _HubDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _LinkDraft {
  const _LinkDraft({
    required this.targetNoteId,
    required this.colorValue,
    required this.label,
    required this.directed,
  });

  final String targetNoteId;
  final int colorValue;
  final String label;
  final bool directed;
}

enum _WorkspaceAction { rename, delete, addExisting, connections }

enum _MobileNoteAction {
  edit,
  duplicate,
  connect,
  pin,
  addToWorkspace,
  removeFromWorkspace,
  delete,
}
