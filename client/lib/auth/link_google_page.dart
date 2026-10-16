import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'google_identity_service.dart';

class LinkGooglePage extends StatefulWidget {
  const LinkGooglePage({
    super.key,
    required this.controller,
    this.googleIdentityService,
  });

  final AuthController controller;
  final GoogleIdentityService? googleIdentityService;

  @override
  State<LinkGooglePage> createState() => _LinkGooglePageState();
}

class _LinkGooglePageState extends State<LinkGooglePage> {
  bool _googleBusy = false;
  String? _googleError;

  GoogleIdentityService get _googleIdentityService =>
      widget.googleIdentityService ?? DefaultGoogleIdentityService.instance;

  Future<void> _link() async {
    setState(() {
      _googleBusy = true;
      _googleError = null;
    });
    widget.controller.clearFeedback();

    try {
      final idToken = await _googleIdentityService.acquireIdToken();
      if (idToken == null) return;
      final linked = await widget.controller.linkGoogle(idToken: idToken);
      if (!linked || !mounted) return;
      final signOut = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Google account linked'),
          content: const Text(
            'Would you like to sign out now and sign in with Google?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay signed in'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign out'),
            ),
          ],
        ),
      );
      if (signOut == true && mounted) {
        Navigator.of(context).pop();
        await widget.controller.logout();
      }
    } on Object catch (error) {
      if (mounted) setState(() => _googleError = error.toString());
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Link Google account')),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Connect a Google account with the same email address as '
              '${widget.controller.email ?? 'your Fasty account'}.',
            ),
            const SizedBox(height: 16),
            Text(
              'Your notes and workspaces stay in your current Fasty account.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (widget.controller.errorMessage != null ||
                _googleError != null) ...[
              const SizedBox(height: 16),
              Text(
                _googleError ?? widget.controller.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (widget.controller.message != null) ...[
              const SizedBox(height: 16),
              Text(widget.controller.message!),
            ],
            const SizedBox(height: 24),
            if (widget.controller.googleLinked != true)
              FilledButton.icon(
                key: const ValueKey('link-google-button'),
                onPressed:
                    widget.controller.isBusy ||
                        _googleBusy ||
                        !_googleIdentityService.isAvailable
                    ? null
                    : _link,
                icon: const Icon(Icons.account_circle_outlined),
                label: Text(
                  _googleBusy ? 'Opening Google sign-in…' : 'Link Google',
                ),
              ),
            if (!_googleIdentityService.isAvailable) ...[
              const SizedBox(height: 8),
              Text(
                _googleIdentityService.unavailableReason ??
                    'Google sign-in is unavailable.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
