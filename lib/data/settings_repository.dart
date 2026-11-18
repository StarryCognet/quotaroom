import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'models.dart';

class FxCache {
  const FxCache({required this.rate, this.at, this.attemptedAt});

  final double rate;

  /// Time of the last successful fetch. A fallback rate never advances this.
  final DateTime? at;

  /// Time of the last attempt, successful or not. Used only to throttle
  /// retries without making a fallback rate look fresh.
  final DateTime? attemptedAt;
}

/// Reads/writes the single-row JSON settings payload.
class SettingsRepository {
  SettingsRepository(this.db);

  final Database db;

  static Map<String, Object?> _decode(Object? raw) {
    try {
      final decoded = jsonDecode(raw?.toString() ?? '{}');
      if (decoded is Map) return decoded.cast<String, Object?>();
    } catch (_) {
      // Fall through to an empty payload.
    }
    return {};
  }

  static Future<Map<String, Object?>> _read(DatabaseExecutor executor) async {
    final rows = await executor.query('settings', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return {};
    return _decode(rows.first['payload']);
  }

  /// Atomically reads, mutates and writes the JSON payload. A read followed by
  /// a separate write loses concurrent updates from sync logs, key-name
  /// merges or the Android background isolate.
  Future<void> _mutate(
    void Function(Map<String, Object?> payload) change,
  ) async {
    await db.transaction((txn) async {
      final raw = await _read(txn);
      change(raw);
      await txn.update('settings', {
        'payload': jsonEncode(raw),
        'updated_at': nowIso(),
      }, where: 'id = 1');
    });
  }

  Future<Map<String, Object?>> rawPayload() => _read(db);

  Future<Settings> getSettings() async {
    return Settings.fromJson(await rawPayload());
  }

  Future<Settings> saveSettings(Settings settings) async {
    await _mutate((raw) => raw.addAll(settings.toJson()));
    return settings;
  }

  Future<int?> activeAccountId() async {
    final raw = await rawPayload();
    final value = raw['active_account_id'];
    return value is num ? value.toInt() : null;
  }

  Future<void> setActiveAccountId(int? accountId) async {
    await _mutate((raw) {
      if (accountId == null) {
        raw.remove('active_account_id');
      } else {
        raw['active_account_id'] = accountId;
      }
    });
  }

  Future<Map<String, String>> getKeyNames() async {
    final raw = await rawPayload();
    final value = raw['key_names'];
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }
    return const {};
  }

  Future<void> mergeKeyNames(Map<String, String> names) async {
    if (names.isEmpty) return;
    await _mutate((raw) {
      final merged = <String, String>{};
      final existing = raw['key_names'];
      if (existing is Map) {
        existing.forEach((key, value) {
          if (key.toString().isNotEmpty && value.toString().isNotEmpty) {
            merged[key.toString()] = value.toString();
          }
        });
      }
      merged.addAll(names);
      raw['key_names'] = merged;
    });
  }

  Future<void> addSyncLog(Map<String, Object?> entry) async {
    await _mutate((raw) {
      final list = <Map<String, Object?>>[];
      final existing = raw['sync_log'];
      if (existing is List) {
        for (final item in existing) {
          if (item is Map) list.add(item.cast<String, Object?>());
        }
      }
      list.insert(0, entry);
      if (list.length > 30) {
        list.removeRange(30, list.length);
      }
      raw['sync_log'] = list;
    });
  }

  Future<List<Map<String, Object?>>> getSyncLog() async {
    final raw = await rawPayload();
    final existing = raw['sync_log'];
    if (existing is! List) return const [];
    final result = <Map<String, Object?>>[];
    for (final item in existing) {
      if (item is Map) result.add(item.cast<String, Object?>());
    }
    return result;
  }

  Future<FxCache> getFxCache() async {
    final raw = await rawPayload();
    final rate = (raw['fx_rate'] as num?)?.toDouble() ?? 7.2;
    return FxCache(
      rate: rate > 0 ? rate : 7.2,
      at: parseDateTime(raw['fx_at']),
      attemptedAt: parseDateTime(raw['fx_attempt_at']),
    );
  }

  Future<void> saveFxRate(double rate) async {
    if (!rate.isFinite || rate <= 0) return;
    final now = nowIso();
    await _mutate((raw) {
      raw['fx_rate'] = rate;
      raw['fx_at'] = now;
      raw['fx_attempt_at'] = now;
    });
  }

  Future<void> markFxAttempt() async {
    await _mutate((raw) => raw['fx_attempt_at'] = nowIso());
  }
}
