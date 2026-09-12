import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_error.dart';
import '../services/api_service.dart';
import '../services/anon_session.dart';

enum _ReportTarget { product, account }

Future<void> showProductReportSheet({
  required BuildContext context,
  required Product product,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProductReportSheet(product: product),
  );
}

class _ProductReportSheet extends StatefulWidget {
  const _ProductReportSheet({required this.product});

  final Product product;

  @override
  State<_ProductReportSheet> createState() => _ProductReportSheetState();
}

class _ProductReportSheetState extends State<_ProductReportSheet> {
  final _otherController = TextEditingController();
  _ReportTarget _target = _ReportTarget.product;
  String? _reason;
  bool _sending = false;

  static const _productReasons = <String>[
    'report_listing.reason_misleading',
    'report_listing.reason_prohibited',
    'report_listing.reason_scam',
    'report_listing.reason_duplicate',
  ];
  static const _accountReasons = <String>[
    'report_listing.reason_impersonation',
    'report_listing.reason_harassment',
    'report_listing.reason_suspicious',
    'report_listing.reason_inappropriate',
  ];

  bool get _isOther => _reason == 'other';
  bool get _canSend =>
      !_sending &&
      _reason != null &&
      (!_isOther || _otherController.text.trim().length >= 5);

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  void _selectTarget(_ReportTarget value) {
    setState(() {
      _target = value;
      _reason = null;
      _otherController.clear();
    });
  }

  Future<void> _send() async {
    if (!_canSend) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);

    final reasonLabel = _isOther
        ? _otherController.text.trim()
        : (_reason ?? '').tr();
    final product = widget.product;

    try {
      // No exige cuenta: si el visitante no inicio sesion, obtiene de forma
      // transparente una sesion de invitado firmada antes de reportar.
      await AnonSession.ensure();
      await ApiService.createReport(
        // Las publicaciones "Se busca" se adaptan a Product para reutilizar
        // la pantalla de detalle, pero en el backend viven en wanted_posts.
        // Enviarlas como product hace que /api/reports busque el id en la
        // tabla equivocada y rechace el reporte con 404.
        targetType: _target == _ReportTarget.product
            ? (product.isWantedPost ? 'wanted' : 'product')
            : 'user',
        targetId: _target == _ReportTarget.product
            ? product.id
            : product.seller.id,
        targetUserId: product.seller.id,
        reason: reasonLabel,
        details: _otherController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text('report_listing.sent'.tr())),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
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
              fallback: 'report_listing.send_error'.tr(),
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reasons = _target == _ReportTarget.product
        ? _productReasons
        : _accountReasons;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: context.colors.surface,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(14),
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
                            'report_listing.title'.tr(),
                            style: TextStyle(
                              color: context.colors.ink,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.4,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'report_listing.subtitle'.tr(),
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 13.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _sending ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _TargetSelector(target: _target, onChanged: _selectTarget),
                const SizedBox(height: 20),
                Text(
                  'report_listing.question'.tr(),
                  style: TextStyle(
                    color: context.colors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                for (final reason in [...reasons, 'other'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ReasonTile(
                      label:
                          (reason == 'other'
                                  ? 'report_listing.reason_other'
                                  : reason)
                              .tr(),
                      selected: _reason == reason,
                      onTap: () => setState(() => _reason = reason),
                    ),
                  ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: !_isOther
                      ? const SizedBox.shrink()
                      : Padding(
                          key: const ValueKey('other-field'),
                          padding: const EdgeInsets.only(top: 2, bottom: 10),
                          child: TextField(
                            controller: _otherController,
                            autofocus: true,
                            minLines: 3,
                            maxLines: 5,
                            maxLength: 500,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'report_listing.other_hint'.tr(),
                              filled: true,
                              fillColor: context.colors.background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: context.colors.border,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed: _canSend ? _send : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: AppColors.danger,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 19),
                  label: Text(
                    _sending
                        ? 'report_listing.sending'.tr()
                        : 'report_listing.send'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'report_listing.privacy'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TargetSelector extends StatelessWidget {
  const _TargetSelector({required this.target, required this.onChanged});

  final _ReportTarget target;
  final ValueChanged<_ReportTarget> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          for (final value in _ReportTarget.values)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: target == value
                        ? context.colors.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: target == value ? AppShadows.soft : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        value == _ReportTarget.product
                            ? Icons.inventory_2_outlined
                            : Icons.person_outline_rounded,
                        size: 18,
                        color: target == value
                            ? context.colors.primary
                            : context.colors.muted,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        (value == _ReportTarget.product
                                ? 'report_listing.target_product'
                                : 'report_listing.target_account')
                            .tr(),
                        style: TextStyle(
                          color: target == value
                              ? context.colors.ink
                              : context.colors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? context.colors.primary.withValues(alpha: .07)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(
          color: selected ? context.colors.primary : context.colors.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? context.colors.primary : context.colors.muted,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
