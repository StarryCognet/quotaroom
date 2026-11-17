import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
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
    final colors = context.colors;
    return Container(
      margin: margin,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: color ?? colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? colors.border),
        boxShadow: cardShadowFor(colors),
      ),
      child: Padding(padding: padding, child: child),
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
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 11.5, color: colors.text3),
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
    final colors = context.colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.muted,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              GestureDetector(
                onTap: () => onChanged(option.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 13,
                    vertical: compact ? 6 : 7,
                  ),
                  decoration: BoxDecoration(
                    color: option.value == value
                        ? colors.card
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    boxShadow: option.value == value
                        ? const [
                            BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    option.label,
                    style: TextStyle(
                      fontSize: compact ? 11.5 : 12,
                      fontWeight: option.value == value
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: option.value == value
                          ? colors.primary
                          : colors.text2,
                    ),
                  ),
                ),
              ),
          ],
        ),
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
  final IconData icon;
  final String? sub;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: colors.text3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: valueColor ?? colors.text,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: -0.4,
              ),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: colors.text3),
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
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(fontSize: 9.5, color: colors.text3),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: highlight ?? colors.text,
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
  const LegendDot({
    super.key,
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: colors.text3)),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: compact ? 20 : 44,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 32 : 42, color: colors.text3),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.text2,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.text3, height: 1.5),
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
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 40, color: colors.red),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: colors.text2, height: 1.5),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
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
  const SyncBanner({
    super.key,
    required this.progress,
    required this.l10n,
  });

  final SyncProgress progress;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    if (!progress.running) return const SizedBox.shrink();
    final colors = context.colors;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${l10n.t('syncRunning')} · ${progress.account}'
                  '${progress.page > 0 ? ' · ${l10n.t('pagePrefix')} ${progress.page + 1}' : ''}',
                  style: TextStyle(fontSize: 12, color: colors.text2),
                ),
              ),
              Text(
                '${l10n.t('totalN')} ${fmtInt(progress.inserted)}',
                style: TextStyle(fontSize: 11, color: colors.text3),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: const LinearProgressIndicator(minHeight: 4),
          ),
        ],
      ),
    );
  }
}

String formatCost(String currency, double rate, double usd) =>
    fmtMoney(usd, currency: currency, rate: rate);
