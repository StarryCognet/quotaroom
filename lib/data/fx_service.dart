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
    final now = DateTime.now();
    final at = cached.at;
    if (!force && at != null && now.difference(at) < ttl) {
      return rate;
    }
    // A failed fetch is retried after an hour, not on every launch, but it
    // must not refresh the successful-fetch timestamp and hide stale data.
    final attempted = cached.attemptedAt;
    if (!force &&
        attempted != null &&
        now.difference(attempted) < const Duration(hours: 1)) {
      return rate;
    }
    try {
      final fresh = await api.fetchUsdCny();
      await settings.saveFxRate(fresh);
      return fresh;
    } catch (_) {
      await settings.markFxAttempt();
      return rate;
    }
  }
}
