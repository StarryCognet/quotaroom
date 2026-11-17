import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

String nowIso() => DateTime.now().toUtc().toIso8601String();

/// SQLite storage mirroring the desktop app's schema, with an extra
/// `created_ms` column so date/time bucketing never depends on SQLite's
/// ability to parse the `...Z` suffix.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static Future<AppDatabase> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await getDatabasesPath(), 'quotaroom.db');
    final database = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
      ),
    );
    final result = AppDatabase._(database);
    await result._seed();
    return result;
  }

  static Future<void> _createSchema(Database db) async {
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
    await db.execute(
      'CREATE INDEX idx_usage_account_ms ON usage_records(account_id, created_ms DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_usage_account_model ON usage_records(account_id, model)',
    );
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
  }

  Future<void> _seed() async {
    await db.transaction((txn) async {
      final settings = await txn.query('settings', limit: 1);
      if (settings.isEmpty) {
        await txn.insert('settings', {
          'id': 1,
          'payload': '{}',
          'updated_at': nowIso(),
        });
      }
      final accounts = await txn.rawQuery('SELECT COUNT(*) AS c FROM accounts');
      final count = (accounts.first['c'] as num?)?.toInt() ?? 0;
      if (count == 0) {
        final now = nowIso();
        await txn.insert('accounts', {
          'name': 'Default',
          'workspace_id': 'Default',
          'created_at': now,
          'updated_at': now,
        });
      }
    });
  }

  Future<void> close() => db.close();
}
