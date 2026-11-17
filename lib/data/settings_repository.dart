import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'models.dart';

class FxCache {
  const FxCache({required this.rate, this.at});

  final double rate;
  final DateTime? at;
}

/// Reads/writes the single-row JSON settings payload.
class SettingsRepository {
  SettingsRepository(this.db);

  final Database db;

  Future<Map<String, Object?>> rawPayload() async {
    final rows = await db.query('settings', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return {};
    final raw = rows.first['payload']?.toString() ?? '{}';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } catch (_) {
      // Fall through to an empty payload.
    }
    return {};
  }

  Future<void> writePayload(Map<String, Object?> payload) async {
    await db.update(
      'settings',
      {'payload': jsonEncode(payload), 'updated_at': nowIso()},
      where: 'id = 1',
    );
  }

  Future<Settings> getSettings() async {
    final raw = await rawPayload();
    return Settings.fromJson(raw);
  }

  Future<Settings> saveSettings(Settings settings) async {
    final raw = await rawPayload();
    raw.addAll(settings.toJson());
    await writePayload(raw);
    return settings;
  }

  Future<int?> activeAccountId() async {
    final raw = await rawPayload();
    final value = raw['active_account_id'];
    return value is num ? value.toInt() : null;
  }

  Future<void> setActiveAccountId(int? accountId) async {
    final raw = await rawPayload();
    if (accountId == null) {
      raw.remove('active_account_id');
    } else {
      raw['active_account_id'] = accountId;
    }
    await writePayload(raw);
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
    final raw = await rawPayload();
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
    await writePayload(raw);
  }

  Future<FxCache> getFxCache() async {
    final raw = await rawPayload();
    final rate = (raw['fx_rate'] as num?)?.toDouble() ?? 7.2;
    final at = parseDateTime(raw['fx_at']);
    return FxCache(rate: rate > 0 ? rate : 7.2, at: at);
  }

  Future<void> saveFxRate(double rate) async {
    if (!rate.isFinite || rate <= 0) return;
    final raw = await rawPayload();
    raw['fx_rate'] = rate;
    raw['fx_at'] = nowIso();
    await writePayload(raw);
  }
}
