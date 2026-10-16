import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsController extends ChangeNotifier {
  AppSettingsController._({
    required ThemeMode themeMode,
    required String languageCode,
    required int seedColorValue,
    required SharedPreferencesAsync? preferences,
  }) : _themeMode = themeMode,
       _languageCode = languageCode,
       _seedColorValue = seedColorValue,
       _preferences = preferences;

  factory AppSettingsController.ephemeral({
    ThemeMode themeMode = ThemeMode.system,
    String languageCode = 'en',
    int seedColorValue = defaultSeedColorValue,
  }) {
    return AppSettingsController._(
      themeMode: themeMode,
      languageCode: _normalizeLanguageCode(languageCode),
      seedColorValue: seedColorValue,
      preferences: null,
    );
  }

  static const _themeModeKey = 'settings.themeMode';
  static const _languageCodeKey = 'settings.languageCode';
  static const _seedColorKey = 'settings.seedColor';
  static const defaultSeedColorValue = 0xFF625BEB;

  final SharedPreferencesAsync? _preferences;

  ThemeMode _themeMode;
  String _languageCode;
  int _seedColorValue;

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;
  Locale get locale => Locale(_languageCode);
  Color get seedColor => Color(_seedColorValue);
  int get seedColorValue => _seedColorValue;

  static Future<AppSettingsController> load() async {
    final preferences = SharedPreferencesAsync();
    final storedThemeMode = await preferences.getString(_themeModeKey);
    final storedLanguageCode = await preferences.getString(_languageCodeKey);
    final storedSeedColor = await preferences.getInt(_seedColorKey);

    return AppSettingsController._(
      themeMode: _themeModeFromStorage(storedThemeMode),
      languageCode: _normalizeLanguageCode(storedLanguageCode),
      seedColorValue: storedSeedColor ?? defaultSeedColorValue,
      preferences: preferences,
    );
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) {
      return;
    }
    _themeMode = value;
    notifyListeners();
    await _preferences?.setString(_themeModeKey, value.name);
  }

  Future<void> setLanguageCode(String value) async {
    final normalized = _normalizeLanguageCode(value);
    if (_languageCode == normalized) {
      return;
    }
    _languageCode = normalized;
    notifyListeners();
    await _preferences?.setString(_languageCodeKey, normalized);
  }

  Future<void> setSeedColorValue(int value) async {
    if (_seedColorValue == value) {
      return;
    }
    _seedColorValue = value;
    notifyListeners();
    await _preferences?.setInt(_seedColorKey, value);
  }

  static ThemeMode _themeModeFromStorage(String? value) {
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  static String _normalizeLanguageCode(String? value) {
    return value == 'el' ? 'el' : 'en';
  }
}
