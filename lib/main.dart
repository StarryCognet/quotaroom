import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/account_repository.dart';
import 'data/app_database.dart';
import 'data/fx_service.dart';
import 'data/opencode_api.dart';
import 'data/prefs.dart';
import 'data/settings_repository.dart';
import 'data/sync_service.dart';
import 'data/token_store.dart';
import 'data/usage_repository.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final database = await AppDatabase.open();
    final prefs = await Prefs.load();
    final api = OpenCodeApi();
    final settingsRepo = SettingsRepository(database.db);
    final tokens = SecureTokenStore();
    final accountRepo = AccountRepository(
      db: database.db,
      tokens: tokens,
      settings: settingsRepo,
    );
    final usageRepo = UsageRepository(database.db);
    final syncService = SyncService(
      accounts: accountRepo,
      usage: usageRepo,
      settings: settingsRepo,
      api: api,
    );
    final fxService = FxService(settings: settingsRepo, api: api);
    final state = AppState(
      db: database,
      api: api,
      prefs: prefs,
      settingsRepo: settingsRepo,
      accountRepo: accountRepo,
      usageRepo: usageRepo,
      syncService: syncService,
      fxService: fxService,
    );
    unawaited(state.init());
    runApp(
      ChangeNotifierProvider.value(
        value: state,
        child: const QuotaRoomApp(),
      ),
    );
  } catch (error, stack) {
    debugPrint('QuotaRoom init failed: $error\n$stack');
    runApp(FatalErrorApp(message: error.toString()));
  }
}
