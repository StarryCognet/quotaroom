import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../login/login_page.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
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
              valueColor: account?.hasToken == true
                  ? colors.green
                  : colors.red,
            ),
            _InfoRow(
              label: l10n.t('accountName'),
              value: account?.name ?? '—',
            ),
            _InfoRow(
              label: l10n.t('workspace'),
              value: maskWorkspace(
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
              onChanged: (value) => state.updateSettings(
                syncIntervalSec: value,
              ),
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
            _InfoRow(
              label: l10n.t('dataDir'),
              value: state.databasePath,
            ),
            _InfoRow(
              label: l10n.t('syncInfo'),
              value:
                  '${fmtInt(sync?.totalRecords ?? 0)} ${l10n.t('items')} · $lastSync',
            ),
            _VersionRow(l10n: l10n),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: EdgeInsets.zero,
          child: _ActionRow(
            label: l10n.t('aboutTitle'),
            subtitle: 'QuotaRoom · ${l10n.t('aboutIntro')}',
            icon: Icons.info_outline_rounded,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.t('loggedOut'))),
    );
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
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

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
            Icon(
              icon,
              size: 18,
              color: danger ? colors.red : colors.text2,
            ),
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
            Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: colors.text3,
            ),
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
          Text(
            subtitle,
            style: TextStyle(fontSize: 10.5, color: colors.text3),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
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
