import 'package:shared_preferences/shared_preferences.dart';

/// UI-only preferences (theme / language / currency), mirroring the desktop
/// app's localStorage keys.
class Prefs {
  Prefs(this._prefs);

  static const _themeKey = 'quotaroom_theme';
  static const _langKey = 'quotaroom_lang';
  static const _currencyKey = 'quotaroom_currency';

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

  Future<void> setCurrency(String value) => _prefs.setString(_currencyKey, value);
}
