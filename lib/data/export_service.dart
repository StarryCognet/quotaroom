import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'usage_repository.dart';

class ExportService {
  ExportService({required this.db, required this.usage});

  final Database db;
  final UsageRepository usage;

  Future<File> exportRecordsCsv(
    int accountId,
    Map<String, String> keyNames, {
    String? model,
    int? days,
    String? keyId,
    String? sessionId,
    String? query,
  }) async {
    final records = await usage.allRecords(
      accountId,
      model: model,
      days: days,
      keyId: keyId,
      sessionId: sessionId,
      query: query,
    );
    final buffer = StringBuffer();
    buffer.writeln(
      'created_at,model,provider,key_id,key_name,session_id,'
      'input_tokens,output_tokens,reasoning_tokens,cache_read_tokens,'
      'cache_write_tokens,cost_usd,plan',
    );
    for (final record in records) {
      buffer.writeln(
        [
          _csv(
            DateFormat('yyyy-MM-dd HH:mm:ss')
                .format(record.createdAt.toLocal()),
          ),
          _csv(record.model),
          _csv(record.provider),
          _csv(record.keyId),
          _csv(keyNames[record.keyId] ?? ''),
          _csv(record.sessionId),
          record.inputTokens,
          record.outputTokens,
          record.reasoningTokens,
          record.cacheReadTokens,
          record.cacheWriteTokens,
          record.costUsd.toStringAsFixed(8),
          _csv(record.plan ?? ''),
        ].join(','),
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/quotaroom-records-${_stamp()}.csv');
    await file.writeAsString('\uFEFF${buffer.toString()}');
    return file;
  }

  Future<File> exportKeysCsv(
    int accountId,
    Map<String, String> keyNames,
  ) async {
    final stats = await usage.keyStats(accountId);
    final buffer = StringBuffer();
    buffer.writeln(
      'key_id,key_name,request_count,session_count,total_tokens,'
      'input_tokens,output_tokens,reasoning_tokens,cache_read_tokens,'
      'cache_write_tokens,cost_usd,last_used',
    );
    for (final stat in stats) {
      buffer.writeln(
        [
          _csv(stat.keyId),
          _csv(keyNames[stat.keyId] ?? ''),
          stat.requestCount,
          stat.sessionCount,
          stat.totalTokens,
          stat.totalInputTokens,
          stat.totalOutputTokens,
          stat.totalReasoningTokens,
          stat.cacheHitTokens,
          stat.cacheWriteTokens,
          stat.totalCostUsd.toStringAsFixed(8),
          _csv(
            stat.lastAt == null
                ? ''
                : DateFormat('yyyy-MM-dd HH:mm:ss')
                      .format(stat.lastAt!.toLocal()),
          ),
        ].join(','),
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/quotaroom-keys-${_stamp()}.csv');
    await file.writeAsString('\uFEFF${buffer.toString()}');
    return file;
  }

  /// Consistent SQLite snapshot via `VACUUM INTO`; does not include the
  /// session cookies, which live in Android Keystore-backed storage.
  Future<File> backupDatabase() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/quotaroom-backup-${_stamp()}.db');
    if (await file.exists()) {
      await file.delete();
    }
    final escaped = file.path.replaceAll("'", "''");
    try {
      await db.execute("VACUUM INTO '$escaped'");
    } catch (_) {
      // Android 7–9 ship SQLite older than 3.27 (no VACUUM INTO). Flush the
      // WAL and copy the database file as a best-effort fallback.
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      await File(db.path).copy(file.path);
    }
    return file;
  }

  Future<void> shareFile(File file, {required String text}) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text),
    );
  }

  Future<void> shareText(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }

  /// Writes picked backup bytes to a temporary file, restores, then removes it.
  Future<int> restoreUsageFromBytes(int accountId, List<int> bytes) async {
    if (bytes.length < 1024) {
      throw Exception('Backup file is empty');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/quotaroom-restore-${_stamp()}.db');
    await file.writeAsBytes(bytes, flush: true);
    try {
      return await restoreUsageInto(accountId, file.path);
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Temporary cleanup is best-effort.
      }
    }
  }

  /// Imports usage history from a QuotaRoom backup into [accountId].
  ///
  /// Backups never contain credentials and their account ids may not match the
  /// current install, so every backup account's records are merged into the
  /// signed-in account. Existing rows win on duplicate `usg_id`.
  Future<int> restoreUsageInto(int accountId, String backupPath) async {
    final file = File(backupPath);
    if (!await file.exists()) {
      throw Exception('Backup file not found');
    }
    final escaped = backupPath.replaceAll("'", "''");
    await db.execute("ATTACH DATABASE '$escaped' AS qr_restore");
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM qr_restore.sqlite_master WHERE type = 'table' "
        "AND name IN ('usage_records', 'accounts')",
      );
      if (tables.length < 2) {
        throw Exception('Not a QuotaRoom backup');
      }
      final columns = await db.rawQuery(
        'PRAGMA qr_restore.table_info(usage_records)',
      );
      final names = columns.map((row) => row['name'].toString()).toSet();
      const required = {
        'usg_id',
        'created_at',
        'created_ms',
        'model',
        'input_tokens',
        'output_tokens',
        'reasoning_tokens',
        'cache_read_tokens',
        'cache_write_5m_tokens',
        'cache_write_1h_tokens',
        'cost_raw',
        'cost_usd',
        'synced_at',
      };
      if (!names.containsAll(required)) {
        throw Exception('Unsupported backup schema');
      }
      // Backups produced before these columns existed must still restore.
      String optional(String name) => names.contains(name) ? name : 'NULL';
      final before =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM usage_records WHERE account_id = ?',
              [accountId],
            ),
          ) ??
          0;
      await db.rawInsert(
        '''
        INSERT OR IGNORE INTO usage_records
          (usg_id, account_id, created_at, created_ms, model, provider,
           input_tokens, output_tokens, reasoning_tokens, cache_read_tokens,
           cache_write_5m_tokens, cache_write_1h_tokens, cost_raw, cost_usd,
           key_id, session_id, plan, origin, synced_at)
        SELECT usg_id, ?, created_at, created_ms, model, ${optional('provider')},
           input_tokens, output_tokens, reasoning_tokens, cache_read_tokens,
           cache_write_5m_tokens, cache_write_1h_tokens, cost_raw, cost_usd,
           ${optional('key_id')}, ${optional('session_id')},
           ${optional('plan')}, 'restore', synced_at
        FROM qr_restore.usage_records
      ''',
        [accountId],
      );
      final after =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM usage_records WHERE account_id = ?',
              [accountId],
            ),
          ) ??
          0;
      await usage.refreshSyncTotals(accountId);
      return after - before;
    } finally {
      await db.execute('DETACH DATABASE qr_restore');
    }
  }

  static String _csv(String value) {
    var safe = value;
    if (safe.isNotEmpty && '=+-@\t\r'.contains(safe[0])) {
      // Prevent spreadsheet formula execution from server-provided values.
      safe = "'$safe";
    }
    return '"${safe.replaceAll('"', '""')}"';
  }

  static String _stamp() {
    return DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
  }
}
