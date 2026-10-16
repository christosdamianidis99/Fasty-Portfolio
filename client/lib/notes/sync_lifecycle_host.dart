import 'dart:async';

import 'package:flutter/material.dart';

import 'notes_sync_service.dart';

class SyncLifecycleHost extends StatefulWidget {
  const SyncLifecycleHost({
    super.key,
    required this.syncService,
    required this.child,
    this.interval = const Duration(seconds: 30),
  });

  final NotesSyncService syncService;
  final Widget child;
  final Duration interval;

  @override
  State<SyncLifecycleHost> createState() => _SyncLifecycleHostState();
}

class _SyncLifecycleHostState extends State<SyncLifecycleHost>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_sync());
    });
    _timer = Timer.periodic(widget.interval, (_) => unawaited(_sync()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_sync());
    }
  }

  Future<void> _sync() async {
    try {
      await widget.syncService.syncPendingOperations(forceRetry: false);
    } catch (_) {
      // Background synchronization is deliberately quiet. Pending operations
      // and their actionable errors remain available in Sync Activity, while a
      // manual sync still surfaces failures through the existing UI.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
