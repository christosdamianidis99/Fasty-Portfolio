import 'dart:convert';

import 'package:fasty/releases/release_announcement.dart';
import 'package:fasty/releases/release_announcement_api.dart';
import 'package:fasty/releases/release_announcement_controller.dart';
import 'package:fasty/releases/release_announcement_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('returns active unacknowledged announcement', () async {
    final preferences = _MemoryPreferences();

    final api = ReleaseAnnouncementApi(
      baseUrl: 'http://fasty.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'id': 'release-2',
            'title': 'New build',
            'message': 'Please update.',
            'contactUrl': null,
          }),
          200,
        ),
      ),
    );

    final controller = ReleaseAnnouncementController(
      api: api,
      store: ReleaseAnnouncementStore(preferences: preferences),
    );

    final announcement = await controller.loadPending();

    expect(announcement?.id, 'release-2');

    controller.close();
  });

  test('does not return already acknowledged announcement', () async {
    final preferences = _MemoryPreferences();
    final store = ReleaseAnnouncementStore(preferences: preferences);

    await store.acknowledge('release-2');

    final api = ReleaseAnnouncementApi(
      baseUrl: 'http://fasty.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'id': 'release-2',
            'title': 'New build',
            'message': 'Please update.',
          }),
          200,
        ),
      ),
    );

    final controller = ReleaseAnnouncementController(api: api, store: store);

    expect(await controller.loadPending(), isNull);

    controller.close();
  });

  test('acknowledge stores announcement id', () async {
    final preferences = _MemoryPreferences();

    final controller = ReleaseAnnouncementController(
      api: ReleaseAnnouncementApi(
        baseUrl: 'http://fasty.test',
        client: MockClient((_) async => http.Response('', 204)),
      ),
      store: ReleaseAnnouncementStore(preferences: preferences),
    );

    const announcement = ReleaseAnnouncement(
      id: 'release-3',
      title: 'New build',
      message: 'Please update.',
    );

    await controller.acknowledge(announcement);

    expect(
      await preferences.getString('releaseAnnouncement.lastAcknowledgedId'),
      'release-3',
    );

    controller.close();
  });
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
