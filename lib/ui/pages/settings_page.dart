import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/export_service.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../login/login_page.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/update_dialog.dart';
import 'about_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colors = context.colors;
    final account = state.activeAccount;
    final sync = state.dashboard?.sync;
    final lastSync = fmtRelative(
      sync?.lastSyncAt,
      never: l10n.t('never'),
      justNow: l10n.t('justNow'),
      minAgo: l10n.t('minAgo'),
      hrAgo: l10n.t('hrAgo'),
      dayAgo: l10n.t('dayAgo'),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
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
              valueColor: account?.hasToken == true ? colors.green : colors.red,
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
              icon: Icons.person_add_alt_1_rounded,
              onTap: () => _openLogin(context, relogin: false),
            ),
            _ActionRow(
              label: l10n.t('relogin'),
              icon: Icons.login_rounded,
              onTap: () => _openLogin(context, relogin: true),
            ),
            _ActionRow(
              label: l10n.t('setLogout'),
              subtitle: l10n.t('logoutDesc'),
              icon: Icons.logout_rounded,
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
            if (state.settings.notificationsEnabled)
              _ActionRow(
                label: l10n.t('testNotification'),
                icon: Icons.notifications_active_outlined,
                onTap: () => _testNotification(context, state),
              ),
          ],
        ),
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
              value: state.language,
              options: const [
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
              icon: Icons.description_outlined,
              onTap: () => _exportRecords(context),
            ),
            _ActionRow(
              label: l10n.t('exportKeys'),
              subtitle: l10n.t('exportKeysDesc'),
              icon: Icons.table_chart_outlined,
              onTap: () => _exportKeys(context),
            ),
            _ActionRow(
              label: l10n.t('backupDatabase'),
              subtitle: l10n.t('backupHint'),
              icon: Icons.archive_outlined,
              onTap: () => _backupDatabase(context),
            ),
            _ActionRow(
              label: l10n.t('backupRestore'),
              subtitle: l10n.t('backupRestoreHint'),
              icon: Icons.settings_backup_restore_rounded,
              onTap: () => _restoreBackup(context),
            ),
            _ActionRow(
              label: l10n.t('shareSummary'),
              subtitle: l10n.t('shareSummaryHint'),
              icon: Icons.ios_share_rounded,
              onTap: () => _shareSummary(context),
            ),
          ],
        ),
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
            icon: Icons.info_outline_rounded,
            onTap: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const AboutPage())),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          l10n.t('dataPrivacyDesc'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10.5, color: colors.text3, height: 1.6),
        ),
      ],
    );
  }

  Future<void> _toggleNotifications(
    BuildContext context,
    AppState state,
    bool value,
  ) async {
    final enabled = await state.setNotificationsEnabled(value);
    if (!context.mounted) return;
    if (value && !enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.l10n.t('notificationsDenied'))),
      );
    }
  }

  Future<void> _testNotification(BuildContext context, AppState state) async {
    final sent = await state.sendTestNotification();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? state.l10n.t('testNotification')
              : state.l10n.t('notificationsDenied'),
        ),
      ),
    );
  }

  Future<void> _exportRecords(BuildContext context) async {
    final state = context.read<AppState>();
    final account = state.activeAccount;
    if (account == null) return;
    final l10n = state.l10n;
    try {
      final service = ExportService(db: state.db.db, usage: state.usageRepo);
      final file = await service.exportRecordsCsv(account.id, state.keyNames);
      await service.shareFile(
        file,
        text: 'QuotaRoom · ${account.name} records',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${l10n.t('exportFailed')}: $e')));
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
      await service.shareFile(
        file,
        text: 'QuotaRoom · ${account.name} key summary',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${l10n.t('exportFailed')}: $e')));
    }
  }

  Future<void> _backupDatabase(BuildContext context) async {
    final state = context.read<AppState>();
    final l10n = state.l10n;
    try {
      final service = ExportService(db: state.db.db, usage: state.usageRepo);
      final file = await service.backupDatabase();
      await service.shareFile(file, text: 'QuotaRoom database backup');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${l10n.t('exportFailed')}: $e')));
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('restoreConfirmTitle')),
        content: Text(l10n.t('restoreConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.t('backupRestore')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final bytes = await file.readAsBytes();
      final restored = await state.restoreUsageFromBackup(bytes);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('restoreDone', {'n': fmtInt(restored)}))),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${l10n.t('restoreFailed')}: $e')));
    }
  }

  Future<void> _shareSummary(BuildContext context) async {
    final state = context.read<AppState>();
    final l10n = state.l10n;
    final data = state.dashboard;
    if (data == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.t('shareSummaryEmpty'))));
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
      await ExportService(
        db: state.db.db,
        usage: state.usageRepo,
      ).shareText(lines.join('\n'));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${l10n.t('exportFailed')}: $e')));
    }
  }

  Future<void> _openLogin(BuildContext context, {required bool relogin}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginPage(asRoute: true, relogin: relogin),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.t('loggedOut'))));
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i == 0) {
        rows.add(Divider(height: 1, color: colors.border));
      }
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Divider(height: 1, color: colors.border));
      }
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.text,
              ),
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
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.text2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: valueColor ?? colors.text,
                height: 1.4,
              ),
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
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = danger ? colors.red : colors.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: danger ? colors.red : colors.text2),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 10.5, color: colors.text3),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 19, color: colors.text3),
          ],
        ),
      ),
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
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10.5, color: colors.text3),
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
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 10.5, color: colors.text3)),
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
    final colors = context.colors;
    final running = state.progress.running;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('fullSync'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  running
                      ? '${l10n.t('syncRunning')} · ${l10n.t('pagePrefix')} ${state.progress.page + 1}'
                      : l10n.t('fullSyncDesc'),
                  style: TextStyle(fontSize: 10.5, color: colors.text3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: running ? null : () => _startFullSync(context),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 11.5),
            ),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = state.l10n;
    final colors = context.colors;
    final budget = state.settings.dailyBudgetUsd;
    final label = budget == null
        ? l10n.t('notSet')
        : fmtMoney(budget, currency: state.currency, rate: state.usdCny);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('dailyBudget'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.t('dailyBudgetDesc'),
                  style: TextStyle(fontSize: 10.5, color: colors.text3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: () => _edit(context),
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
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
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('dailyBudgetEdit')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.t('dailyBudget'),
            hintText: l10n.t('budgetInputHint', {'currency': state.currency}),
            prefixText: state.currency == 'CNY' ? '¥ ' : '\$ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('__clear__'),
            child: Text(l10n.t('clear')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.t('save')),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result == '__clear__') {
      await state.setDailyBudget(null);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.t('budgetCleared'))));
      return;
    }
    final value = double.tryParse(result.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) {
      await state.setDailyBudget(null);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.t('budgetCleared'))));
      return;
    }
    final usd = state.currency == 'CNY' ? value / state.usdCny : value;
    await state.setDailyBudget(usd);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.t('budgetSaved'))));
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.t('updateNone'))));
        return;
      }
      await showUpdateDialog(context, state: widget.state, info: info);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().contains('403')
          ? l10n.t('updateRateLimited')
          : '${l10n.t('updateFailed')}: $e';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
      icon: Icons.system_update_alt_rounded,
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
    final colors = context.colors;
    final ok = entry['ok'] == true;
    final partial = entry['partial'] == true;
    final error = (entry['error'] ?? '').toString();
    final inserted = (entry['inserted'] as num?)?.toInt() ?? 0;
    final account = (entry['account'] ?? '').toString();
    final mode = entry['mode'] == 'full'
        ? l10n.t('fullSyncMode')
        : l10n.t('incrementalMode');
    final color = ok ? (partial ? colors.amber : colors.green) : colors.red;
    final status = ok
        ? (partial ? l10n.t('syncStatusPartial') : l10n.t('syncStatusOk'))
        : l10n.t('syncStatusError');
    final at = DateTime.tryParse((entry['at'] ?? '').toString())?.toLocal();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$status · $mode',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$account · ${fmtDateTimeShort(at)} · $inserted ${l10n.t('items')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.5, color: colors.text3),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    error,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, color: colors.red),
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
