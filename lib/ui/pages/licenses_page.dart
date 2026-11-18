import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// Shows the MIT license bundled as `assets/LICENSE`, which preserves the
/// upstream GoGauge copyright notice required by the license.
class OpenSourceLicensesPage extends StatelessWidget {
  const OpenSourceLicensesPage({super.key});

  static const _upstreamUrl = 'https://github.com/yphyphyph/opencode-go-gauge';

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<AppState>().l10n;
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('openSourceLicenses'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: l10n.t('openSourceLicenses')),
                const SizedBox(height: 8),
                Text(
                  l10n.t('licenseIntro'),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.7,
                    color: colors.text2,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tech in const [
                      'MIT',
                      'GoGauge upstream',
                      'Flutter',
                      'Dart',
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
                          style: TextStyle(fontSize: 10.5, color: colors.text2),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: FutureBuilder<String>(
              future: rootBundle.loadString('assets/LICENSE'),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return SelectableText(
                  snapshot.data!,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    height: 1.6,
                    color: colors.text2,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              onTap: () => _openUpstream(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(Icons.code_rounded, size: 18, color: colors.primary),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.t('upstream'),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'github.com/yphyphyph/opencode-go-gauge',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: colors.text3,
                            ),
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
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUpstream(BuildContext context) async {
    final l10n = context.read<AppState>().l10n;
    try {
      final ok = await launchUrl(
        Uri.parse(_upstreamUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.t('loadFailed'))));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${l10n.t('loadFailed')}: $e')));
    }
  }
}
