import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/active_sessions_page.dart';
import '../auth/auth_controller.dart';
import '../auth/change_password_page.dart';
import '../auth/link_google_page.dart';

import 'app_settings_controller.dart';
import 'app_strings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.authController,
  });

  static const _accentColors = <int>[
    0xFF625BEB,
    0xFF006C4C,
    0xFF0061A4,
    0xFF8C4A60,
    0xFF7D5700,
    0xFF6B5778,
  ];

  final AppSettingsController controller;
  final AuthController? authController;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Row(
                children: [
                  Icon(Icons.settings_outlined, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      strings.settings,
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
              const SizedBox(height: 18),
              _SectionCard(
                title: strings.appearance,
                icon: Icons.palette_outlined,
                children: [
                  Text(strings.theme),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: const Icon(Icons.brightness_auto_outlined),
                        label: Text(strings.systemTheme),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: const Icon(Icons.light_mode_outlined),
                        label: Text(strings.lightTheme),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: const Icon(Icons.dark_mode_outlined),
                        label: Text(strings.darkTheme),
                      ),
                    ],
                    selected: {controller.themeMode},
                    onSelectionChanged: (selection) {
                      unawaited(controller.setThemeMode(selection.first));
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(strings.accentColor),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final value in _accentColors)
                        _ColorChoice(
                          value: value,
                          selected: controller.seedColorValue == value,
                          onSelected: () =>
                              unawaited(controller.setSeedColorValue(value)),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: strings.language,
                icon: Icons.language_outlined,
                children: [
                  RadioGroup<String>(
                    groupValue: controller.languageCode,
                    onChanged: (value) {
                      if (value != null) {
                        unawaited(controller.setLanguageCode(value));
                      }
                    },
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: 'en',
                          title: Text(strings.english),
                        ),
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: 'el',
                          title: Text(strings.greek),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: strings.accountSecurity,
                icon: Icons.account_circle_outlined,
                children: [
                  if (authController == null)
                    Text(strings.accountComingSafely)
                  else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(authController!.email ?? 'Signed in'),
                      subtitle: const Text(
                        'Your notes and workspace are protected by this account.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        key: const ValueKey('open-active-sessions'),
                        onPressed: authController!.isBusy
                            ? null
                            : () async {
                                authController!.clearFeedback();

                                await Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => ActiveSessionsPage(
                                      controller: authController!,
                                    ),
                                  ),
                                );

                                if (authController!.isSignedIn) {
                                  authController!.clearFeedback();
                                }
                              },
                        icon: const Icon(Icons.devices_outlined),
                        label: const Text('Active sessions'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: authController!.isBusy
                            ? null
                            : () async {
                                authController!.clearFeedback();

                                await Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => ChangePasswordPage(
                                      controller: authController!,
                                    ),
                                  ),
                                );

                                if (authController!.isSignedIn) {
                                  authController!.clearFeedback();
                                }
                              },
                        icon: const Icon(Icons.password_outlined),
                        label: const Text('Change password'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _GoogleLinkAction(controller: authController!),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: authController!.isBusy
                            ? null
                            : () async {
                                Navigator.pop(context);
                                await authController!.logout();
                              },
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final int value;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final color = Color(value);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              width: selected ? 4 : 1,
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  color:
                      ThemeData.estimateBrightnessForColor(color) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                )
              : null,
        ),
      ),
    );
  }
}

class _GoogleLinkAction extends StatefulWidget {
  const _GoogleLinkAction({required this.controller});
  final AuthController controller;

  @override
  State<_GoogleLinkAction> createState() => _GoogleLinkActionState();
}

class _GoogleLinkActionState extends State<_GoogleLinkAction> {
  late Future<void> _status = widget.controller.refreshGoogleLinkStatus();

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _status,
    builder: (context, snapshot) {
      if (widget.controller.googleLinked == null) {
        if (snapshot.connectionState == ConnectionState.done) {
          return ListTile(
            title: const Text('Google link status unavailable'),
            subtitle: Text(
              widget.controller.googleLinkStatusError ?? 'Please try again.',
            ),
            trailing: TextButton(
              onPressed: () => setState(() {
                _status = widget.controller.refreshGoogleLinkStatus();
              }),
              child: const Text('Retry'),
            ),
          );
        }
        return const ListTile(
          leading: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Checking Google account…'),
        );
      }
      if (widget.controller.googleLinked == true) {
        return const ListTile(
          leading: Icon(Icons.check_circle_outline),
          title: Text('Google account linked'),
        );
      }
      return SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          key: const ValueKey('open-link-google'),
          onPressed: widget.controller.isBusy
              ? null
              : () async {
                  widget.controller.clearFeedback();
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          LinkGooglePage(controller: widget.controller),
                    ),
                  );
                  widget.controller.clearFeedback();
                  if (mounted) setState(() {});
                },
          icon: const Icon(Icons.account_circle_outlined),
          label: const Text('Link Google account'),
        ),
      );
    },
  );
}
