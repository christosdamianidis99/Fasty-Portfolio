import 'package:fasty/releases/release_announcement_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('announcement starts unacknowledged', () async {
    final preferences = _MemoryReleaseAnnouncementPreferences();
    final store = ReleaseAnnouncementStore(preferences: preferences);

    expect(await store.isAcknowledged('release-1'), isFalse);
  });

  test('acknowledging announcement remembers its id', () async {
    final preferences = _MemoryReleaseAnnouncementPreferences();
    final store = ReleaseAnnouncementStore(preferences: preferences);

    await store.acknowledge(' release-1 ');

    expect(await store.lastAcknowledgedId(), 'release-1');

    expect(await store.isAcknowledged('release-1'), isTrue);
  });

  test('new announcement id is not already acknowledged', () async {
    final preferences = _MemoryReleaseAnnouncementPreferences();
    final store = ReleaseAnnouncementStore(preferences: preferences);

    await store.acknowledge('release-1');

    expect(await store.isAcknowledged('release-2'), isFalse);
  });

  test('empty announcement id cannot be acknowledged', () async {
    final preferences = _MemoryReleaseAnnouncementPreferences();
    final store = ReleaseAnnouncementStore(preferences: preferences);

    await expectLater(store.acknowledge('   '), throwsFormatException);
  });
}

class _MemoryReleaseAnnouncementPreferences
    implements ReleaseAnnouncementPreferences {
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
