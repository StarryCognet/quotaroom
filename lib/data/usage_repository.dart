import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'models.dart';

/// Aggregates usage rows exactly like the desktop app's `app/db.py`, but uses
/// `created_ms` for range predicates and SQLite's `unixepoch/localtime` for
/// day/hour buckets.
class UsageRepository {
  UsageRepository(this.db);

  final Database db;

  static int? fromMsForPeriod(String period) {
    final now = DateTime.now();
    switch (period) {
      case 'today':
        return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      case '5h':
        return now
            .subtract(const Duration(hours: 5))
            .millisecondsSinceEpoch;
      case 'all':
        return null;
      default:
        final match = RegExp(r'^(\d+)d$').firstMatch(period);
        final days = match == null
            ? 30
            : (int.tryParse(match.group(1) ?? '') ?? 30);
        return now.subtract(Duration(days: days)).millisecondsSinceEpoch;
    }
  }

  Future<int> insertUsageRecords(
    List<UsageRecord> records,
    int accountId,
  ) async {
    if (records.isEmpty) return 0;
    return db.transaction<int>((txn) async {
      final syncedAt = nowIso();
      var inserted = 0;
      for (final record in records) {
        final map = record.toDbMap(
          accountId: accountId,
          syncedAt: syncedAt,
        );
        final existing = await txn.query(
          'usage_records',
          columns: ['usg_id'],
          where: 'usg_id = ?',
          whereArgs: [record.usgId],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('usage_records', map);
          inserted++;
        } else {
          // Desktop upsert semantics: token/cost fields are refreshed, but
          // identity fields (created_at/model/session/account) are preserved.
          await txn.update(
            'usage_records',
            {
              'input_tokens': map['input_tokens'],
              'output_tokens': map['output_tokens'],
              'reasoning_tokens': map['reasoning_tokens'],
              'cache_read_tokens': map['cache_read_tokens'],
              'cache_write_5m_tokens': map['cache_write_5m_tokens'],
              'cache_write_1h_tokens': map['cache_write_1h_tokens'],
              'cost_raw': map['cost_raw'],
              'cost_usd': map['cost_usd'],
              'synced_at': map['synced_at'],
            },
            where: 'usg_id = ?',
            whereArgs: [record.usgId],
          );
        }
      }
      return inserted;
    });
  }

  Future<int> pruneOldRecords(int accountId, int? windowDays) async {
    if (windowDays == null) return 0;
    final days = windowDays.clamp(1, 3650).toInt();
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    return db.delete(
      'usage_records',
      where: 'account_id = ? AND created_ms < ?',
      whereArgs: [accountId, cutoff],
    );
  }

