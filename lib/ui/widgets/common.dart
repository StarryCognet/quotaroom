import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../data/models.dart';
import '../prism/app_glyphs.dart';

/// Shared cards and rows, now drawn with prism_ui's surfaces, squircle shapes
/// and type scale so every page matches the FlClash-style shell.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.clipBehavior = Clip.none,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Clip clipBehavior;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final shape = AppShape.all(AppCorner.lg);
    final border = borderColor;
    final card = Container(
      margin: margin,
      clipBehavior: clipBehavior,
      decoration: ShapeDecoration(
        color: color ?? SurfaceLevel.card.colorOf(scheme),
        shape: shape,
        shadows: [
          BoxShadow(
            color: const Color(0xFF18122B).withValues(
              alpha: scheme.brightness == Brightness.dark ? 0.18 : 0.05,
            ),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      foregroundDecoration: border == null
          ? null
          : ShapeDecoration(
              shape: shape.copyWith(side: BorderSide(color: border)),
            ),
      child: Padding(padding: padding, child: child),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, progress, card) => Opacity(
        opacity: progress.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - progress)),
          child: card,
        ),
      ),
      child: card,
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyle.headline
                    .of(context, emphasized: true)
                    .copyWith(color: scheme.onSurface),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class PillOption<T> {
  const PillOption({required this.value, required this.label});

  final T value;
  final String label;
}

class PillSelector<T> extends StatelessWidget {
  const PillSelector({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final List<PillOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: PressSurface(
                fill: option.value == value
                    ? scheme.primary
                    : scheme.surfaceContainerHigh,
                shape: AppShape.full,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 11 : 15,
                  vertical: compact ? 6 : 8,
                ),
                onPressed: () => onChanged(option.value),
                child: Text(
                  option.label,
                  maxLines: 1,
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(
                        color: option.value == value
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RangeSelector extends StatelessWidget {
  const RangeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.l10n,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return PillSelector<String>(
      value: value,
      onChanged: onChanged,
      options: [
        PillOption(value: 'today', label: l10n.t('today')),
        PillOption(value: '7d', label: l10n.t('d7')),
        PillOption(value: '30d', label: l10n.t('d30')),
        PillOption(value: 'all', label: l10n.t('all')),
      ],
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.sub,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color color;
  final Glyph icon;
  final String? sub;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: ShapeDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: dark ? 0.16 : 0.08),
          scheme.surface,
        ),
        shape: AppShape.all(AppCorner.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 27,
                height: 27,
                decoration: ShapeDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: AppShape.all(AppCorner.sm),
                ),
                child: Center(child: GlyphIcon(icon, size: 15, color: color)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTextStyle.title1
                  .of(context, emphasized: true)
                  .copyWith(
                    color: valueColor ?? scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.label,
    required this.value,
    this.highlight,
  });

  final String label;
  final String value;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerHigh,
        shape: AppShape.all(AppCorner.xs),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: AppTextStyle.caption2
                  .of(context, emphasized: true)
                  .copyWith(
                    color: highlight ?? scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTextStyle.caption2
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.glyph,
    required this.title,
    this.subtitle,
    this.action,
    this.compact = false,
  });

  final Glyph glyph;
  final String title;
  final String? subtitle;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: compact ? 20 : 44,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 48 : 60,
              height: compact ? 48 : 60,
              decoration: ShapeDecoration(
                color: scheme.surfaceContainerHigh,
                shape: AppShape.all(AppCorner.md),
              ),
              child: Center(
                child: GlyphIcon(
                  glyph,
                  size: compact ? 24 : 29,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .copyWith(color: scheme.onSurface),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(AppGlyphs.warning, size: 40, color: scheme.error),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

class ModelIcon extends StatelessWidget {
  const ModelIcon({super.key, required this.model, this.size = 16});

  final String model;
  final double size;

  static const Map<String, String> _map = {
    'deepseek': 'deepseek',
    'glm': 'glm',
    'gpt': 'gpt',
    'grok': 'grok',
    'kimi': 'kimi',
    'meta': 'meta',
    'mimo': 'mimo',
    'minimax': 'minimax',
    'muse': 'meta',
    'qwen': 'qwen',
    'hy': 'hy',
  };

  @override
  Widget build(BuildContext context) {
    final source = model.toLowerCase();
    final base = source.split('-').first;
    var name = _map[base];
    name ??= base.startsWith('hy') ? 'hy' : 'deepseek';
    final dark = Theme.brightnessOf(context) == Brightness.dark;
    var themed = name;
    if (dark && const ['gpt', 'grok', 'mimo'].contains(name)) {
      themed = '$name-color';
    } else if (!dark && name == 'kimi') {
      themed = 'kimi-color';
    }
    return SvgPicture.asset(
      'assets/icons/models/$themed.svg',
      width: size,
      height: size,
    );
  }
}

class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, required this.progress, required this.l10n});

  final SyncProgress progress;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    if (!progress.running) return const SizedBox.shrink();
    final scheme = context.colorScheme;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ActivityIndicator(size: 16, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${l10n.t('syncRunning')} · ${progress.account}'
                  '${progress.page > 0 ? ' · ${l10n.t('pagePrefix')} ${progress.page + 1}' : ''}',
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              Text(
                '${l10n.t('totalN')} ${fmtInt(progress.inserted)}',
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 9),
          LinearProgressIndicator(minHeight: 5),
        ],
      ),
    );
  }
}

String formatCost(String currency, double rate, double usd) =>
    fmtMoney(usd, currency: currency, rate: rate);
