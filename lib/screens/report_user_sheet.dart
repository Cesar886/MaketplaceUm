import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/api_error.dart';
import '../services/api_service.dart';

const _reportesUserId = 'u_cesar8herrera_g2zc';

Future<void> showUserReportSheet({
  required BuildContext context,
  required String userId,
  required String userName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _UserReportSheet(userId: userId, userName: userName),
  );
}

class _UserReportSheet extends StatefulWidget {
  const _UserReportSheet({required this.userId, required this.userName});

  final String userId;
  final String userName;

  @override
  State<_UserReportSheet> createState() => _UserReportSheetState();
}

class _UserReportSheetState extends State<_UserReportSheet> {
  static const _reasons = <String>[
    'report_listing.reason_impersonation',
    'report_listing.reason_harassment',
    'report_listing.reason_suspicious',
    'report_listing.reason_inappropriate',
  ];

  final _detailsController = TextEditingController();
  String? _reason;
  bool _sending = false;

  bool get _isOther => _reason == 'other';
  bool get _canSend =>
      !_sending &&
      _reason != null &&
      (!_isOther || _detailsController.text.trim().length >= 5);

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_canSend) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);

    final reason = _isOther
        ? _detailsController.text.trim()
        : (_reason ?? '').tr();
    final message = 'report_user.message_template'.tr(
      namedArgs: {
        'reason': reason,
        'user': widget.userName,
        'userId': widget.userId,
      },
    );

    try {
      await ApiService.sendMessage(
        productId: '',
        sellerId: _reportesUserId,
        text: message,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('report_user.sent'.tr()),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error, stack) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mensajeDeError(
              error,
              stack: stack,
              fallback: 'report_user.send_error'.tr(),
            ),
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: context.colors.surface,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'report_user.title'.tr(),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.colors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'report_user.question'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _reason,
                onChanged: (value) => setState(() => _reason = value),
                child: Column(
                  children: [
                    ..._reasons.map(
                      (reason) => RadioListTile<String>(
                        value: reason,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(reason.tr()),
                      ),
                    ),
                    RadioListTile<String>(
                      value: 'other',
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('report_listing.reason_other'.tr()),
                    ),
                  ],
                ),
              ),
              if (_isOther) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _detailsController,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'report_user.details_hint'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _canSend ? _send : null,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.flag_outlined),
                label: Text(
                  _sending
                      ? 'report_user.sending'.tr()
                      : 'report_user.send'.tr(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'report_user.privacy'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
