import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quotaroom/data/app_database.dart';
import 'package:quotaroom/data/export_service.dart';
import 'package:quotaroom/data/models.dart';
import 'package:quotaroom/data/usage_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('restore merges backup usage into the target account', () async {
    final dir = await Directory.systemTemp.createTemp('quotaroom-restore-');
    AppDatabase? source;
    AppDatabase? target;
    try {
      final sourcePath = p.join(dir.path, 'source.db');
      final backupPath = p.join(dir.path, 'backup.db');
      final targetPath = p.join(dir.path, 'target.db');

      source = await AppDatabase.open(
        path: sourcePath,
        factory: databaseFactoryFfi,
      );
      final sourceRepo = UsageRepository(source.db);
      final now = DateTime.now();
      await sourceRepo.insertUsageRecords([
        UsageRecord(
          usgId: 'restore-a',
          createdAt: now,
          model: 'deepseek-v4',
          inputTokens: 100,
          outputTokens: 20,
          reasoningTokens: 5,
          costRaw: 1000,
          costUsd: 0.01,
          keyId: 'sk_a',
          sessionId: 'sess_a',
        ),
        UsageRecord(
          usgId: 'restore-b',
          createdAt: now.subtract(const Duration(minutes: 1)),
          model: 'kimi-k3',
          inputTokens: 200,
          outputTokens: 30,
          reasoningTokens: 8,
          costRaw: 2000,
          costUsd: 0.02,
          keyId: 'sk_b',
          sessionId: 'sess_b',
        ),
      ], 1);
      await source.db.execute("VACUUM INTO '$backupPath'");
      await source.close();
      source = null;

      target = await AppDatabase.open(
        path: targetPath,
        factory: databaseFactoryFfi,
      );
      final targetRepo = UsageRepository(target.db);
      await targetRepo.insertUsageRecords([
        UsageRecord(
          usgId: 'existing',
          createdAt: now,
          model: 'existing',
          inputTokens: 1,
          outputTokens: 1,
          costRaw: 0,
          costUsd: 0,
        ),
      ], 1);

      final service = ExportService(db: target.db, usage: targetRepo);
      final restored = await service.restoreUsageInto(1, backupPath);
      expect(restored, 2);
      final totals = await targetRepo.totals(1, 'all');
      expect(totals.requestCount, 3);
      expect(totals.totalTokens, 365);

      // A second restore is idempotent because usg_id is the primary key.
      expect(await service.restoreUsageInto(1, backupPath), 0);
    } finally {
      if (source != null) await source.close();
      if (target != null) await target.close();
      await dir.delete(recursive: true);
    }
  });

  test('restored history is protected from automatic retention', () async {
    final dir = await Directory.systemTemp.createTemp('quotaroom-retention-');
    AppDatabase? source;
    AppDatabase? target;
    try {
      final sourcePath = p.join(dir.path, 'source.db');
      final backupPath = p.join(dir.path, 'backup.db');
      final targetPath = p.join(dir.path, 'target.db');

      source = await AppDatabase.open(
        path: sourcePath,
        factory: databaseFactoryFfi,
      );
      final sourceRepo = UsageRepository(source.db);
      await sourceRepo.insertUsageRecords([
        UsageRecord(
          usgId: 'old-restored',
          createdAt: DateTime.now().subtract(const Duration(days: 40)),
          model: 'old-model',
          inputTokens: 10,
          outputTokens: 2,
          costRaw: 100,
          costUsd: 0.001,
        ),
      ], 1);
      await source.db.execute("VACUUM INTO '$backupPath'");
      await source.close();
      source = null;

      target = await AppDatabase.open(
        path: targetPath,
        factory: databaseFactoryFfi,
      );
      final targetRepo = UsageRepository(target.db);
      final service = ExportService(db: target.db, usage: targetRepo);
      expect(await service.restoreUsageInto(1, backupPath), 1);

      expect(await targetRepo.pruneOldRecords(1, 1), 0);
      final totals = await targetRepo.totals(1, 'all');
      expect(totals.requestCount, 1);
    } finally {
      if (source != null) await source.close();
      if (target != null) await target.close();
      await dir.delete(recursive: true);
    }
  });
}
