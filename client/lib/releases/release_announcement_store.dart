import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ReleaseAnnouncementPreferences {
  Future<String?> getString(String key);

  Future<void> setString(String key, String value);
}

class SharedPreferencesReleaseAnnouncementPreferences
    implements ReleaseAnnouncementPreferences {
  SharedPreferencesReleaseAnnouncementPreferences({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) {
    return _preferences.getString(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    await _preferences.setString(key, value);
  }
}

class ReleaseAnnouncementStore {
  ReleaseAnnouncementStore({ReleaseAnnouncementPreferences? preferences})
    : _preferences =
          preferences ?? SharedPreferencesReleaseAnnouncementPreferences();

  static const _lastAcknowledgedIdKey =
      'releaseAnnouncement.lastAcknowledgedId';

  final ReleaseAnnouncementPreferences _preferences;

  Future<String?> lastAcknowledgedId() {
    return _preferences.getString(_lastAcknowledgedIdKey);
  }

  Future<bool> isAcknowledged(String announcementId) async {
    final normalizedId = announcementId.trim();

    if (normalizedId.isEmpty) {
      return false;
    }

    return await lastAcknowledgedId() == normalizedId;
  }

  Future<void> acknowledge(String announcementId) async {
    final normalizedId = announcementId.trim();

    if (normalizedId.isEmpty) {
      throw const FormatException('Release announcement ID is required.');
    }

    await _preferences.setString(_lastAcknowledgedIdKey, normalizedId);
  }
}
