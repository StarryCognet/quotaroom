import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';

class Pager extends StatelessWidget {
  const Pager({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onPrev,
    required this.onNext,
    required this.l10n,
  });

  final int page;
  final int totalPages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        TextButton(
          onPressed: page > 1 ? onPrev : null,
          child: Text(l10n.t('prev'), style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Text(
            '${l10n.t('pageOf')} $page ${l10n.t('ofPages')} $totalPages',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: colors.text3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        TextButton(
          onPressed: page < totalPages ? onNext : null,
          child: Text(l10n.t('next'), style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
