import 'package:shared_preferences/shared_preferences.dart';

/// UI-only preferences (theme / language / currency), mirroring the desktop
/// app's localStorage keys.
class Prefs {
  Prefs(this._prefs);

  static const _themeKey = 'quotaroom_theme';
  static const _langKey = 'quotaroom_lang';
  static const _currencyKey = 'quotaroom_currency';
  static const _updateCheckedKey = 'quotaroom_update_checked_at';
  static const _dismissedUpdateKey = 'quotaroom_dismissed_update';

  final SharedPreferences _prefs;

  static Future<Prefs> load() async {
    return Prefs(await SharedPreferences.getInstance());
  }

  String get themeMode {
    final value = _prefs.getString(_themeKey) ?? 'system';
    return value == 'light' || value == 'dark' ? value : 'system';
  }

  String get language {
    final value = _prefs.getString(_langKey) ?? 'zh';
    return value == 'en' ? 'en' : 'zh';
  }

  String get currency {
    final value = _prefs.getString(_currencyKey) ?? 'CNY';
    return value == 'USD' ? 'USD' : 'CNY';
  }

  Future<void> setThemeMode(String value) => _prefs.setString(_themeKey, value);

  Future<void> setLanguage(String value) => _prefs.setString(_langKey, value);

  Future<void> setCurrency(String value) =>
      _prefs.setString(_currencyKey, value);

  DateTime? get updateCheckedAt =>
      DateTime.tryParse(_prefs.getString(_updateCheckedKey) ?? '');

  Future<void> setUpdateCheckedAt(DateTime value) =>
      _prefs.setString(_updateCheckedKey, value.toIso8601String());

  String? get dismissedUpdateVersion => _prefs.getString(_dismissedUpdateKey);

  Future<void> setDismissedUpdateVersion(String? value) {
    if (value == null || value.isEmpty) {
      return _prefs.remove(_dismissedUpdateKey);
    }
    return _prefs.setString(_dismissedUpdateKey, value);
  }
}
