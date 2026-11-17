import 'package:flutter_test/flutter_test.dart';
import 'package:quotaroom/data/app_database.dart';
import 'package:quotaroom/data/models.dart';
import 'package:quotaroom/data/usage_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

UsageRecord _rec({
  required String id,
  required DateTime at,
  String model = 'deepseek-v4',
  String session = 's1',
  String key = 'sk_1',
  int input = 100,
  int output = 50,
  int reasoning = 10,
  int cacheRead = 0,
  int cacheWrite = 0,
  double cost = 0.001,
}) {
  return UsageRecord(
    usgId: id,
    createdAt: at,
    model: model,
    inputTokens: input,
    outputTokens: output,
    reasoningTokens: reasoning,
    cacheReadTokens: cacheRead,
    cacheWrite5mTokens: cacheWrite,
    costRaw: (cost * 100000000).round(),
    costUsd: cost,
    sessionId: session,
    keyId: key,
    plan: 'go',
  );
}

void main() {
  sqfliteFfiInit();
  late AppDatabase appDb;
  late UsageRepository repo;
  const accountId = 1;

  setUp(() async {
    appDb = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repo = UsageRepository(appDb.db);
  });

  tearDown(() async {
    await appDb.close();
  });

  test('totals and hit rate follow desktop formulas', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'a', at: now, input: 100, cacheRead: 300, cacheWrite: 50),
      _rec(id: 'b', at: now, input: 200, cacheRead: 100),
    ], accountId);
    final totals = await repo.totals(accountId, 'all');
    expect(totals.requestCount, 2);
    expect(totals.totalInputTokens, 100 + 300 + 50 + 200 + 100);
    expect(totals.uncachedInputTokens, 300);
    expect(totals.cacheHitTokens, 400);
    expect(totals.cacheWriteTokens, 50);
    expect(totals.totalOutputTokens, 100);
    expect(totals.totalReasoningTokens, 20);
    // 400 / (400 + 300) = 57.14%
    expect(totals.hitRate, closeTo(57.14, 0.01));
  });

  test('today range excludes yesterday', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'today', at: now),
      _rec(id: 'old', at: now.subtract(const Duration(hours: 25))),
    ], accountId);
    expect((await repo.totals(accountId, 'today')).requestCount, 1);
    expect((await repo.totals(accountId, '7d')).requestCount, 2);
    expect((await repo.totals(accountId, 'all')).requestCount, 2);
  });

  test('model stats group and order by token volume', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'a', at: now, model: 'small', input: 10),
      _rec(id: 'b', at: now, model: 'big', input: 1000),
      _rec(id: 'c', at: now, model: 'big', input: 500),
    ], accountId);
    final stats = await repo.modelStats(accountId, 'all');
    expect(stats, hasLength(2));
    expect(stats.first.model, 'big');
    expect(stats.first.requestCount, 2);
    expect(stats.first.totalInputTokens, 1500);
  });

  test('daily stats and 24-hour trend use local buckets', () async {
    final now = DateTime.now();
    final noon = DateTime(now.year, now.month, now.day, 12);
    await repo.insertUsageRecords([
      _rec(id: 'a', at: noon, input: 10, output: 5),
    ], accountId);
    final daily = await repo.dailyStats(accountId, 7);
    expect(daily, hasLength(1));
    expect(daily.first.date, hasLength(10));
    expect(daily.first.requestCount, 1);
    final trend = await repo.todayTrend(accountId);
    expect(trend, hasLength(24));
    expect(trend[12].input, 10);
    expect(trend[12].output, 5);
    expect(trend[11].input, 0);
  });

  test('sessions group by session, then key, and blank key ids', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'a', at: now, session: 's1', key: 'sk_a', input: 100),
      _rec(id: 'b', at: now, session: 's1', key: 'sk_a', input: 50),
      _rec(id: 'c', at: now, session: '', key: 'sk_b', input: 10),
      _rec(id: 'd', at: now, session: '', key: '', input: 5),
    ], accountId);
    final sessions = await repo.sessionsPage(accountId, pageSize: 10);
    expect(sessions.total, 3);
    final s1 = sessions.records.firstWhere((s) => s.sessionId == 's1');
    expect(s1.requestCount, 2);
    expect(s1.totalInputTokens, 150);
    expect(sessions.records.any((s) => s.sessionId.isEmpty), isTrue);
  });

  test('key stats aggregate each key and sort by token volume', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'a', at: now, key: 'sk_a', input: 100, output: 50, reasoning: 0),
      _rec(id: 'b', at: now, key: 'sk_a', input: 50, output: 20, reasoning: 0),
      _rec(
        id: 'c',
        at: now,
        key: 'sk_b',
        input: 500,
        output: 100,
        reasoning: 0,
      ),
      _rec(id: 'd', at: now, key: '', input: 10, output: 5, reasoning: 0),
    ], accountId);
    final stats = await repo.keyStats(accountId);
    expect(stats, hasLength(3));
    expect(stats.first.keyId, 'sk_b');
    expect(stats.first.totalTokens, 600);
    final skA = stats.firstWhere((stat) => stat.keyId == 'sk_a');
    expect(skA.requestCount, 2);
    expect(skA.totalInputTokens, 150);
    expect(skA.totalOutputTokens, 70);
    final unassigned = stats.firstWhere((stat) => stat.keyId.isEmpty);
    expect(unassigned.totalTokens, 15);
  });

  test('records page filters by model and paginates', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'a', at: now, model: 'm1'),
      _rec(id: 'b', at: now.subtract(const Duration(minutes: 1)), model: 'm2'),
      _rec(id: 'c', at: now.subtract(const Duration(minutes: 2)), model: 'm2'),
    ], accountId);
    final all = await repo.recordsPage(accountId, page: 1, pageSize: 2);
    expect(all.total, 3);
    expect(all.records, hasLength(2));
    expect(all.records.first.usgId, 'a');
    final filtered = await repo.recordsPage(accountId, model: 'm2');
    expect(filtered.total, 2);
    expect(await repo.models(accountId), ['m1', 'm2']);
  });

  test('duplicate usg_id refreshes usage fields without new row', () async {
    final now = DateTime.now();
    expect(
      await repo.insertUsageRecords([
        _rec(id: 'a', at: now, input: 100),
      ], accountId),
      1,
    );
    expect(
      await repo.insertUsageRecords([
        _rec(id: 'a', at: now, input: 999, output: 222),
      ], accountId),
      0,
    );
    final page = await repo.recordsPage(accountId);
    expect(page.total, 1);
    expect(page.records.first.inputTokens, 999);
    expect(page.records.first.outputTokens, 222);
  });

  test('prune removes rows outside the window', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'old', at: now.subtract(const Duration(days: 40))),
      _rec(id: 'new', at: now),
    ], accountId);
    final removed = await repo.pruneOldRecords(accountId, 30);
    expect(removed, 1);
    expect((await repo.recordsPage(accountId)).total, 1);
  });

  test('sync state accumulates inserted count and refreshes totals', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'a', at: now),
      _rec(id: 'b', at: now),
    ], accountId);
    await repo.updateSyncState(accountId, status: 'ok', inserted: 2);
    final state = await repo.syncState(accountId);
    expect(state.lastSyncStatus, 'ok');
    expect(state.lastInsertedCount, 2);
    expect(state.totalRecords, 2);
    expect(state.newestRecordAt, isNotNull);
    expect(state.oldestRecordAt, isNotNull);
  });

  test('totalsBetween uses a half-open time window', () async {
    final base = DateTime.now().subtract(const Duration(hours: 5));
    await repo.insertUsageRecords([
      _rec(id: 'before', at: base.subtract(const Duration(minutes: 1))),
      _rec(id: 'start', at: base, input: 10),
      _rec(id: 'inside', at: base.add(const Duration(hours: 1)), input: 20),
      _rec(id: 'end', at: base.add(const Duration(hours: 2)), input: 40),
    ], accountId);
    final totals = await repo.totalsBetween(
      accountId,
      fromMs: base.millisecondsSinceEpoch,
      toMs: base.add(const Duration(hours: 2)).millisecondsSinceEpoch,
    );
    expect(totals.requestCount, 2);
    expect(totals.totalInputTokens, 30);
  });

  test('model-key matrix groups and limits by token volume', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'a', at: now, model: 'm1', key: 'sk_a', input: 100),
      _rec(id: 'b', at: now, model: 'm1', key: 'sk_a', input: 50),
      _rec(id: 'c', at: now, model: 'm1', key: 'sk_b', input: 900),
      _rec(id: 'd', at: now, model: 'm2', key: 'sk_b', input: 300),
    ], accountId);
    final stats = await repo.modelKeyStats(accountId, 'all');
    expect(stats, hasLength(3));
    expect(stats.first.model, 'm1');
    expect(stats.first.keyId, 'sk_b');
    expect(stats.first.totalTokens, 960);
    final topOne = await repo.modelKeyStats(accountId, 'all', limit: 1);
    expect(topOne, hasLength(1));
  });

  test('top expensive requests order by cost', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'cheap', at: now, cost: 0.001),
      _rec(id: 'pricey', at: now, cost: 0.5),
      _rec(id: 'middle', at: now, cost: 0.05),
    ], accountId);
    final top = await repo.topExpensive(accountId, 'all', limit: 2);
    expect(top.map((record) => record.usgId), ['pricey', 'middle']);
  });

  test('key daily tokens zero-fills seven days per key', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    await repo.insertUsageRecords([
      _rec(id: 'today', at: today, key: 'sk_a', input: 100, output: 20),
      _rec(
        id: 'old',
        at: today.subtract(const Duration(days: 3)),
        key: 'sk_a',
        input: 50,
      ),
      _rec(
        id: 'out',
        at: today.subtract(const Duration(days: 9)),
        key: 'sk_old',
        input: 70,
      ),
    ], accountId);
    final series = await repo.keyDailyTokens(accountId);
    expect(series.keys, contains('sk_a'));
    expect(series.keys, isNot(contains('sk_old')));
    expect(series['sk_a'], hasLength(7));
    expect(series['sk_a']!.last, 130);
    expect(series['sk_a']![3], 110);
    expect(series['sk_a']!.first, 0);
  });

  test('records page filters by key and free-text query', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'a', at: now, model: 'qwen3', key: 'sk_a', session: 'sess_1'),
      _rec(id: 'b', at: now, model: 'glm', key: 'sk_b', session: 'sess_2'),
      _rec(id: 'c', at: now, model: 'glm', key: '', session: 'sess_3'),
    ], accountId);
    final byKey = await repo.recordsPage(accountId, keyId: 'sk_a');
    expect(byKey.records.single.usgId, 'a');
    final unassigned = await repo.recordsPage(accountId, keyId: '');
    expect(unassigned.records.single.usgId, 'c');
    final query = await repo.recordsPage(accountId, query: 'sess_2');
    expect(query.records.single.usgId, 'b');
    final modelQuery = await repo.recordsPage(accountId, query: 'qwen');
    expect(modelQuery.total, 1);
  });
}
