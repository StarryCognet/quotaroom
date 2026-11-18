import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/app_state.dart';
import '../prism/app_glyphs.dart';
import '../widgets/common.dart';

/// Shows the GPL-3.0 text and third-party notices bundled as `assets/LICENSE`,
/// including the upstream GoGauge MIT notice and FlClash / prism_ui credits.
class OpenSourceLicensesPage extends StatefulWidget {
  const OpenSourceLicensesPage({super.key});

  static const _upstreamUrl = 'https://github.com/yphyphyph/opencode-go-gauge';

  @override
  State<OpenSourceLicensesPage> createState() => _OpenSourceLicensesPageState();
}

class _OpenSourceLicensesPageState extends State<OpenSourceLicensesPage> {
  late final Future<String> _license = rootBundle.loadString('assets/LICENSE');

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<AppState>().l10n;
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
            title: Text(l10n.t('openSourceLicenses')),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          context.appBarInset + 8,
          16,
          24 + context.bottomInset,
        ),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: l10n.t('openSourceLicenses')),
                const SizedBox(height: 8),
                Text(
                  l10n.t('licenseIntro'),
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant, height: 1.7),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tech in const [
                      'GPL-3.0',
                      'MIT upstream',
                      'prism_ui',
                      'Flutter',
                      'Dart',
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
            child: FutureBuilder<String>(
              future: _license,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ActivityIndicator(size: 22, color: scheme.primary),
                    ),
                  );
                }
                return SelectableText(
                  snapshot.data!,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(
                        fontFamily: 'monospace',
                        height: 1.6,
                        color: scheme.onSurfaceVariant,
                      ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: EdgeInsets.zero,
            child: PressSurface(
              fill: const Color(0x00000000),
              shape: AppShape.all(0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              onPressed: () => _openUpstream(context),
              child: Row(
                children: [
                  GlyphIcon(AppGlyphs.code, size: 18, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.t('upstream'),
                          style: AppTextStyle.caption1
                              .of(context, emphasized: true)
                              .copyWith(color: scheme.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'github.com/yphyphyph/opencode-go-gauge',
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
        Uri.parse(OpenSourceLicensesPage._upstreamUrl),
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
