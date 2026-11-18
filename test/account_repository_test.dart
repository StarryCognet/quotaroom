import 'package:flutter_test/flutter_test.dart';
import 'package:quotaroom/data/account_repository.dart';
import 'package:quotaroom/data/app_database.dart';
import 'package:quotaroom/data/settings_repository.dart';
import 'package:quotaroom/data/token_store.dart';
import 'package:quotaroom/data/usage_repository.dart';
import 'package:quotaroom/data/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDb;
  late AccountRepository accounts;
  late UsageRepository usage;
  late MemoryTokenStore tokens;

  setUp(() async {
    appDb = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final settings = SettingsRepository(appDb.db);
    tokens = MemoryTokenStore();
    accounts = AccountRepository(
      db: appDb.db,
      tokens: tokens,
      settings: settings,
    );
    usage = UsageRepository(appDb.db);
    await tokens.write(1, 'st_same');
    await accounts.saveWorkspace(1, hint: 'wrk_one', resolved: 'wrk_one');
    await accounts.setActive(1);
  });

  tearDown(() async {
    await appDb.close();
  });

  test('same token in another workspace becomes a separate account', () async {
    final second = await accounts.addAccount(
      token: 'st_same',
      workspaceId: 'wrk_two',
      name: 'Second workspace',
    );
    expect(second.id, isNot(1));
    expect(second.resolvedWorkspaceId, 'wrk_two');
    expect(await appDb.db.query('accounts'), hasLength(2));

    // Same token+workspace is idempotent.
    final again = await accounts.addAccount(
      token: 'st_same',
      workspaceId: 'wrk_two',
    );
    expect(again.id, second.id);
    expect(await appDb.db.query('accounts'), hasLength(2));

    // The first account still owns its own workspace and rows.
    final first = await accounts.getAccount(1);
    expect(first!.resolvedWorkspaceId, 'wrk_one');
    await usage.insertUsageRecords([
      UsageRecord(
        usgId: 'one',
        createdAt: DateTime.now(),
        model: 'm',
        inputTokens: 1,
        outputTokens: 1,
        costRaw: 0,
        costUsd: 0,
      ),
    ], 1);
    await usage.insertUsageRecords([
      UsageRecord(
        usgId: 'two',
        createdAt: DateTime.now(),
        model: 'm',
        inputTokens: 1,
        outputTokens: 1,
        costRaw: 0,
        costUsd: 0,
      ),
    ], second.id);
    expect((await usage.totals(1, 'all')).requestCount, 1);
    expect((await usage.totals(second.id, 'all')).requestCount, 1);
  });

  test('same token and workspace returns the existing account', () async {
    final existing = await accounts.addAccount(
      token: 'st_same',
      workspaceId: 'wrk_one',
      name: 'Renamed',
    );
    expect(existing.id, 1);
    expect(existing.name, 'Renamed');
    expect(await appDb.db.query('accounts'), hasLength(1));
  });
}
