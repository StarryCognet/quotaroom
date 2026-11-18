import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quotaroom/data/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('opens a v1 database and adds the restore-origin column', () async {
    final dir = await Directory.systemTemp.createTemp('quotaroom-migrate-');
    final path = p.join(dir.path, 'v1.db');
    try {
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE accounts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL DEFAULT 'Default',
                workspace_id TEXT NOT NULL DEFAULT 'Default',
                resolved_workspace_id TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE usage_records (
                usg_id TEXT PRIMARY KEY,
                account_id INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                created_ms INTEGER NOT NULL,
                model TEXT NOT NULL,
                provider TEXT,
                input_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                reasoning_tokens INTEGER NOT NULL DEFAULT 0,
                cache_read_tokens INTEGER NOT NULL DEFAULT 0,
                cache_write_5m_tokens INTEGER NOT NULL DEFAULT 0,
                cache_write_1h_tokens INTEGER NOT NULL DEFAULT 0,
                cost_raw INTEGER NOT NULL,
                cost_usd REAL NOT NULL,
                key_id TEXT,
                session_id TEXT,
                plan TEXT,
                synced_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE usage_sync_state (
                account_id INTEGER PRIMARY KEY,
                last_sync_at TEXT,
                last_sync_status TEXT,
                last_sync_error TEXT,
                last_inserted_count INTEGER NOT NULL DEFAULT 0,
                deepest_page_fetched INTEGER NOT NULL DEFAULT -1,
                total_records INTEGER NOT NULL DEFAULT 0,
                oldest_record_at TEXT,
                newest_record_at TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE settings (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                payload TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
            await db.insert('settings', {
              'id': 1,
              'payload': '{}',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            });
            await db.insert('accounts', {
              'name': 'Old',
              'workspace_id': 'Default',
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            });
          },
        ),
      );
      await old.close();

      final upgraded = await AppDatabase.open(
        path: path,
        factory: databaseFactoryFfi,
      );
      try {
        final columns = await upgraded.db.rawQuery(
          'PRAGMA table_info(usage_records)',
        );
        expect(columns.map((row) => row['name']), contains('origin'));
        final syncColumns = await upgraded.db.rawQuery(
          'PRAGMA table_info(usage_sync_state)',
        );
        expect(
          syncColumns.map((row) => row['name']),
          contains('last_success_at'),
        );
        final tables = await upgraded.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        );
        expect(tables.map((row) => row['name']), contains('sync_lease'));
      } finally {
        await upgraded.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
