import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import 'pages/accounts_page.dart';
import 'pages/home_page.dart';
import 'pages/records_page.dart';
import 'pages/settings_page.dart';
import 'pages/stats_page.dart';
import 'widgets/app_logo.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _quickActionsReady = false;
  String? _shortcutLanguage;

  static const List<Widget> _pages = [
    HomePage(),
    StatsPage(),
    RecordsPage(),
    AccountsPage(),
    SettingsPage(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AppState>();
    if (_shortcutLanguage != state.language) {
      _shortcutLanguage = state.language;
      unawaited(_setupQuickActions(state));
    }
  }

  Future<void> _setupQuickActions(AppState state) async {
    const quickActions = QuickActions();
    try {
      if (!_quickActionsReady) {
        await quickActions.initialize(_handleQuickAction);
        _quickActionsReady = true;
      }
      final zh = state.language != 'en';
      await quickActions.setShortcutItems([
        ShortcutItem(
          type: 'sync',
          localizedTitle: zh ? '立即同步' : 'Sync now',
          localizedSubtitle: zh ? '刷新额度与用量' : 'Refresh quota and usage',
        ),
        ShortcutItem(
          type: 'stats',
          localizedTitle: zh ? '查看统计' : 'Statistics',
          localizedSubtitle: zh ? '用量趋势与费用' : 'Usage trends and cost',
        ),
        ShortcutItem(
          type: 'records',
          localizedTitle: zh ? '使用记录' : 'Usage records',
          localizedSubtitle: zh ? '按 Key 查看明细' : 'Details by API key',
        ),
      ]);
    } catch (e) {
      debugPrint('QuotaRoom quick actions failed: $e');
    }
  }

  void _handleQuickAction(String type) {
    if (!mounted) return;
    final state = context.read<AppState>();
    switch (type) {
      case 'sync':
        setState(() => _index = 0);
        unawaited(_quickSync(state));
        break;
      case 'stats':
        setState(() => _index = 1);
        break;
      case 'records':
        setState(() => _index = 2);
        break;
    }
  }

  Future<void> _quickSync(AppState state) async {
    final result = await state.syncNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? state.l10n.t('syncDone')
              : '${state.l10n.t('syncFailed')}: ${result.error ?? ''}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colors = context.colors;
    final sync = state.dashboard?.sync;
    final lastSync = fmtRelative(
      sync?.lastSyncAt,
      never: l10n.t('never'),
      justNow: l10n.t('justNow'),
      minAgo: l10n.t('minAgo'),
      hrAgo: l10n.t('hrAgo'),
      dayAgo: l10n.t('dayAgo'),
    );
    final subtitle = state.hasLoggedInAccount
        ? '${l10n.t('lastSync')} $lastSync · ${fmtInt(sync?.totalRecords ?? 0)} ${l10n.t('records')}'
        : l10n.t('notLoggedIn');
    final syncDot = state.errorMessage != null
        ? colors.red
        : switch (state.dashboard?.sync.lastSyncStatus) {
            'ok' => colors.green,
            'partial' => colors.amber,
            'error' => colors.red,
            _ => colors.text3,
          };
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) {
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 56,
          titleSpacing: 14,
          title: Row(
            children: [
              const AppLogo(size: 29),
              const SizedBox(width: 9),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QuotaRoom',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colors.text,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: syncDot,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: colors.text3),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: l10n.t('refresh'),
              onPressed: state.syncing ? null : _manualSync,
              icon: state.syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
            ),
            IconButton(
              tooltip: dark ? l10n.t('themeLight') : l10n.t('themeDark'),
              onPressed: state.toggleTheme,
              icon: Icon(
                dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              ),
            ),
            const SizedBox(width: 4),
          ],
          bottom: state.progress.running
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: IndexedStack(index: _index, children: _pages),
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.space_dashboard_outlined),
              selectedIcon: const Icon(Icons.space_dashboard_rounded),
              label: l10n.t('home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.bar_chart_rounded),
              selectedIcon: const Icon(Icons.insert_chart_rounded),
              label: l10n.t('stats'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long_rounded),
              label: l10n.t('recordsTab'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.manage_accounts_outlined),
              selectedIcon: const Icon(Icons.manage_accounts_rounded),
              label: l10n.t('accountsTab'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings_rounded),
              label: l10n.t('settingsTab'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manualSync() async {
    final state = context.read<AppState>();
    final l10n = state.l10n;
    final result = await state.syncNow();
    if (!mounted) return;
    final text = result.ok
        ? '${l10n.t('syncDone')} · +${result.inserted}'
        : '${l10n.t('syncFailed')}: ${result.error ?? ''}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
