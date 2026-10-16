enum SyncState { idle, syncing, synchronized, unavailable, failed }

class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.state,
    required this.message,
    required this.occurredAt,
    this.successfulOperations = 0,
    this.pendingOperations = 0,
    this.failureMessages = const [],
  });

  const SyncStatusSnapshot.idle()
    : state = SyncState.idle,
      message = 'Synchronization has not run yet.',
      occurredAt = null,
      successfulOperations = 0,
      pendingOperations = 0,
      failureMessages = const [];

  final SyncState state;
  final String message;
  final DateTime? occurredAt;
  final int successfulOperations;
  final int pendingOperations;
  final List<String> failureMessages;

  bool get hasProblem =>
      state == SyncState.unavailable || state == SyncState.failed;
}
