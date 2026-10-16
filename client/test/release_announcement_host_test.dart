import 'dart:convert';

import 'package:fasty/releases/release_announcement_api.dart';
import 'package:fasty/releases/release_announcement_controller.dart';
import 'package:fasty/releases/release_announcement_host.dart';
import 'package:fasty/releases/release_announcement_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('shows pending announcement and acknowledges it when dismissed', (
    tester,
  ) async {
    final preferences = _MemoryPreferences();
    var requestCount = 0;

    final controller = _controller(
      preferences: preferences,
      onRequest: () {
        requestCount++;
        return _announcementResponse('release-1');
      },
    );

    await tester.pumpWidget(_TestApp(controller: controller));

    await tester.pump();
    await tester.pumpAndSettle();

    expect(requestCount, 1);

    expect(
      find.byKey(const ValueKey('release-announcement-dialog')),
      findsOneWidget,
    );

    expect(find.text('New Fasty beta'), findsOneWidget);

    expect(find.text('Please install the latest beta build.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('acknowledge-release-announcement')),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('release-announcement-dialog')),
      findsNothing,
    );

    expect(
      await preferences.getString('releaseAnnouncement.lastAcknowledgedId'),
      'release-1',
    );

    controller.close();
  });

  testWidgets('same announcement stays hidden after acknowledgment', (
    tester,
  ) async {
    final preferences = _MemoryPreferences();

    final firstController = _controller(
      preferences: preferences,
      onRequest: () => _announcementResponse('release-1'),
    );

    await tester.pumpWidget(_TestApp(controller: firstController));

    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('release-announcement-dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('acknowledge-release-announcement')),
    );

    await tester.pumpAndSettle();

    firstController.close();

    final secondController = _controller(
      preferences: preferences,
      onRequest: () => _announcementResponse('release-1'),
    );

    await tester.pumpWidget(
      _TestApp(
        key: const ValueKey('second-launch'),
        controller: secondController,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('release-announcement-dialog')),
      findsNothing,
    );

    secondController.close();
  });

  testWidgets(
    'new announcement id is shown after an older one was acknowledged',
    (tester) async {
      final preferences = _MemoryPreferences();

      await preferences.setString(
        'releaseAnnouncement.lastAcknowledgedId',
        'release-1',
      );

      final controller = _controller(
        preferences: preferences,
        onRequest: () => _announcementResponse('release-2'),
      );

      await tester.pumpWidget(_TestApp(controller: controller));

      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('release-announcement-dialog')),
        findsOneWidget,
      );

      controller.close();
    },
  );

  testWidgets('shows Contact Christos when contact URL exists', (tester) async {
    final preferences = _MemoryPreferences();
    Uri? openedUri;

    final controller = _controller(
      preferences: preferences,
      onRequest: () => _announcementResponse(
        'release-contact',
        contactUrl: 'mailto:christos@example.com',
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        externalLinkLauncher: (uri) async {
          openedUri = uri;
          return true;
        },
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('contact-release-announcement')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('contact-release-announcement')),
    );

    await tester.pump();

    expect(openedUri, Uri.parse('mailto:christos@example.com'));

    expect(
      find.byKey(const ValueKey('release-announcement-dialog')),
      findsOneWidget,
    );

    expect(
      await preferences.getString('releaseAnnouncement.lastAcknowledgedId'),
      isNull,
    );

    controller.close();
  });

  testWidgets('hides Contact Christos when contact URL is absent', (
    tester,
  ) async {
    final preferences = _MemoryPreferences();

    final controller = _controller(
      preferences: preferences,
      onRequest: () => _announcementResponse('release-no-contact'),
    );

    await tester.pumpWidget(_TestApp(controller: controller));

    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('contact-release-announcement')),
      findsNothing,
    );

    controller.close();
  });

  testWidgets('announcement service failure does not block the app', (
    tester,
  ) async {
    final preferences = _MemoryPreferences();

    final controller = ReleaseAnnouncementController(
      api: ReleaseAnnouncementApi(
        baseUrl: 'http://fasty.test',
        client: MockClient(
          (_) async => http.Response('Service unavailable', 503),
        ),
      ),
      store: ReleaseAnnouncementStore(preferences: preferences),
    );

    await tester.pumpWidget(_TestApp(controller: controller));

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Signed-in content'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('release-announcement-dialog')),
      findsNothing,
    );

    controller.close();
  });
}

ReleaseAnnouncementController _controller({
  required _MemoryPreferences preferences,
  required http.Response Function() onRequest,
}) {
  return ReleaseAnnouncementController(
    api: ReleaseAnnouncementApi(
      baseUrl: 'http://fasty.test',
      client: MockClient((_) async => onRequest()),
    ),
    store: ReleaseAnnouncementStore(preferences: preferences),
  );
}

http.Response _announcementResponse(String id, {String? contactUrl}) {
  return http.Response(
    jsonEncode({
      'id': id,
      'title': 'New Fasty beta',
      'message': 'Please install the latest beta build.',
      'contactUrl': contactUrl,
    }),
    200,
    headers: const {'content-type': 'application/json'},
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    super.key,
    required this.controller,
    this.externalLinkLauncher,
  });

  final ReleaseAnnouncementController controller;
  final ExternalReleaseLinkLauncher? externalLinkLauncher;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ReleaseAnnouncementHost(
        controller: controller,
        externalLinkLauncher: externalLinkLauncher,
        child: const Scaffold(body: Center(child: Text('Signed-in content'))),
      ),
    );
  }
}

class _MemoryPreferences implements ReleaseAnnouncementPreferences {
  final Map<String, String> _values = {};

  @override
  Future<String?> getString(String key) async {
    return _values[key];
  }

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }
}
