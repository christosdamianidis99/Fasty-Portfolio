import 'release_announcement.dart';
import 'release_announcement_api.dart';
import 'release_announcement_store.dart';

class ReleaseAnnouncementController {
  ReleaseAnnouncementController({
    required ReleaseAnnouncementApi api,
    required ReleaseAnnouncementStore store,
  }) : _api = api,
       _store = store;

  final ReleaseAnnouncementApi _api;
  final ReleaseAnnouncementStore _store;

  Future<ReleaseAnnouncement?> loadPending() async {
    final announcement = await _api.fetchCurrent();

    if (announcement == null) {
      return null;
    }

    if (await _store.isAcknowledged(announcement.id)) {
      return null;
    }

    return announcement;
  }

  Future<void> acknowledge(ReleaseAnnouncement announcement) {
    return _store.acknowledge(announcement.id);
  }

  void close() {
    _api.close();
  }
}
