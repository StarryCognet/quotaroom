import 'package:flutter_test/flutter_test.dart';
import 'package:quotaroom/data/app_database.dart';
import 'package:quotaroom/data/settings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('concurrent settings updates do not overwrite each other', () async {
    final appDb = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    try {
      final settings = SettingsRepository(appDb.db);
      await Future.wait([
        settings.addSyncLog({'at': 'now', 'ok': true}),
        settings.mergeKeyNames({'sk_a': 'Key A'}),
        settings.setActiveAccountId(1),
      ]);

      expect(await settings.getSyncLog(), hasLength(1));
      expect((await settings.getKeyNames())['sk_a'], 'Key A');
      expect(await settings.activeAccountId(), 1);
    } finally {
      await appDb.close();
    }
  });
}