  Future<Totals> totals(int accountId, String period) async {
    final fromMs = fromMsForPeriod(period);
    final where = StringBuffer('account_id = ?');
    final args = <Object?>[accountId];
    if (fromMs != null) {
      where.write(' AND created_ms >= ?');
      args.add(fromMs);
    }
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS request_count,
             COUNT(DISTINCT CASE WHEN session_id IS NOT NULL AND session_id != ''
                                 THEN session_id END) AS session_count,
             SUM(input_tokens + cache_read_tokens + cache_write_5m_tokens
                 + cache_write_1h_tokens) AS total_input_tokens,
             SUM(input_tokens) AS uncached_input_tokens,
             SUM(reasoning_tokens) AS total_reasoning_tokens,
             SUM(cache_read_tokens) AS cache_hit_tokens,
             SUM(cache_write_5m_tokens + cache_write_1h_tokens) AS cache_write_tokens,
             SUM(output_tokens) AS total_output_tokens,
             SUM(cost_usd) AS total_cost_usd
      FROM usage_records
      WHERE $where
    ''', args);
    return _totalsFromRow(rows.isEmpty ? const {} : rows.first);
  }

  Future<List<ModelStat>> modelStats(int accountId, String period) async {
    final fromMs = fromMsForPeriod(period);
    final where = StringBuffer('account_id = ?');
    final args = <Object?>[accountId];
    if (fromMs != null) {
      where.write(' AND created_ms >= ?');
      args.add(fromMs);
    }
    final rows = await db.rawQuery('''
      SELECT model,
             COUNT(*) AS request_count,
             COUNT(DISTINCT CASE WHEN session_id IS NOT NULL AND session_id != ''
                                 THEN session_id END) AS session_count,
             SUM(input_tokens + cache_read_tokens + cache_write_5m_tokens
                 + cache_write_1h_tokens) AS total_input_tokens,
             SUM(input_tokens) AS uncached_input_tokens,
             SUM(reasoning_tokens) AS total_reasoning_tokens,
             SUM(cache_read_tokens) AS cache_hit_tokens,
             SUM(cache_write_5m_tokens + cache_write_1h_tokens) AS cache_write_tokens,
             SUM(output_tokens) AS total_output_tokens,
             SUM(cost_usd) AS total_cost_usd
      FROM usage_records
      WHERE $where
      GROUP BY model
      ORDER BY (SUM(input_tokens + cache_read_tokens + cache_write_5m_tokens
                    + cache_write_1h_tokens) + SUM(output_tokens)) DESC
    ''', args);
    return rows.map((row) {
      final hit = _int(row['cache_hit_tokens']);
      final miss = _int(row['uncached_input_tokens']);
      return ModelStat(
        model: (row['model'] ?? '').toString(),
        requestCount: _int(row['request_count']),
        sessionCount: _int(row['session_count']),
        totalInputTokens: _int(row['total_input_tokens']),
        uncachedInputTokens: miss,
        totalReasoningTokens: _int(row['total_reasoning_tokens']),
        cacheHitTokens: hit,
        cacheWriteTokens: _int(row['cache_write_tokens']),
        totalOutputTokens: _int(row['total_output_tokens']),
        totalCostUsd: _double(row['total_cost_usd']),
        hitRate: _hitRate(hit, miss),
      );
    }).toList();
  }

  Future<List<DailyStat>> dailyStats(int accountId, int days) async {
    final clamped = days.clamp(1, 365).toInt();
    final rows = await db.rawQuery('''
      SELECT date(created_ms / 1000, 'unixepoch', 'localtime') AS date,
             SUM(input_tokens + cache_read_tokens + cache_write_5m_tokens
                 + cache_write_1h_tokens) AS total_input_tokens,
             SUM(input_tokens) AS uncached_input_tokens,
             SUM(reasoning_tokens) AS total_reasoning_tokens,
             SUM(cache_read_tokens) AS cache_hit_tokens,
             SUM(cache_write_5m_tokens + cache_write_1h_tokens) AS cache_write_tokens,
             SUM(output_tokens) AS total_output_tokens,
             SUM(cost_usd) AS total_cost_usd,
             COUNT(*) AS request_count
      FROM usage_records
      WHERE account_id = ?
        AND date(created_ms / 1000, 'unixepoch', 'localtime')
            >= date('now', 'localtime', ?)
      GROUP BY date
      ORDER BY date ASC
    ''', [accountId, '-$clamped days']);
    return rows.map((row) {
      final hit = _int(row['cache_hit_tokens']);
      final miss = _int(row['uncached_input_tokens']);
      return DailyStat(
        date: (row['date'] ?? '').toString(),
        totalInputTokens: _int(row['total_input_tokens']),
        uncachedInputTokens: miss,
        totalReasoningTokens: _int(row['total_reasoning_tokens']),
        cacheHitTokens: hit,
        cacheWriteTokens: _int(row['cache_write_tokens']),
        totalOutputTokens: _int(row['total_output_tokens']),
        totalCostUsd: _double(row['total_cost_usd']),
        requestCount: _int(row['request_count']),
        hitRate: _hitRate(hit, miss),
      );
    }).toList();
  }

  Future<List<HourPoint>> todayTrend(int accountId) async {
    final rows = await db.rawQuery('''
      SELECT CAST(strftime('%H', created_ms / 1000, 'unixepoch', 'localtime')
                  AS INTEGER) AS h,
             SUM(input_tokens) AS input,
             SUM(output_tokens) AS output,
             SUM(reasoning_tokens) AS reasoning
      FROM usage_records
      WHERE account_id = ?
        AND date(created_ms / 1000, 'unixepoch', 'localtime')
            = date('now', 'localtime')
      GROUP BY h
    ''', [accountId]);
    final byHour = <int, Map<String, Object?>>{};
    for (final row in rows) {
      byHour[_int(row['h'])] = row;
    }
    return List.generate(24, (hour) {
      final row = byHour[hour];
      return HourPoint(
        hour: hour,
        input: row == null ? 0 : _int(row['input']),
        output: row == null ? 0 : _int(row['output']),
        reasoning: row == null ? 0 : _int(row['reasoning']),
      );
    });
  }

  Future<RecordsPageResult> recordsPage(
    int accountId, {
    int page = 1,
    int pageSize = 20,
    String? model,
    int? days,
  }) async {
    final currentPage = page < 1 ? 1 : page;
    final size = pageSize.clamp(1, 100).toInt();
    final where = <String>['account_id = ?'];
    final args = <Object?>[accountId];
    if (model != null && model.isNotEmpty) {
      where.add('model = ?');
      args.add(model);
    }
    if (days != null && days > 0) {
      where.add('created_ms >= ?');
      args.add(
        DateTime.now()
            .subtract(Duration(days: days))
            .millisecondsSinceEpoch,
      );
    }
    final whereSql = where.join(' AND ');
    final total = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM usage_records WHERE $whereSql',
            args,
          ),
        ) ??
        0;
    final rows = await db.query(
      'usage_records',
      where: whereSql,
      whereArgs: args,
      orderBy: 'created_ms DESC',
      limit: size,
      offset: (currentPage - 1) * size,
    );
    return RecordsPageResult(
      records: rows.map(UsageRecord.fromDbMap).toList(),
      total: total,
    );
  }

  Future<SessionsPageResult> sessionsPage(
    int accountId, {
    int page = 1,
    int pageSize = 20,
    int? days,
  }) async {
    final currentPage = page < 1 ? 1 : page;
    final size = pageSize.clamp(1, 50).toInt();
    const keyExpr =
        "CASE WHEN session_id IS NOT NULL AND session_id != '' THEN session_id "
        "WHEN key_id IS NOT NULL AND key_id != '' THEN key_id ELSE '' END";
    final where = <String>['account_id = ?'];
    final args = <Object?>[accountId];
    if (days != null && days > 0) {
      where.add('created_ms >= ?');
      args.add(
        DateTime.now()
            .subtract(Duration(days: days))
            .millisecondsSinceEpoch,
      );
    }
    final whereSql = where.join(' AND ');
    final total = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(DISTINCT $keyExpr) FROM usage_records WHERE $whereSql',
            args,
          ),
        ) ??
        0;
    final rows = await db.rawQuery('''
      SELECT $keyExpr AS session_id,
             MAX(key_id) AS key_id,
             COUNT(*) AS request_count,
             SUM(input_tokens + cache_read_tokens + cache_write_5m_tokens
                 + cache_write_1h_tokens) AS total_input_tokens,
             SUM(input_tokens) AS uncached_input_tokens,
             SUM(output_tokens) AS total_output_tokens,
             SUM(reasoning_tokens) AS total_reasoning_tokens,
             SUM(cost_usd) AS total_cost_usd,
             MAX(created_ms) AS last_ms
      FROM usage_records
      WHERE $whereSql
      GROUP BY $keyExpr
      ORDER BY last_ms DESC
      LIMIT ? OFFSET ?
    ''', [...args, size, (currentPage - 1) * size]);
    return SessionsPageResult(
      total: total,
      records: rows.map((row) {
        var sessionId = (row['session_id'] ?? '').toString();
        if (sessionId.startsWith('key_') || sessionId.startsWith('sk_')) {
          sessionId = '';
        }
        final lastMs = _int(row['last_ms']);
        return SessionStat(
          sessionId: sessionId,
          keyId: (row['key_id'] ?? '').toString(),
          requestCount: _int(row['request_count']),
          totalInputTokens: _int(row['total_input_tokens']),
          uncachedInputTokens: _int(row['uncached_input_tokens']),
          totalOutputTokens: _int(row['total_output_tokens']),
          totalReasoningTokens: _int(row['total_reasoning_tokens']),
          totalCostUsd: _double(row['total_cost_usd']),
          lastAt: lastMs <= 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(lastMs, isUtc: true),
        );
      }).toList(),
    );
  }

  Future<List<String>> models(int accountId) async {
    final rows = await db.query(
      'usage_records',
      columns: ['model'],
      where: 'account_id = ?',
      whereArgs: [accountId],
      groupBy: 'model',
      orderBy: 'model ASC',
      distinct: true,
    );
    return rows
        .map((row) => (row['model'] ?? '').toString())
        .where((model) => model.isNotEmpty)
        .toList();
  }

  Future<SyncState> syncState(int accountId) async {
    final rows = await db.query(
      'usage_sync_state',
      where: 'account_id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (rows.isEmpty) return SyncState.empty;
    final row = rows.first;
    return SyncState(
      lastSyncAt: parseDateTime(row['last_sync_at']),
      lastSyncStatus: row['last_sync_status']?.toString(),
      lastSyncError: row['last_sync_error']?.toString(),
      lastInsertedCount: _int(row['last_inserted_count']),
      totalRecords: _int(row['total_records']),
      oldestRecordAt: parseDateTime(row['oldest_record_at']),
      newestRecordAt: parseDateTime(row['newest_record_at']),
    );
  }

  Future<void> updateSyncState(
    int accountId, {
    required String status,
    String? error,
    int inserted = 0,
  }) async {
    await db.transaction((txn) async {
      final existing = await txn.query(
        'usage_sync_state',
        columns: ['account_id'],
        where: 'account_id = ?',
        whereArgs: [accountId],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('usage_sync_state', {
          'account_id': accountId,
          'last_inserted_count': 0,
          'deepest_page_fetched': -1,
          'total_records': 0,
        });
      }
      await txn.rawUpdate('''
        UPDATE usage_sync_state
        SET last_sync_at = ?, last_sync_status = ?, last_sync_error = ?,
            last_inserted_count = last_inserted_count + ?
        WHERE account_id = ?
      ''', [nowIso(), status, error, inserted, accountId]);
      await _refreshSyncTotals(txn, accountId);
    });
  }

  Future<void> refreshSyncTotals(int accountId) => db.transaction(
    (txn) => _refreshSyncTotals(txn, accountId),
  );

  Future<void> _refreshSyncTotals(Transaction txn, int accountId) async {
    final rows = await txn.rawQuery('''
      SELECT COUNT(*) AS total,
             MIN(created_at) AS oldest,
             MAX(created_at) AS newest
      FROM usage_records
      WHERE account_id = ?
    ''', [accountId]);
    final row = rows.isEmpty ? <String, Object?>{} : rows.first;
    await txn.update(
      'usage_sync_state',
      {
        'total_records': _int(row['total']),
        'oldest_record_at': row['oldest']?.toString(),
        'newest_record_at': row['newest']?.toString(),
      },
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
  }

  Totals _totalsFromRow(Map<String, Object?> row) {
    final hit = _int(row['cache_hit_tokens']);
    final miss = _int(row['uncached_input_tokens']);
    return Totals(
      requestCount: _int(row['request_count']),
      sessionCount: _int(row['session_count']),
      totalInputTokens: _int(row['total_input_tokens']),
      uncachedInputTokens: miss,
      totalReasoningTokens: _int(row['total_reasoning_tokens']),
      cacheHitTokens: hit,
      cacheWriteTokens: _int(row['cache_write_tokens']),
      totalOutputTokens: _int(row['total_output_tokens']),
      totalCostUsd: _double(row['total_cost_usd']),
      hitRate: _hitRate(hit, miss),
    );
  }

  static int _int(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  static double _double(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static double _hitRate(int hit, int miss) {
    final total = hit + miss;
    if (total <= 0) return 0;
    return ((hit / total) * 100 * 100).round() / 100;
  }
}
