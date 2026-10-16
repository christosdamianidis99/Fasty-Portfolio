import 'package:flutter/material.dart';

import 'auth/auth_controller.dart';

import 'notes/local_notes_repository.dart';
import 'notes/notes_hub_page.dart';
import 'notes/notes_sync_service.dart';
import 'notes/sync_lifecycle_host.dart';
import 'notes/sync_status.dart';
import 'notes/workspace_state_store.dart';
import 'releases/release_announcement_controller.dart';
import 'releases/release_announcement_host.dart';
import 'settings/app_settings_controller.dart';
import 'settings/app_strings.dart';
import 'settings/settings_page.dart';

class FastyAppShell extends StatelessWidget {
  const FastyAppShell({
    super.key,
    required this.repository,
    required this.syncService,
    required this.workspaceStore,
    required this.settings,
    this.authController,
    this.releaseAnnouncementController,
  });

  final LocalNotesRepository repository;
  final NotesSyncService syncService;
  final WorkspaceStateStore workspaceStore;
  final AppSettingsController settings;
  final AuthController? authController;
  final ReleaseAnnouncementController? releaseAnnouncementController;

  @override
  Widget build(BuildContext context) {
    final content = SyncLifecycleHost(
      syncService: syncService,
      child: NotesHubPage(
        repository: repository,
        syncService: syncService,
        workspaceStore: workspaceStore,
        onOpenSettings: () => _showSettings(context),
        onOpenSyncDetails: () => _showSyncDetails(context),
      ),
    );

    final releaseController = releaseAnnouncementController;

    if (releaseController == null) {
      return content;
    }

    return ReleaseAnnouncementHost(
      controller: releaseController,
      child: content,
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: SettingsPage(
          controller: settings,
          authController: authController,
        ),
      ),
    );
  }

  void _showSyncDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _SyncDetailsSheet(
          repository: repository,
          workspaceStore: workspaceStore,
          syncService: syncService,
        ),
      ),
    );
  }
}

class _SyncDetailsSheet extends StatefulWidget {
  const _SyncDetailsSheet({
    required this.repository,
    required this.workspaceStore,
    required this.syncService,
  });

  final LocalNotesRepository repository;
  final WorkspaceStateStore workspaceStore;
  final NotesSyncService syncService;

  @override
  State<_SyncDetailsSheet> createState() => _SyncDetailsSheetState();
}

class _SyncDetailsSheetState extends State<_SyncDetailsSheet> {
  late Future<_SyncDetailsData> _details;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _details = _load();
  }

  Future<_SyncDetailsData> _load() async {
    final workspace = await widget.workspaceStore.localSnapshot();
    final operations = await widget.repository.getPendingOperationDetails(
      workspace.state,
    );
    return _SyncDetailsData(
      operations: operations,
      workspacePending: workspace.isPending,
    );
  }

  Future<void> _syncNow() async {
    if (_syncing) {
      return;
    }
    setState(() => _syncing = true);
    try {
      await widget.syncService.syncPendingOperations();
    } catch (_) {
      // The observable status contains the complete failure message.
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _details = _load();
        });
      }
    }
  }

  String _localizedStatusMessage(
    AppStrings strings,
    SyncStatusSnapshot status,
  ) {
    return switch (status.state) {
      SyncState.idle => strings.notSyncedYet,
      SyncState.syncing => strings.syncingDescription,
      SyncState.synchronized =>
        status.successfulOperations == 0
            ? strings.syncCheckComplete
            : strings.synchronizedChanges(status.successfulOperations),
      SyncState.unavailable => strings.serverUnavailable,
      SyncState.failed =>
        status.failureMessages.isEmpty
            ? strings.failed
            : '${strings.failed}: ${status.failureMessages.first}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.sync_alt_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings.syncDetails,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: strings.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<SyncStatusSnapshot>(
            valueListenable: widget.syncService.status,
            builder: (context, status, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                child: ListTile(
                  leading: Icon(
                    status.hasProblem
                        ? Icons.warning_amber_rounded
                        : Icons.cloud_done_outlined,
                  ),
                  title: Text(strings.lastSyncResult),
                  subtitle: Text(_localizedStatusMessage(strings, status)),
                  trailing: status.occurredAt == null
                      ? null
                      : Text(_formatTime(status.occurredAt!.toLocal())),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _syncing ? null : _syncNow,
                icon: _syncing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(strings.syncNow),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<_SyncDetailsData>(
              future: _details,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final details = snapshot.data!;
                if (details.operations.isEmpty && !details.workspacePending) {
                  return Center(child: Text(strings.noPendingChanges));
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    Text(
                      strings.pendingChanges,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (details.workspacePending)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.space_dashboard_outlined),
                          title: Text(strings.workspaceChanges),
                          subtitle: Text(strings.queued),
                        ),
                      ),
                    for (final detail in details.operations)
                      _PendingOperationCard(detail: detail),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _PendingOperationCard extends StatelessWidget {
  const _PendingOperationCard({required this.detail});

  final PendingOperationDetails detail;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final operation = detail.operation;
    final actionLabel = switch (operation.operation) {
      'create' => strings.createdNote,
      'update' => strings.editedNote,
      'delete' => strings.deletedNote,
      _ => operation.operation,
    };
    final workspaceLabel = detail.workspaceNames.join(', ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_operationIcon(operation.operation)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(actionLabel),
                      Text(
                        detail.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (detail.contentPreview.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                detail.contentPreview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (workspaceLabel.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('${strings.workspaces}: $workspaceLabel'),
            ],
            const SizedBox(height: 8),
            Text('${strings.queued}: ${operation.createdAt.toLocal()}'),
            if (operation.retryCount > 0)
              Text('${strings.retry}: ${operation.retryCount}'),
            if (operation.lastError?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                operation.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _operationIcon(String operation) {
    return switch (operation) {
      'create' => Icons.note_add_outlined,
      'update' => Icons.edit_note_outlined,
      'delete' => Icons.delete_outline,
      _ => Icons.pending_actions_outlined,
    };
  }
}

class _SyncDetailsData {
  const _SyncDetailsData({
    required this.operations,
    required this.workspacePending,
  });

  final List<PendingOperationDetails> operations;
  final bool workspacePending;
}
