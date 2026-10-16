import 'dart:io';
import 'package:fasty/releases/release_announcement_api.dart';
import 'package:fasty/releases/release_announcement_controller.dart';
import 'package:fasty/releases/release_announcement_host.dart';
import 'package:fasty/releases/release_announcement_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/connections_ui_regression_test.dart' as connections;
import '../test/workspace_deletion_ui_test.dart' as workspaces;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    expect(Platform.environment['FASTY_R3_ISOLATED'], '1');
    for (final key in ['XDG_CONFIG_HOME', 'XDG_DATA_HOME']) {
      expect(
        Platform.environment[key],
        startsWith('${Directory.systemTemp.path}/fasty-r3-'),
        reason: '$key must point to a dedicated temporary R3 directory.',
      );
    }
  });
  if (const bool.fromEnvironment('FASTY_R3_RESTART_CHECK')) {
    testWidgets('acknowledgment survives a separate Linux process', (
      tester,
    ) async {
      expect(Platform.environment['FASTY_R3_ISOLATED'], '1');
      final api = ReleaseAnnouncementApi(
        baseUrl: const String.fromEnvironment('FASTY_API_BASE_URL'),
      );
      final current = await api.fetchCurrent();
      expect(current, isNotNull);
      expect(
        await ReleaseAnnouncementStore().isAcknowledged(current!.id),
        isTrue,
      );
      final controller = ReleaseAnnouncementController(
        api: api,
        store: ReleaseAnnouncementStore(),
      );
      expect(await controller.loadPending(), isNull);
      controller.close();
    });
    return;
  }
  connections.main();
  workspaces.main();
  testWidgets(
    'live release notice persists acknowledgment in Linux preferences',
    (tester) async {
      const baseUrl = String.fromEnvironment('FASTY_API_BASE_URL');
      expect(baseUrl, isNotEmpty);
      // Require isolated preferences rather than touch the user's acknowledgment.
      expect(Platform.environment['FASTY_R3_ISOLATED'], '1');
      final api = ReleaseAnnouncementApi(baseUrl: baseUrl);
      final current = await api.fetchCurrent();
      expect(
        current,
        isNotNull,
        reason: 'The live release announcement must be enabled.',
      );
      final preferences = SharedPreferencesAsync();
      await preferences.remove('releaseAnnouncement.lastAcknowledgedId');
      final controller = ReleaseAnnouncementController(
        api: api,
        store: ReleaseAnnouncementStore(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReleaseAnnouncementHost(
            controller: controller,
            child: const Scaffold(body: Text('R3 Linux release test')),
          ),
        ),
      );
      for (
        var i = 0;
        i < 100 &&
            find
                .byKey(const ValueKey('release-announcement-dialog'))
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byKey(const ValueKey('release-announcement-dialog')),
        findsOneWidget,
      );
      expect(find.text(current!.title), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('acknowledge-release-announcement')),
      );
      await tester.pumpAndSettle();
      expect(
        await ReleaseAnnouncementStore().isAcknowledged(current.id),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.close();
      final relaunched = ReleaseAnnouncementController(
        api: ReleaseAnnouncementApi(baseUrl: baseUrl),
        store: ReleaseAnnouncementStore(),
      );
      expect(await relaunched.loadPending(), isNull);
      relaunched.close();
    },
  );
}
