import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../state/app_state.dart';

Future<void> showCustomRangeDialog(BuildContext context, AppState state) {
  return showFloatingDialog<void>(
    context: context,
    child: _CustomRangeDialog(state: state),
  );
}

class _CustomRangeDialog extends StatefulWidget {
  const _CustomRangeDialog({required this.state});

  final AppState state;

  @override
  State<_CustomRangeDialog> createState() => _CustomRangeDialogState();
}

class _CustomRangeDialogState extends State<_CustomRangeDialog> {
  late final TextEditingController _from;
  late final TextEditingController _to;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final from =
        widget.state.customRangeFrom ??
        DateTime(now.year, now.month, now.day - 29);
    final to =
        widget.state.customRangeTo ?? DateTime(now.year, now.month, now.day);
    _from = TextEditingController(text: _format(from));
    _to = TextEditingController(text: _format(to));
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  static String _format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  void _quick(int days) {
    final now = DateTime.now();
    final to = DateTime(now.year, now.month, now.day);
    final from = DateTime(now.year, now.month, now.day - (days - 1));
    setState(() {
      _from.text = _format(from);
      _to.text = _format(to);
    });
  }

  void _thisMonth() {
    final now = DateTime.now();
    setState(() {
      _from.text = _format(DateTime(now.year, now.month, 1));
      _to.text = _format(DateTime(now.year, now.month, now.day));
    });
  }

  void _lastMonth() {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month - 1, 1);
    final last = DateTime(now.year, now.month, 0);
    setState(() {
      _from.text = _format(first);
      _to.text = _format(last);
    });
  }

  Future<void> _apply() async {
    final from = DateTime.tryParse(_from.text.trim());
    final to = DateTime.tryParse(_to.text.trim());
    if (from == null ||
        to == null ||
        _from.text.trim().length != 10 ||
        _to.text.trim().length != 10) {
      setState(() => _error = widget.state.l10n.t('invalidRange'));
      return;
    }
    if (to.isBefore(from)) {
      setState(() => _error = widget.state.l10n.t('invalidRange'));
      return;
    }
    if (to.difference(from).inDays > 3650) {
      setState(() => _error = widget.state.l10n.t('rangeTooLong'));
      return;
    }
    await widget.state.setCustomRange(from, to);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = widget.state.l10n;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Container(
          decoration: ShapeDecoration(
            color: scheme.surface,
            shape: AppShape.all(AppCorner.xl),
          ),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.t('customRange'),
                style: AppTextStyle.title3
                    .of(context, emphasized: true)
                    .copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.t('customRangeDesc'),
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.t('fromDate'),
                          style: AppTextStyle.caption2
                              .of(context)
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _from,
                          keyboardType: TextInputType.datetime,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: const InputDecoration(
                            hintText: 'YYYY-MM-DD',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.t('toDate'),
                          style: AppTextStyle.caption2
                              .of(context)
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _to,
                          keyboardType: TextInputType.datetime,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: const InputDecoration(
                            hintText: 'YYYY-MM-DD',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton(
                    onPressed: () => _quick(7),
                    child: Text(l10n.t('d7')),
                  ),
                  OutlinedButton(
                    onPressed: () => _quick(30),
                    child: Text(l10n.t('d30')),
                  ),
                  OutlinedButton(
                    onPressed: () => _quick(90),
                    child: Text(l10n.t('d90')),
                  ),
                  OutlinedButton(
                    onPressed: _thisMonth,
                    child: Text(l10n.t('thisMonth')),
                  ),
                  OutlinedButton(
                    onPressed: _lastMonth,
                    child: Text(l10n.t('lastMonth')),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.t('cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
                      child: Text(l10n.t('apply')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
