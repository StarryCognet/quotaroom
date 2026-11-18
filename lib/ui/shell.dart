import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';

import '../core/formatters.dart';
import '../core/platform.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import 'pages/accounts_page.dart';
import 'pages/home_page.dart';
import 'pages/records_page.dart';
import 'pages/settings_page.dart';
import 'pages/stats_page.dart';
import 'widgets/app_logo.dart';
import 'widgets/update_dialog.dart';

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_autoCheckUpdate());
    });
  }

  Future<void> _autoCheckUpdate() async {
    if (!mounted) return;
    final state = context.read<AppState>();
    if (!state.hasLoggedInAccount) return;
    try {
      final info = await state.checkForUpdate();
      if (!mounted || info == null || !info.hasUpdate) return;
      if (state.isUpdateDismissed(info.latest)) return;
      await showUpdateDialog(context, state: state, info: info);
    } catch (_) {
      // Silent on startup; the settings page exposes manual retry.
    }
  }

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
    if (!supportsAndroidIntegrations) return;
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
        _selectTab(0);
        unawaited(_quickSync(state));
        break;
      case 'stats':
        _selectTab(1);
        break;
      case 'records':
        _selectTab(2);
        break;
    }
  }

  void _selectTab(int index) {
    if (!mounted || index == _index) return;
    setState(() => _index = index);
  }

  void _refreshShortcut() {
    final state = context.read<AppState>();
    if (state.syncing) return;
    unawaited(_manualSync());
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
    final wide = isDesktop && MediaQuery.sizeOf(context).width >= 840;
    final tabs = <({String label, IconData icon, IconData selected})>[
      (
        label: l10n.t('home'),
        icon: Icons.space_dashboard_outlined,
        selected: Icons.space_dashboard_rounded,
      ),
      (
        label: l10n.t('stats'),
        icon: Icons.bar_chart_rounded,
        selected: Icons.insert_chart_rounded,
      ),
      (
        label: l10n.t('recordsTab'),
        icon: Icons.receipt_long_outlined,
        selected: Icons.receipt_long_rounded,
      ),
      (
        label: l10n.t('accountsTab'),
        icon: Icons.manage_accounts_outlined,
        selected: Icons.manage_accounts_rounded,
      ),
      (
        label: l10n.t('settingsTab'),
        icon: Icons.settings_outlined,
        selected: Icons.settings_rounded,
      ),
    ];
    final content = PopScope(
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
          child: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _selectTab,
                  labelType: NavigationRailLabelType.all,
                  minWidth: 78,
                  groupAlignment: -0.85,
                  destinations: [
                    for (final tab in tabs)
                      NavigationRailDestination(
                        icon: Icon(tab.icon),
                        selectedIcon: Icon(tab.selected),
                        label: Text(tab.label),
                      ),
                  ],
                ),
              if (wide) const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 1240 : 980),
                    child: IndexedStack(index: _index, children: _pages),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _selectTab,
                destinations: [
                  for (final tab in tabs)
                    NavigationDestination(
                      icon: Icon(tab.icon),
                      selectedIcon: Icon(tab.selected),
                      label: tab.label,
                    ),
                ],
              ),
      ),
    );
    if (!isDesktop) return content;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            _selectTab(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            _selectTab(1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            _selectTab(2),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
            _selectTab(3),
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () =>
            _selectTab(4),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true):
            _refreshShortcut,
        const SingleActivator(LogicalKeyboardKey.f5): _refreshShortcut,
      },
      child: Focus(autofocus: true, child: content),
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
