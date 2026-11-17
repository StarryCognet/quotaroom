import 'opencode_api.dart';
import 'settings_repository.dart';

/// USD -> CNY with a 6-hour cache; failures keep the last known rate.
class FxService {
  FxService({required this.settings, required this.api});

  final SettingsRepository settings;
  final OpenCodeApi api;

  static const double fallbackRate = 7.2;
  static const Duration ttl = Duration(hours: 6);

  Future<double> usdCny({bool force = false}) async {
    final cached = await settings.getFxCache();
    final rate = cached.rate > 0 ? cached.rate : fallbackRate;
    final at = cached.at;
    if (!force &&
        at != null &&
        DateTime.now().difference(at) < ttl) {
      return rate;
    }
    try {
      final fresh = await api.fetchUsdCny();
      await settings.saveFxRate(fresh);
      return fresh;
    } catch (_) {
      // Mark the cached value as fresh to avoid hammering the FX endpoint.
      await settings.saveFxRate(rate);
      return rate;
    }
  }
}
