import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform.dart';
import '../../state/app_state.dart';
import '../prism/app_glyphs.dart';
import '../prism/prism_route.dart';
import '../widgets/app_logo.dart';
import '../widgets/common.dart';
import 'licenses_page.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _projectUrl = 'https://github.com/StarryCognet/quotaroom';
  static const _issuesUrl = 'https://github.com/StarryCognet/quotaroom/issues';
  static const _upstreamUrl = 'https://github.com/yphyphyph/opencode-go-gauge';
  static const _openCodeUrl = 'https://opencode.ai';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final scheme = context.colorScheme;
    return PrismScaffold(
      bar: ScaffoldBar(
        isCompact: false,
        listenable: const AlwaysStoppedAnimation<double>(0),
        loading: const AlwaysStoppedAnimation<bool>(false),
        builder: (context) => ColoredBox(
          color: SurfaceLevel.page.colorOf(context.colorScheme),
          child: AppBar(
            leading: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const GlyphIcon(AppGlyphs.chevronBack),
              tooltip: l10n.t('back'),
            ),
            title: Text(l10n.t('aboutTitle')),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, context.appBarInset + 8, 16, 24),
        children: [
          const Center(child: AppLogo(size: 68)),
          const SizedBox(height: 12),
          Text(
            'QuotaRoom',
            textAlign: TextAlign.center,
            style: AppTextStyle.title2
                .of(context, emphasized: true)
                .copyWith(color: scheme.onSurface, letterSpacing: -0.3),
          ),
          const SizedBox(height: 3),
          Text(
            l10n.t('slogan'),
            textAlign: TextAlign.center,
            style: AppTextStyle.caption2
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 5),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.hasData
                  ? '${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                  : '1.0.0';
              return Text(
                '${l10n.t('version')} $version · $platformLabel',
                textAlign: TextAlign.center,
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              );
            },
          ),
          const SizedBox(height: 18),
          AppCard(
            child: Text(
              l10n.t('introText'),
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant, height: 1.75),
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
                  'feat6',
                  'feat7',
                  'feat8',
                  'feat9',
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GlyphIcon(
                          AppGlyphs.checkCircle,
                          size: 15,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.t(key),
                            style: AppTextStyle.footnote
                                .of(context)
                                .copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.5,
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
                      'prism_ui',
                      'SQLite',
                      'Prism charts',
                      'WebView',
                      'WorkManager',
                      'home_widget',
                      'opencode /console/api',
                    ])
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: ShapeDecoration(
                          color: scheme.surfaceContainerHigh,
                          shape: AppShape.full,
                        ),
                        child: Text(
                          tech,
                          style: AppTextStyle.caption2
                              .of(context)
                              .copyWith(color: scheme.onSurfaceVariant),
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
                  glyph: AppGlyphs.dashboard,
                  label: l10n.t('projectHome'),
                  value: 'github.com/StarryCognet/quotaroom',
                  onTap: () => _open(context, _projectUrl),
                ),
                const Divider(height: 1, thickness: 1),
                _LinkRow(
                  glyph: AppGlyphs.warning,
                  label: l10n.t('feedback'),
                  value: 'github.com/StarryCognet/quotaroom/issues',
                  onTap: () => _open(context, _issuesUrl),
                ),
                const Divider(height: 1, thickness: 1),
                _LinkRow(
                  glyph: AppGlyphs.code,
                  label: l10n.t('upstream'),
                  value: 'github.com/yphyphyph/opencode-go-gauge',
                  onTap: () => _open(context, _upstreamUrl),
                ),
                const Divider(height: 1, thickness: 1),
                _LinkRow(
                  glyph: AppGlyphs.openExternal,
                  label: l10n.t('thanksText'),
                  value: 'opencode.ai',
                  onTap: () => _open(context, _openCodeUrl),
                ),
                const Divider(height: 1, thickness: 1),
                _LinkRow(
                  glyph: AppGlyphs.gavel,
                  label: l10n.t('openSourceLicenses'),
                  value: 'GPL-3.0 · MIT upstream',
                  onTap: () => Navigator.of(context).push(
                    prismPageRoute<void>(
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
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.t('pageFoot', {'version': '2.3.0'}),
            textAlign: TextAlign.center,
            style: AppTextStyle.caption2
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
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
        BannerHost.maybeOf(context)
            ?.show(l10n.t('loadFailed'), level: BannerLevel.error);
      }
    } catch (e) {
      if (!context.mounted) return;
      BannerHost.maybeOf(context)
          ?.show('${l10n.t('loadFailed')}: $e', level: BannerLevel.error);
    }
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.glyph,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final Glyph glyph;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return PressSurface(
      fill: const Color(0x00000000),
      shape: AppShape.all(0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      onPressed: onTap,
      child: Row(
        children: [
          GlyphIcon(glyph, size: 18, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          GlyphIcon(
            AppGlyphs.openExternal,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
