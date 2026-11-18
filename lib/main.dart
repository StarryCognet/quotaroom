import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'core/desktop_shell.dart';
import 'core/platform.dart';
import 'data/account_repository.dart';
import 'data/app_database.dart';
import 'data/background_sync.dart';
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
  if (isDesktop) {
    // Desktop has no sqflite plugin; route every database call through FFI.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else {
    await initBackgroundSync();
  }
  // The native window must exist before the first frame so close-to-tray,
  // window bounds and hidden autostart work consistently. A desktop plugin
  // failure must not prevent the app from opening.
  try {
    await DesktopShell.instance.initialize();
  } catch (error) {
    debugPrint('QuotaRoom desktop shell init failed: $error');
  }
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
      ChangeNotifierProvider.value(value: state, child: const QuotaRoomApp()),
    );
  } catch (error, stack) {
    debugPrint('QuotaRoom init failed: $error\n$stack');
    runApp(FatalErrorApp(message: error.toString()));
  }
}
