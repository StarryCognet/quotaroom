import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../core/desktop_shell.dart';
import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/package_info_cache.dart';
import '../../core/platform.dart';
import '../../data/export_service.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../prism/app_glyphs.dart';
import '../prism/prism_login_page.dart';
import '../prism/prism_route.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/export_helper.dart';
import '../widgets/update_dialog.dart';
import 'about_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final scheme = context.colorScheme;
    final account = state.activeAccount;
    final sync = state.dashboard?.sync;
    final lastSync = fmtRelative(
      sync?.lastSuccessOrAttempt,
      never: l10n.t('never'),
      justNow: l10n.t('justNow'),
      minAgo: l10n.t('minAgo'),
      hrAgo: l10n.t('hrAgo'),
      dayAgo: l10n.t('dayAgo'),
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        context.appBarInset + 8,
        16,
        24 + context.bottomInset,
      ),
      children: [
        SyncBanner(progress: state.progress, l10n: l10n),
        _SettingsCard(
          title: l10n.t('setAccount'),
          children: [
            _InfoRow(
              label: l10n.t('setLoginState'),
              value: account?.hasToken == true
                  ? l10n.t('loggedIn')
                  : l10n.t('notLoggedIn'),
              valueColor: account?.hasToken == true
                  ? const Color(0xFF16A34A)
                  : scheme.error,
            ),
            _InfoRow(label: l10n.t('accountName'), value: account?.name ?? '—'),
            _InfoRow(
              label: l10n.t('workspace'),
              value:
                  maskWorkspace(
                    account?.resolvedWorkspaceId ?? account?.workspaceHint,
                  ).isEmpty
                  ? '—'
                  : maskWorkspace(
                      account?.resolvedWorkspaceId ?? account?.workspaceHint,
                    ),
            ),
            _ActionRow(
              label: l10n.t('addUser'),
              subtitle: l10n.t('addUserTip'),
              glyph: AppGlyphs.addCircle,
              onTap: () => _openLogin(context, relogin: false),
            ),
            _ActionRow(
              label: l10n.t('relogin'),
              glyph: AppGlyphs.key,
              onTap: () => _openLogin(context, relogin: true),
            ),
            _ActionRow(
              label: l10n.t('setLogout'),
              subtitle: l10n.t('logoutDesc'),
              glyph: AppGlyphs.lock,
              danger: true,
              onTap: () => _logout(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          title: l10n.t('setAutoSync'),
          children: [
            _SwitchRow(
              title: l10n.t('autoSync'),
              subtitle: l10n.t('autoSyncDesc'),
              value: state.settings.autoSync,
              onChanged: (value) => state.updateSettings(autoSync: value),
            ),
            _PillRow<int>(
              title: l10n.t('syncInterval'),
              subtitle: l10n.t('syncIntervalDesc'),
              value: state.settings.syncIntervalSec,
              options: [
                PillOption(value: 60, label: l10n.t('min1')),
                PillOption(value: 300, label: l10n.t('min5')),
                PillOption(value: 900, label: l10n.t('min15')),
                PillOption(value: 1800, label: l10n.t('min30')),
              ],
              onChanged: (value) =>
                  state.updateSettings(syncIntervalSec: value),
            ),
            _PillRow<int?>(
              title: l10n.t('syncRange'),
              subtitle: l10n.t('syncRangeDesc'),
              value: state.settings.windowDays,
              options: [
                PillOption(value: 30, label: l10n.t('d30short')),
                PillOption(value: 60, label: l10n.t('d60')),
                PillOption(value: 90, label: l10n.t('d90')),
                PillOption(value: 180, label: l10n.t('d180')),
                PillOption(value: null, label: l10n.t('all')),
              ],
              onChanged: (value) => state.setWindowDays(value),
            ),
            _FullSyncRow(state: state),
          ],
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          title: l10n.t('quotaAndAlerts'),
          children: [
            _BudgetRow(state: state),
            _SwitchRow(
              title: l10n.t('quotaAlert'),
              subtitle: l10n.t('quotaAlertDesc'),
              value: state.settings.notificationsEnabled,
              onChanged: (value) => _toggleNotifications(context, state, value),
            ),
            if (state.settings.notificationsEnabled) ...[
              _ActionRow(
                label: l10n.t('testNotification'),
                glyph: AppGlyphs.toggleOn,
                onTap: () => _testNotification(context, state),
              ),
              _PillRow<int>(
                title: l10n.t('quotaAlertThreshold'),
                subtitle: l10n.t('quotaAlertThresholdDesc'),
                value: state.settings.quotaAlertPercent,
                options: const [
                  PillOption(value: 10, label: '10%'),
                  PillOption(value: 15, label: '15%'),
                  PillOption(value: 20, label: '20%'),
                  PillOption(value: 25, label: '25%'),
                  PillOption(value: 30, label: '30%'),
                ],
                onChanged: (value) => state.setQuotaAlertPercent(value),
              ),
              _PillRow<int>(
                title: l10n.t('budgetAlertThreshold'),
                subtitle: l10n.t('budgetAlertThresholdDesc'),
                value: state.settings.budgetAlertPercent,
                options: const [
                  PillOption(value: 70, label: '70%'),
                  PillOption(value: 80, label: '80%'),
                  PillOption(value: 90, label: '90%'),
                ],
                onChanged: (value) => state.setBudgetAlertPercent(value),
              ),
              _SwitchRow(
                title: l10n.t('quietHours'),
                subtitle: l10n.t('quietHoursDesc'),
                value: state.settings.quietHoursEnabled,
                onChanged: (value) => state.setQuietHoursEnabled(value),
              ),
            ],
          ],
        ),
        if (state.settings.notificationsEnabled) ...[
          const SizedBox(height: 12),
          _AlertHistoryCard(state: state),
        ],
        const SizedBox(height: 12),
        _SettingsCard(
          title: l10n.t('setAppearance'),
          children: [
            _PillRow<String>(
              title: l10n.t('theme'),
              subtitle: l10n.t('themeDesc'),
              value: state.themeMode,
              options: [
                PillOption(value: 'system', label: l10n.t('system')),
                PillOption(value: 'light', label: l10n.t('light')),
                PillOption(value: 'dark', label: l10n.t('dark')),
              ],
              onChanged: (value) => state.setThemeMode(value),
            ),
            _SwitchRow(
              title: l10n.t('amoled'),
              subtitle: l10n.t('amoledDesc'),
              value: state.settings.amoled,
              onChanged: (value) => state.setAmoled(value),
            ),
            _PillRow<String>(
              title: l10n.t('currency'),
              subtitle: l10n.t('currencyDesc'),
              value: state.currency,
              options: [
                PillOption(value: 'CNY', label: 'CNY ¥'),
                PillOption(value: 'USD', label: 'USD \$'),
              ],
              onChanged: (value) => state.setCurrency(value),
            ),
            _PillRow<String>(
              title: l10n.t('language'),
              subtitle: l10n.t('languageDesc'),
              value: state.languagePreference,
              options: [
                PillOption(value: 'system', label: l10n.t('system')),
                PillOption(value: 'zh', label: '中文'),
                PillOption(value: 'en', label: 'English'),
              ],
              onChanged: (value) => state.setLanguage(value),
            ),
            _SwitchRow(
              title: l10n.t('showAccountsPanel'),
              subtitle: l10n.t('showAccountsPanelDesc'),
              value: state.settings.showAccountsPanel,
              onChanged: (value) =>
                  state.updateSettings(showAccountsPanel: value),
            ),
          ],
        ),
        if (isDesktop) ...[
          const SizedBox(height: 12),
          _DesktopSettingsCard(state: state),
        ],
        const SizedBox(height: 12),
        _SettingsCard(
          title: l10n.t('setData'),
          children: [
            _InfoRow(label: l10n.t('dataDir'), value: state.databasePath),
            _InfoRow(
              label: l10n.t('syncInfo'),
              value:
                  '${fmtInt(sync?.totalRecords ?? 0)} ${l10n.t('items')} · $lastSync',
            ),
            _VersionRow(l10n: l10n),
            _UpdateRow(l10n: l10n, state: state),
          ],
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          title: l10n.t('exportBackup'),
          children: [
            _ActionRow(
              label: l10n.t('exportRecords'),
              subtitle: l10n.t('exportRecordsDesc'),
              glyph: AppGlyphs.export,
              onTap: () => _exportRecords(context),
            ),
            _ActionRow(
              label: l10n.t('exportKeys'),
              subtitle: l10n.t('exportKeysDesc'),
              glyph: AppGlyphs.dataUsage,
              onTap: () => _exportKeys(context),
            ),
            _ActionRow(
              label: l10n.t('backupDatabase'),
              subtitle: l10n.t('backupHint'),
              glyph: AppGlyphs.cloudDownload,
              onTap: () => _backupDatabase(context),
            ),
            _ActionRow(
              label: l10n.t('backupRestore'),
              subtitle: l10n.t('backupRestoreHint'),
              glyph: AppGlyphs.undo,
              onTap: () => _restoreBackup(context),
            ),
            _ActionRow(
              label: l10n.t('shareSummary'),
              subtitle: l10n.t('shareSummaryHint'),
              glyph: AppGlyphs.openExternal,
              onTap: () => _shareSummary(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DataMaintenanceCard(state: state),
        const SizedBox(height: 12),
        _SettingsCard(
          title: l10n.t('syncLog'),
          children: [
            if (state.syncLog.isEmpty)
              _InfoRow(label: l10n.t('noSyncLog'), value: '—')
            else
              for (final entry in state.syncLog.take(5))
                _SyncLogRow(entry: entry, l10n: l10n),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: EdgeInsets.zero,
          child: _ActionRow(
            label: l10n.t('aboutTitle'),
            subtitle: 'QuotaRoom · ${l10n.t('aboutIntro')}',
            glyph: AppGlyphs.info,
            onTap: () => Navigator.of(context)
                .push(prismPageRoute<void>(builder: (_) => const AboutPage())),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          l10n.t('dataPrivacyDesc'),
          textAlign: TextAlign.center,
          style: AppTextStyle.caption2
              .of(context)
              .copyWith(color: scheme.onSurfaceVariant, height: 1.6),
        ),
      ],
    );
  }

  void _notice(BuildContext context, String text, {bool error = false}) {
    BannerHost.maybeOf(context)
        ?.show(text, level: error ? BannerLevel.error : BannerLevel.success);
  }

  Future<void> _toggleNotifications(
    BuildContext context,
    AppState state,
    bool value,
  ) async {
    final enabled = await state.setNotificationsEnabled(value);
    if (!context.mounted) return;
    if (value && !enabled) {
      _notice(context, state.l10n.t('notificationsDenied'), error: true);
    }
  }

  Future<void> _testNotification(BuildContext context, AppState state) async {
    final sent = await state.sendTestNotification();
    if (!context.mounted) return;
    _notice(
      context,
      sent
          ? state.l10n.t('testNotification')
          : state.l10n.t('notificationsDenied'),
      error: !sent,
    );
  }

  /// Desktop has no share sheet for files: let the user pick a destination
  /// instead. Mobile keeps the existing share flow.
  Future<void> _saveOrShare(
    BuildContext context, {
    required File file,
    required String shareText,
  }) async {
    await saveOrShareExport(context, file: file, shareText: shareText);
  }

  Future<void> _exportRecords(BuildContext context) async {
    final state = context.read<AppState>();
    final account = state.activeAccount;
    if (account == null) return;
    final l10n = state.l10n;
    try {
      final service = ExportService(db: state.db.db, usage: state.usageRepo);
      final file = await service.exportRecordsCsv(account.id, state.keyNames);
      if (!context.mounted) return;
      await _saveOrShare(
        context,
        file: file,
        shareText: 'QuotaRoom · ${account.name} records',
      );
    } catch (e) {
      if (!context.mounted) return;
      _notice(context, '${l10n.t('exportFailed')}: $e', error: true);
    }
  }

  Future<void> _exportKeys(BuildContext context) async {
    final state = context.read<AppState>();
    final account = state.activeAccount;
    if (account == null) return;
    final l10n = state.l10n;
    try {
      final service = ExportService(db: state.db.db, usage: state.usageRepo);
      final file = await service.exportKeysCsv(account.id, state.keyNames);
      if (!context.mounted) return;
      await _saveOrShare(
        context,
        file: file,
        shareText: 'QuotaRoom · ${account.name} key summary',
      );
    } catch (e) {
      if (!context.mounted) return;
      _notice(context, '${l10n.t('exportFailed')}: $e', error: true);
    }
  }

  Future<void> _backupDatabase(BuildContext context) async {
    final state = context.read<AppState>();
    final l10n = state.l10n;
    try {
      final service = ExportService(db: state.db.db, usage: state.usageRepo);
      final file = await service.backupDatabase();
      if (!context.mounted) return;
      await _saveOrShare(
        context,
        file: file,
        shareText: 'QuotaRoom database backup',
      );
    } catch (e) {
      if (!context.mounted) return;
      _notice(context, '${l10n.t('exportFailed')}: $e', error: true);
    }
  }

  Future<void> _restoreBackup(BuildContext context) async {
    final state = context.read<AppState>();
    final l10n = state.l10n;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'QuotaRoom backup',
          extensions: ['db', 'sqlite', 'sqlite3'],
        ),
      ],
    );
    if (file == null || !context.mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.t('restoreConfirmTitle'),
      message: l10n.t('restoreConfirmBody'),
      cancelLabel: l10n.t('cancel'),
      confirmLabel: l10n.t('backupRestore'),
    );
    if (!confirmed) return;
    try {
      final bytes = await file.readAsBytes();
      final restored = await state.restoreUsageFromBackup(bytes);
      if (!context.mounted) return;
      _notice(context, l10n.t('restoreDone', {'n': fmtInt(restored)}));
    } catch (e) {
      if (!context.mounted) return;
      _notice(context, '${l10n.t('restoreFailed')}: $e', error: true);
    }
  }

  Future<void> _shareSummary(BuildContext context) async {
    final state = context.read<AppState>();
    final l10n = state.l10n;
    final data = state.dashboard;
    if (data == null) {
      _notice(context, l10n.t('shareSummaryEmpty'));
      return;
    }
    final range = switch (state.dashboardRange) {
      'today' => l10n.t('today'),
      '7d' => l10n.t('d7'),
      '30d' => l10n.t('d30'),
      _ => l10n.t('all'),
    };
    String quotaLabel(String label) => switch (label) {
      '5h Rolling' => l10n.t('rolling'),
      'Weekly' => l10n.t('weekly'),
      'Monthly' => l10n.t('monthly'),
      _ => label,
    };
    final lines = <String>[
      'QuotaRoom · ${state.activeAccount?.name ?? ''}',
      '${l10n.t('currentRange')}: $range',
      '${l10n.t('totalCost')}: ${fmtMoney(data.totals.totalCostUsd, currency: state.currency, rate: state.usdCny)}',
      '${l10n.t('totalTokens')}: ${fmtTokens(data.totals.totalTokens)}',
      '${l10n.t('totalRequests')}: ${fmtInt(data.totals.requestCount)}',
      '${l10n.t('hitRate')}: ${data.totals.hitRate.toStringAsFixed(1)}%',
      for (final window in data.quota?.windows ?? const <QuotaWindow>[])
        '${quotaLabel(window.label)}: ${l10n.t('used')} '
            '${window.used.toStringAsFixed(1)}% · ${l10n.t('remaining')} '
            '${window.remaining.toStringAsFixed(1)}%',
      'https://github.com/StarryCognet/quotaroom',
    ];
    try {
      final text = lines.join('\n');
      if (isDesktop) {
        await Clipboard.setData(ClipboardData(text: text));
        if (!context.mounted) return;
        _notice(context, l10n.t('copiedToClipboard'));
        return;
      }
      await ExportService(
        db: state.db.db,
        usage: state.usageRepo,
      ).shareText(text);
    } catch (e) {
      if (!context.mounted) return;
      _notice(context, '${l10n.t('exportFailed')}: $e', error: true);
    }
  }

  Future<void> _openLogin(BuildContext context, {required bool relogin}) async {
    await Navigator.of(context).push(
      prismPageRoute<void>(
        builder: (_) => PrismLoginPage(asRoute: true, relogin: relogin),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final state = context.read<AppState>();
    final l10n = state.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.t('setLogout'),
      message: l10n.t('logoutConfirm'),
      cancelLabel: l10n.t('cancel'),
      confirmLabel: l10n.t('logout'),
      danger: true,
    );
    if (!confirmed) return;
    await state.logoutActive();
    if (!context.mounted) return;
    _notice(context, l10n.t('loggedOut'));
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i == 0) rows.add(const Divider(height: 1, thickness: 1));
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(const Divider(height: 1, thickness: 1));
      }
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 10),
            child: Text(
              title,
              style: AppTextStyle.caption1
                  .of(context, emphasized: true)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context, emphasized: true)
                  .copyWith(color: valueColor ?? scheme.onSurface, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.glyph,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  final String label;
  final String? subtitle;
  final Glyph glyph;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final color = danger ? scheme.error : scheme.onSurface;
    return PressSurface(
      fill: const Color(0x00000000),
      shape: AppShape.all(0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      onPressed: onTap,
      child: Row(
        children: [
          GlyphIcon(
            glyph,
            size: 19,
            color: danger ? scheme.error : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: color),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption2
                        .of(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          GlyphIcon(
            AppGlyphs.chevronForward,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _AlertHistoryCard extends StatefulWidget {
  const _AlertHistoryCard({required this.state});

  final AppState state;

  @override
  State<_AlertHistoryCard> createState() => _AlertHistoryCardState();
}

class _AlertHistoryCardState extends State<_AlertHistoryCard> {
  List<Map<String, Object?>> _items = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final items = await widget.state.notifications.history();
    if (mounted) setState(() => _items = items.take(6).toList());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = widget.state.l10n;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l10n.t('alertHistory'),
            trailing: IconButton(
              onPressed: _load,
              tooltip: l10n.t('refresh'),
              icon: const GlyphIcon(AppGlyphs.refresh, size: 17),
            ),
          ),
          const SizedBox(height: 6),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l10n.t('alertHistoryEmpty'),
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          else
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0) Divider(height: 12, thickness: 1),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GlyphIcon(
                    AppGlyphs.requests,
                    size: 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (_items[i]['title'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption2
                              .of(context, emphasized: true)
                              .copyWith(color: scheme.onSurface),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          (_items[i]['body'] ?? '').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption2
                              .of(context)
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    fmtRelative(
                      parseDateTime(_items[i]['at']),
                      never: l10n.t('never'),
                      justNow: l10n.t('justNow'),
                      minAgo: l10n.t('minAgo'),
                      hrAgo: l10n.t('hrAgo'),
                      dayAgo: l10n.t('dayAgo'),
                    ),
                    style: AppTextStyle.caption2
                        .of(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

class _DataMaintenanceCard extends StatefulWidget {
  const _DataMaintenanceCard({required this.state});

  final AppState state;

  @override
  State<_DataMaintenanceCard> createState() => _DataMaintenanceCardState();
}

class _DataMaintenanceCardState extends State<_DataMaintenanceCard> {
  String _size = '—';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSize());
  }

  Future<void> _loadSize() async {
    final bytes = await widget.state.databaseSizeBytes();
    if (!mounted) return;
    setState(() => _size = _formatBytes(bytes));
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _cleanTemp() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final count = await widget.state.cleanupTempFiles();
      if (!mounted) return;
      BannerHost.maybeOf(context)?.show(
        widget.state.l10n.t('cleanedFiles', {'n': count}),
        level: BannerLevel.success,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkIntegrity() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.state.checkDatabaseIntegrity();
      if (!mounted) return;
      final ok = result.toLowerCase() == 'ok';
      BannerHost.maybeOf(context)?.show(
        ok
            ? widget.state.l10n.t('integrityOk')
            : widget.state.l10n.t('integrityFailed', {'result': result}),
        level: ok ? BannerLevel.success : BannerLevel.error,
      );
    } catch (e) {
      if (!mounted) return;
      BannerHost.maybeOf(context)?.show(
        widget.state.l10n.t('integrityFailed', {'result': e}),
        level: BannerLevel.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compact() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.state.compactDatabase();
      await _loadSize();
      if (!mounted) return;
      BannerHost.maybeOf(context)?.show(
        widget.state.l10n.t('databaseCompacted'),
        level: BannerLevel.success,
      );
    } catch (e) {
      if (!mounted) return;
      BannerHost.maybeOf(context)?.show(
        '${widget.state.l10n.t('loadFailed')}: $e',
        level: BannerLevel.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    final l10n = widget.state.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.t('clearAccountData'),
      message: l10n.t('clearAccountConfirm'),
      cancelLabel: l10n.t('cancel'),
      confirmLabel: l10n.t('clearAccountData'),
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      final count = await widget.state.clearActiveAccountUsage();
      await _loadSize();
      if (!mounted) return;
      BannerHost.maybeOf(context)?.show(
        count > 0
            ? l10n.t('dataCleared', {'n': count})
            : l10n.t('noDataCleared'),
        level: BannerLevel.success,
      );
    } catch (e) {
      if (!mounted) return;
      BannerHost.maybeOf(context)?.show('$e', level: BannerLevel.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.state.l10n;
    return _SettingsCard(
      title: l10n.t('dataManagement'),
      children: [
        _InfoRow(label: l10n.t('databaseSize'), value: _size),
        _ActionRow(
          label: l10n.t('cleanupTemp'),
          subtitle: l10n.t('cleanupTempDesc'),
          glyph: AppGlyphs.broom,
          onTap: _cleanTemp,
        ),
        _ActionRow(
          label: l10n.t('integrityCheck'),
          subtitle: l10n.t('integrityCheckDesc'),
          glyph: AppGlyphs.verified,
          onTap: _checkIntegrity,
        ),
        _ActionRow(
          label: l10n.t('compactDatabase'),
          subtitle: l10n.t('compactDatabaseDesc'),
          glyph: AppGlyphs.layers,
          onTap: _compact,
        ),
        _ActionRow(
          label: l10n.t('clearAccountData'),
          subtitle: l10n.t('clearAccountDataDesc'),
          glyph: AppGlyphs.broom,
          danger: true,
          onTap: _clear,
        ),
      ],
    );
  }
}

class _DesktopSettingsCard extends StatefulWidget {
  const _DesktopSettingsCard({required this.state});

  final AppState state;

  @override
  State<_DesktopSettingsCard> createState() => _DesktopSettingsCardState();
}

class _DesktopSettingsCardState extends State<_DesktopSettingsCard> {
  bool _launchAtStartup = false;
  bool _busy = false;
  bool _userToggled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final enabled = await DesktopShell.instance.isLaunchAtStartupEnabled();
    if (mounted && !_userToggled && !_busy) {
      setState(() => _launchAtStartup = enabled);
    }
  }

  Future<void> _toggleLaunch(bool value) async {
    if (_busy) return;
    _userToggled = true;
    setState(() => _busy = true);
    final ok = await DesktopShell.instance.setLaunchAtStartup(value);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _launchAtStartup = value;
    });
    if (!ok) {
      _userToggled = false;
      unawaited(_load());
    }
    final l10n = widget.state.l10n;
    BannerHost.maybeOf(context)?.show(
      ok ? l10n.t('settingSaved') : l10n.t('settingSaveFailed'),
      level: ok ? BannerLevel.success : BannerLevel.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.state.l10n;
    return _SettingsCard(
      title: l10n.t('desktopIntegration'),
      children: [
        _SwitchRow(
          title: l10n.t('closeToTray'),
          subtitle: l10n.t('closeToTrayDesc'),
          value: DesktopShell.instance.closeToTray,
          onChanged: (value) async {
            await DesktopShell.instance.setCloseToTray(value);
            if (mounted) setState(() {});
          },
        ),
        _SwitchRow(
          title: l10n.t('launchAtStartup'),
          subtitle: l10n.t('launchAtStartupDesc'),
          value: _launchAtStartup,
          onChanged: _toggleLaunch,
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _PillRow<T> extends StatelessWidget {
  const _PillRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final T value;
  final List<PillOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyle.caption1
                .of(context, emphasized: true)
                .copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTextStyle.caption2
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 9),
          PillSelector<T>(
            value: value,
            options: options,
            onChanged: onChanged,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _FullSyncRow extends StatelessWidget {
  const _FullSyncRow({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = state.l10n;
    final scheme = context.colorScheme;
    final running = state.progress.running;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('fullSync'),
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  running
                      ? '${l10n.t('syncRunning')} · ${l10n.t('pagePrefix')} ${state.progress.page + 1}'
                      : l10n.t('fullSyncDesc'),
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: running ? null : () => _startFullSync(context),
            child: Text(l10n.t('startFullSync')),
          ),
        ],
      ),
    );
  }

  Future<void> _startFullSync(BuildContext context) async {
    final l10n = state.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.t('fullSync'),
      message: l10n.t('fullSyncConfirm'),
      cancelLabel: l10n.t('cancel'),
      confirmLabel: l10n.t('startSync'),
    );
    if (!confirmed) return;
    final result = await state.syncNow(full: true);
    if (!context.mounted) return;
    final text = result.ok
        ? '${l10n.t('syncDone')} · +${result.inserted}'
        : '${l10n.t('syncFailed')}: ${result.error ?? ''}';
    BannerHost.maybeOf(
      context,
    )?.show(text, level: result.ok ? BannerLevel.success : BannerLevel.error);
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = state.l10n;
    final scheme = context.colorScheme;
    final budget = state.settings.dailyBudgetUsd;
    final label = budget == null
        ? l10n.t('notSet')
        : fmtMoney(budget, currency: state.currency, rate: state.usdCny);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('dailyBudget'),
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.t('dailyBudgetDesc'),
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(onPressed: () => _edit(context), child: Text(label)),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final l10n = state.l10n;
    final current = state.settings.dailyBudgetUsd;
    final display = current == null
        ? ''
        : (state.currency == 'CNY' ? current * state.usdCny : current)
              .toStringAsFixed(2);
    final controller = TextEditingController(text: display);
    final result = await showFloatingDialog<String>(
      context: context,
      child: AlertDialog(
        title: l10n.t('dailyBudgetEdit'),
        hasFields: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('__clear__'),
            child: Text(l10n.t('clear')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.t('save')),
          ),
        ],
        child: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: l10n.t('budgetInputHint', {'currency': state.currency}),
            prefixText: state.currency == 'CNY' ? '¥ ' : '\$ ',
          ),
        ),
      ),
    );
    if (result == null) {
      controller.dispose();
      return;
    }
    if (result == '__clear__') {
      controller.dispose();
      await state.setDailyBudget(null);
      if (!context.mounted) return;
      BannerHost.maybeOf(context)?.show(l10n.t('budgetCleared'));
      return;
    }
    final value = double.tryParse(result.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) {
      // Invalid input must not silently delete an existing budget.
      controller.dispose();
      if (!context.mounted) return;
      BannerHost.maybeOf(context)
          ?.show(l10n.t('budgetInvalid'), level: BannerLevel.error);
      return;
    }
    controller.dispose();
    final usd = state.currency == 'CNY' ? value / state.usdCny : value;
    await state.setDailyBudget(usd);
    if (!context.mounted) return;
    BannerHost.maybeOf(context)?.show(l10n.t('budgetSaved'));
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: loadPackageInfo(),
      builder: (context, snapshot) {
        final version = snapshot.hasData
            ? '${snapshot.data!.version} (${snapshot.data!.buildNumber})'
            : '1.0.0';
        return _InfoRow(label: l10n.t('currentVersion'), value: version);
      },
    );
  }
}

class _UpdateRow extends StatefulWidget {
  const _UpdateRow({required this.l10n, required this.state});

  final L10n l10n;
  final AppState state;

  @override
  State<_UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends State<_UpdateRow> {
  bool _busy = false;

  Future<void> _check() async {
    final l10n = widget.l10n;
    setState(() => _busy = true);
    try {
      final info = await widget.state.checkForUpdate(force: true);
      if (!mounted) return;
      if (info == null || !info.hasUpdate) {
        BannerHost.maybeOf(context)?.show(l10n.t('updateNone'));
        return;
      }
      await showUpdateDialog(context, state: widget.state, info: info);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().contains('403')
          ? l10n.t('updateRateLimited')
          : '${l10n.t('updateFailed')}: $e';
      BannerHost.maybeOf(context)?.show(message, level: BannerLevel.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ActionRow(
      label: widget.l10n.t('checkUpdate'),
      subtitle: _busy
          ? widget.l10n.t('checkingUpdate')
          : widget.l10n.t('checkUpdateDesc'),
      glyph: AppGlyphs.cloudDownload,
      onTap: _busy ? () {} : _check,
    );
  }
}

class _SyncLogRow extends StatelessWidget {
  const _SyncLogRow({required this.entry, required this.l10n});

  final Map<String, Object?> entry;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final ok = entry['ok'] == true;
    final partial = entry['partial'] == true;
    final error = (entry['error'] ?? '').toString();
    final inserted = (entry['inserted'] as num?)?.toInt() ?? 0;
    final account = (entry['account'] ?? '').toString();
    final mode = entry['mode'] == 'full'
        ? l10n.t('fullSyncMode')
        : l10n.t('incrementalMode');
    final color = ok
        ? (partial ? const Color(0xFFD97706) : const Color(0xFF16A34A))
        : scheme.error;
    final status = ok
        ? (partial ? l10n.t('syncStatusPartial') : l10n.t('syncStatusOk'))
        : l10n.t('syncStatusError');
    final at = DateTime.tryParse((entry['at'] ?? '').toString())?.toLocal();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$status · $mode',
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  '$account · ${fmtDateTimeShort(at)} · $inserted ${l10n.t('items')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    error,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption2
                        .of(context)
                        .copyWith(color: scheme.error),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
