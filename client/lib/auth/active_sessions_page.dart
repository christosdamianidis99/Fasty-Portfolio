import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'refresh_session_info.dart';

class ActiveSessionsPage extends StatefulWidget {
  const ActiveSessionsPage({super.key, required this.controller});

  final AuthController controller;

  @override
  State<ActiveSessionsPage> createState() => _ActiveSessionsPageState();
}

class _ActiveSessionsPageState extends State<ActiveSessionsPage> {
  List<RefreshSessionInfo>? _sessions;
  String? _loadError;
  String? _revokingSessionId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    final sessions = await widget.controller.listSessions();

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;

      if (sessions == null) {
        _loadError =
            widget.controller.errorMessage ?? 'Could not load active sessions.';
        return;
      }

      _sessions = sessions;
    });
  }

  Future<void> _confirmAndRevoke(RefreshSessionInfo session) async {
    final isCurrent = session.id == widget.controller.session?.refreshSessionId;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(
                isCurrent
                    ? 'Sign out this device?'
                    : 'Sign out this device session?',
              ),
              content: Text(
                isCurrent
                    ? 'You will be returned to the sign-in screen.'
                    : 'The device "${session.deviceName}" '
                          'will need to sign in again.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const ValueKey('confirm-session-revocation'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('Sign out'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _revokingSessionId = session.id;
    });

    final succeeded = await widget.controller.revokeSession(session.id);

    if (!mounted) {
      return;
    }

    if (!succeeded) {
      setState(() {
        _revokingSessionId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.errorMessage ?? 'Could not sign out the device.',
          ),
        ),
      );

      return;
    }

    if (isCurrent) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    setState(() {
      _revokingSessionId = null;
      _sessions = _sessions
          ?.where((candidate) => candidate.id != session.id)
          .toList(growable: false);
    });
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();

    final day = local.day.toString().padLeft(2, '0');

    final month = local.month.toString().padLeft(2, '0');

    final hour = local.hour.toString().padLeft(2, '0');

    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/${local.year} $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active sessions'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: widget.controller.isBusy
              ? null
              : () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            key: const ValueKey('refresh-active-sessions'),
            tooltip: 'Refresh',
            onPressed: _loading || widget.controller.isBusy
                ? null
                : _loadSessions,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          if (_loading) {
            return const Center(
              child: CircularProgressIndicator(
                key: ValueKey('active-sessions-loading'),
              ),
            );
          }

          if (_loadError != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 48),
                          const SizedBox(height: 16),
                          Text(_loadError!, textAlign: TextAlign.center),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            key: const ValueKey('retry-active-sessions'),
                            onPressed: widget.controller.isBusy
                                ? null
                                : _loadSessions,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          final sessions = _sessions ?? const <RefreshSessionInfo>[];

          if (sessions.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No active sessions were found.',
                  key: ValueKey('active-sessions-empty'),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Text(
                'Devices signed in to your account',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Sign out devices you no longer '
                'recognize or use.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              for (final session in sessions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SessionCard(
                    key: ValueKey('active-session-${session.id}'),
                    session: session,
                    isCurrent:
                        session.id ==
                        widget.controller.session?.refreshSessionId,
                    isRevoking: _revokingSessionId == session.id,
                    actionsDisabled:
                        widget.controller.isBusy || _revokingSessionId != null,
                    formatDateTime: _formatDateTime,
                    onRevoke: () => _confirmAndRevoke(session),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    super.key,
    required this.session,
    required this.isCurrent,
    required this.isRevoking,
    required this.actionsDisabled,
    required this.formatDateTime,
    required this.onRevoke,
  });

  final RefreshSessionInfo session;
  final bool isCurrent;
  final bool isRevoking;
  final bool actionsDisabled;
  final String Function(DateTime value) formatDateTime;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final lastActive = session.lastUsedAt ?? session.createdAt;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Icon(
                    isCurrent ? Icons.devices_rounded : Icons.devices_outlined,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.deviceName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (isCurrent) ...[
                        const SizedBox(height: 6),
                        const Chip(
                          key: ValueKey('current-session-label'),
                          avatar: Icon(Icons.check_circle, size: 18),
                          label: Text('Current device'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Last active: '
              '${formatDateTime(lastActive)}',
            ),
            const SizedBox(height: 4),
            Text(
              'Expires: '
              '${formatDateTime(session.expiresAt)}',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: ValueKey('revoke-session-${session.id}'),
              onPressed: actionsDisabled || isRevoking ? null : onRevoke,
              icon: isRevoking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      isCurrent ? Icons.logout : Icons.phonelink_erase_outlined,
                    ),
              label: Text(
                isCurrent ? 'Sign out this device' : 'Sign out device',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
