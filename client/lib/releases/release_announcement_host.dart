import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'release_announcement.dart';
import 'release_announcement_controller.dart';

typedef ExternalReleaseLinkLauncher = Future<bool> Function(Uri uri);

class ReleaseAnnouncementHost extends StatefulWidget {
  const ReleaseAnnouncementHost({
    super.key,
    required this.controller,
    required this.child,
    this.externalLinkLauncher,
  });

  final ReleaseAnnouncementController controller;
  final Widget child;
  final ExternalReleaseLinkLauncher? externalLinkLauncher;

  @override
  State<ReleaseAnnouncementHost> createState() =>
      _ReleaseAnnouncementHostState();
}

class _ReleaseAnnouncementHostState extends State<ReleaseAnnouncementHost> {
  bool _checkStarted = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForAnnouncement());
    });
  }

  Future<void> _checkForAnnouncement() async {
    if (_checkStarted || !mounted) {
      return;
    }

    _checkStarted = true;

    ReleaseAnnouncement? announcement;

    try {
      announcement = await widget.controller.loadPending();
    } catch (_) {
      // Release announcements must never block access to the app.
      return;
    }

    if (!mounted || announcement == null) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          key: const ValueKey('release-announcement-dialog'),
          icon: const Icon(Icons.new_releases_outlined),
          title: Text(
            announcement!.title,
            key: const ValueKey('release-announcement-title'),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              announcement.message,
              key: const ValueKey('release-announcement-message'),
            ),
          ),
          actions: [
            if (announcement.contactUrl != null)
              TextButton.icon(
                key: const ValueKey('contact-release-announcement'),
                onPressed: () {
                  unawaited(_openContact(announcement!.contactUrl!));
                },
                icon: const Icon(Icons.contact_support_outlined),
                label: const Text('Contact Christos'),
              ),
            FilledButton(
              key: const ValueKey('acknowledge-release-announcement'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );

    try {
      await widget.controller.acknowledge(announcement);
    } catch (_) {
      // A local persistence failure should not interrupt the signed-in app.
    }
  }

  Future<void> _openContact(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);

    if (uri == null || !uri.hasScheme) {
      return;
    }

    final launcher =
        widget.externalLinkLauncher ?? _defaultExternalLinkLauncher;

    try {
      await launcher(uri);
    } catch (_) {
      // Contact links are optional and must never block app usage.
    }
  }

  static Future<bool> _defaultExternalLinkLauncher(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
