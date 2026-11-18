import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String cancelLabel,
  required String confirmLabel,
  bool danger = false,
}) async {
  final scheme = context.colorScheme;
  final result = await showFloatingDialog<bool>(
    context: context,
    child: AlertDialog(
      title: title,
      destructive: danger,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
      child: Text(
        message,
        style: AppTextStyle.footnote
            .of(context)
            .copyWith(color: scheme.onSurfaceVariant, height: 1.5),
      ),
    ),
  );
  return result == true;
}
