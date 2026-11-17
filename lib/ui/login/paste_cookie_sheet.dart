import 'package:flutter/material.dart';

import '../../core/i18n.dart';

/// Manual token/cookie fallback for environments where the embedded login
/// cannot complete (or for quick testing).
Future<String?> showPasteCookieSheet(
  BuildContext context,
  L10n l10n,
) {
  final controller = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final colors = Theme.of(sheetContext);
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          20 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.t('pasteCookie'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('pasteCookieDesc'),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: colors.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontSize: 12.5, height: 1.45),
              decoration: InputDecoration(
                hintText: l10n.t('pasteCookieHint'),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(l10n.t('cancel')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final value = controller.text.trim();
                      if (value.isEmpty) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          SnackBar(content: Text(l10n.t('pasteCookieEmpty'))),
                        );
                        return;
                      }
                      Navigator.of(sheetContext).pop(value);
                    },
                    child: Text(l10n.t('confirm')),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
