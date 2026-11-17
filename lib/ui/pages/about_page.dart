import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../widgets/app_logo.dart';
import '../widgets/common.dart';
import 'licenses_page.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _upstreamUrl =
      'https://github.com/yphyphyph/opencode-go-gauge';
  static const _openCodeUrl = 'https://opencode.ai';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('aboutTitle'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Center(child: AppLogo(size: 68)),
          const SizedBox(height: 12),
          Text(
            'QuotaRoom',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: colors.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.hasData
                  ? '${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                  : '1.0.0';
              return Text(
                '${l10n.t('version')} $version',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: colors.text3),
              );
            },
          ),
          const SizedBox(height: 18),
          AppCard(
            child: Text(
              l10n.t('introText'),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.75,
                color: colors.text2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: l10n.t('aboutFeatures')),
                const SizedBox(height: 10),
                for (final key in const [
                  'feat1',
                  'feat2',
                  'feat3',
                  'feat4',
                  'feat5',
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 15,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.t(key),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: colors.text2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: l10n.t('aboutTech')),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tech in const [
                      'Flutter',
                      'Dart',
                      'SQLite',
                      'fl_chart',
                      'WebView',
                      'opencode /console/api',
                    ])
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.muted,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          tech,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colors.text2,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _LinkRow(
                  icon: Icons.code_rounded,
                  label: l10n.t('upstream'),
                  value: 'github.com/yphyphyph/opencode-go-gauge',
                  onTap: () => _open(context, _upstreamUrl),
                ),
                Divider(height: 1, color: colors.border),
                _LinkRow(
                  icon: Icons.public_rounded,
                  label: l10n.t('thanksText'),
                  value: 'opencode.ai',
                  onTap: () => _open(context, _openCodeUrl),
                ),
                Divider(height: 1, color: colors.border),
                _LinkRow(
                  icon: Icons.gavel_rounded,
                  label: l10n.t('openSourceLicenses'),
                  value: 'MIT · GoGauge upstream',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const OpenSourceLicensesPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: l10n.t('aboutThanks')),
                const SizedBox(height: 6),
                Text(
                  l10n.t('thanksText'),
                  style: TextStyle(fontSize: 12, color: colors.text2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.t('pageFoot', {'version': '1.0.0'}),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: colors.text3),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final l10n = context.read<AppState>().l10n;
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('loadFailed'))),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.t('loadFailed')}: $e')),
      );
    }
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.primary),
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
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(fontSize: 10.5, color: colors.text3),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.open_in_new_rounded,
              size: 16,
              color: colors.text3,
            ),
          ],
        ),
      ),
    );
  }
}
