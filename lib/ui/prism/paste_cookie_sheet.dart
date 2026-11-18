import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../core/i18n.dart';
import '../../core/platform.dart';

/// Prism_ui form sheet shared by the login page and the Android WebView
/// fallback. Desktop gets a centered form sheet; mobile gets a snapping
/// bottom sheet.
Future<String?> showPasteCookieSheet(BuildContext context, L10n l10n) {
  return showFormSheet<String>(
    context: context,
    props: const SheetProps(detents: [0.5, 0.9]),
    builder: (_) => _PasteCookieForm(l10n: l10n),
  );
}

class _PasteCookieForm extends StatefulWidget {
  const _PasteCookieForm({required this.l10n});

  final L10n l10n;

  @override
  State<_PasteCookieForm> createState() => _PasteCookieFormState();
}

class _PasteCookieFormState extends State<_PasteCookieForm> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = widget.l10n.t('pasteCookieEmpty'));
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.l10n.t('pasteCookie'),
              style: AppTextStyle.title2
                  .of(context, emphasized: true)
                  .copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              widget.l10n.t(
                isDesktop ? 'pasteCookieDescDesktop' : 'pasteCookieDesc',
              ),
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: widget.l10n.t('pasteCookieHint'),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 16),
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
        ),
      ),
    );
  }
}
