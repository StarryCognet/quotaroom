import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../state/app_state.dart';
import '../pages/accounts_page.dart';
import '../pages/records_page.dart';
import '../pages/settings_page.dart';
import '../pages/stats_page.dart';
import '../widgets/update_dialog.dart';
import 'app_glyphs.dart';
import 'keep_alive_page.dart';
import 'prism_home_page.dart';

/// FlClash-style app frame: a collapsible sidebar on desktop, a floating dock
/// on phones, with prism_ui's floating app bar and surface levels.
class PrismShell extends StatefulWidget {
  const PrismShell({super.key});

  @override
  State<PrismShell> createState() => _PrismShellState();
}

class _PrismShellState extends State<PrismShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tabsController;
  int _lastIndex = 0;
  bool _sidebarExpanded = true;
  bool _quickActionsReady = false;
  String? _shortcutLanguage;

  List<Widget> get _pages => const [
    PrismHomePage(),
    StatsPage(),
    RecordsPage(),
    AccountsPage(),
    SettingsPage(),
  ];

  List<({Glyph glyph, String label})> get _navItems {
    final l10n = context.read<AppState>().l10n;
    return [
      (glyph: AppGlyphs.dashboard, label: l10n.t('home')),
      (glyph: AppGlyphs.dataUsage, label: l10n.t('stats')),
      (glyph: AppGlyphs.requests, label: l10n.t('recordsTab')),
      (glyph: AppGlyphs.account, label: l10n.t('accountsTab')),
      (glyph: AppGlyphs.settings, label: l10n.t('settingsTab')),
    ];
  }

  @override
  void initState() {
    super.initState();
    _tabsController = TabController(length: 5, vsync: this);
    _tabsController.addListener(_onTabsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_autoCheckUpdate());
    });
  }

  void _onTabsChanged() {
    if (!mounted || _tabsController.index == _lastIndex) return;
    _lastIndex = _tabsController.index;
    setState(() {});
  }

  @override
  void dispose() {
    _tabsController.dispose();
    super.dispose();
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
      // Silent on startup; settings exposes a manual retry.
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
    switch (type) {
      case 'sync':
        _selectTab(0);
        unawaited(_sync());
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
    if (!mounted || index == _tabsController.index) return;
    _tabsController.animateTo(index);
  }

  Future<void> _sync() async {
    final state = context.read<AppState>();
    if (state.syncing) return;
    final l10n = state.l10n;
    final result = await state.syncNow();
    if (!mounted) return;
    final banner = BannerHost.maybeOf(context);
    banner?.show(
      result.ok
          ? '${l10n.t('syncDone')} · +${result.inserted}'
          : '${l10n.t('syncFailed')}: ${result.error ?? ''}',
      level: result.ok ? BannerLevel.success : BannerLevel.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colorScheme = context.colorScheme;
    final isMobile = ViewScope.isMobileOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final dark = Theme.brightnessOf(context) == Brightness.dark;
    final tabs = _navItems;
    final index = _tabsController.index;
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

    final body = PrismScaffold(
      bar: ScaffoldBar(
        isCompact: false,
        listenable: const AlwaysStoppedAnimation<double>(0),
        loading: const AlwaysStoppedAnimation<bool>(false),
        builder: (context) => ColoredBox(
          color: SurfaceLevel.page.colorOf(context.colorScheme),
          child: AppBar(
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.15),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    tabs[index].label,
                    key: ValueKey(index),
                    style: AppTextStyle.pageTitle
                        .of(context)
                        .copyWith(
                          color: colorScheme.onSurface,
                          letterSpacing: -0.4,
                        ),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'QuotaRoom · $subtitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: state.syncing ? null : _sync,
                tooltip: l10n.t('refresh'),
                icon: state.syncing
                    ? ActivityIndicator(size: 18, color: colorScheme.primary)
                    : const GlyphIcon(AppGlyphs.sync, size: 22),
              ),
              IconButton(
                onPressed: state.toggleTheme,
                tooltip: dark ? l10n.t('themeLight') : l10n.t('themeDark'),
                icon: GlyphIcon(
                  dark ? AppGlyphs.sun : AppGlyphs.pureBlack,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabsController,
        physics: const NeverScrollableScrollPhysics(),
        children: [for (final page in _pages) KeepAlivePage(child: page)],
      ),
    );

    final dockInset = isMobile
        ? (NavigationDock.insetOf(context) -
                  MediaQuery.paddingOf(context).bottom)
              .clamp(0.0, double.infinity)
              .toDouble()
        : 0.0;
    final content = isMobile
        ? Stack(
            children: [
              Positioned.fill(
                child: BottomInsetScope(inset: dockInset, child: body),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: NavigationDock(
                  destinations: [
                    for (final tab in tabs)
                      NavigationDockDestination(
                        glyph: tab.glyph,
                        label: tab.label,
                      ),
                  ],
                  selectedIndex: index,
                  onSelected: _selectTab,
                ),
              ),
            ],
          )
        : Row(
            children: [
              NavigationSidebar(
                destinations: [
                  for (final tab in tabs)
                    SidebarDestination(glyph: tab.glyph, label: tab.label),
                ],
                selectedIndex: index,
                expanded: _sidebarExpanded && width >= 900,
                onSelected: _selectTab,
                onToggle: width >= 900
                    ? () => setState(() => _sidebarExpanded = !_sidebarExpanded)
                    : null,
              ),
              Expanded(child: body),
            ],
          );

    final shell = Surface(
      color: SurfaceLevel.page.colorOf(colorScheme),
      child: PopScope(
        canPop: index == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && index != 0) {
            _selectTab(0);
          }
        },
        child: content,
      ),
    );

    if (isMobile) return shell;
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
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            unawaited(_sync()),
        const SingleActivator(LogicalKeyboardKey.f5): () => unawaited(_sync()),
      },
      child: Focus(autofocus: true, child: shell),
    );
  }
}
