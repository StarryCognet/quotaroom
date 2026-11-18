import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/platform.dart';

/// Manual token/cookie fallback for environments where the embedded login
/// cannot complete (or for quick testing). Desktop shows a dialog; mobile
/// keeps the bottom sheet.
Future<String?> showPasteCookieSheet(BuildContext context, L10n l10n) {
  if (isDesktop) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('pasteCookie')),
        content: SizedBox(
          width: 460,
          child: _PasteCookieForm(l10n: l10n, showTitle: false),
        ),
      ),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          20 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _PasteCookieForm(l10n: l10n, showTitle: true),
      );
    },
  );
}

class _PasteCookieForm extends StatefulWidget {
  const _PasteCookieForm({required this.l10n, required this.showTitle});

  final L10n l10n;
  final bool showTitle;

  @override
  State<_PasteCookieForm> createState() => _PasteCookieFormState();
}

class _PasteCookieFormState extends State<_PasteCookieForm> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.l10n.t('pasteCookieEmpty'))),
      );
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle) ...[
          Text(
            widget.l10n.t('pasteCookie'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          widget.l10n.t(
            isDesktop ? 'pasteCookieDescDesktop' : 'pasteCookieDesc',
          ),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.6,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: isDesktop,
          minLines: 2,
          maxLines: 4,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontSize: 12.5, height: 1.45),
          decoration: InputDecoration(
            hintText: widget.l10n.t('pasteCookieHint'),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(widget.l10n.t('cancel')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _submit,
                child: Text(widget.l10n.t('confirm')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
