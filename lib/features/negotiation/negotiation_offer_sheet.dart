import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../models.dart';

Future<double?> showNegotiationOfferSheet({
  required BuildContext context,
  required String productTitle,
  required double listPrice,
  double? previousOffer,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NegotiationOfferSheet(
      productTitle: productTitle,
      listPrice: listPrice,
      previousOffer: previousOffer,
    ),
  );
}

class _NegotiationOfferSheet extends StatefulWidget {
  const _NegotiationOfferSheet({
    required this.productTitle,
    required this.listPrice,
    this.previousOffer,
  });

  final String productTitle;
  final double listPrice;
  final double? previousOffer;

  @override
  State<_NegotiationOfferSheet> createState() => _NegotiationOfferSheetState();
}

class _NegotiationOfferSheetState extends State<_NegotiationOfferSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final initial = widget.previousOffer ?? widget.listPrice * .9;
    _controller = TextEditingController(text: initial.round().toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(
    _controller.text.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.]'), ''),
  );

  bool get _valid {
    final amount = _amount;
    return amount != null && amount >= 1 && amount < widget.listPrice;
  }

  void _setPercent(int percent) {
    final amount = widget.listPrice * (1 - percent / 100);
    setState(() => _controller.text = amount.round().toString());
  }

  @override
  Widget build(BuildContext context) {
    final amount = _amount;
    final discount = amount == null || widget.listPrice <= 0
        ? 0
        : ((widget.listPrice - amount) * 100 / widget.listPrice)
              .round()
              .clamp(0, 100);
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [context.colors.primary, context.colors.accent],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: context.colors.primary.withValues(alpha: .22),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.handshake_rounded, color: Colors.white),
            ),
            const SizedBox(height: 14),
            Text(
              widget.previousOffer == null
                  ? 'negotiation.make_offer'.tr()
                  : 'negotiation.counter_offer'.tr(),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              widget.productTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.colors.muted),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
              decoration: InputDecoration(
                prefixText: '\$ ',
                suffixText: ' MXN',
                helperText: 'negotiation.list_price'.tr(
                  namedArgs: {'price': Product.formatPrice(widget.listPrice)},
                ),
                errorText: _controller.text.isNotEmpty && !_valid
                    ? 'negotiation.invalid_amount'.tr()
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final percent in [5, 10, 15])
                  ChoiceChip(
                    label: Text('-$percent%'),
                    selected: discount == percent,
                    onSelected: (_) => _setPercent(percent),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.accent.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 18, color: context.colors.accent),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'negotiation.safe_note'.tr(),
                      style: TextStyle(fontSize: 12.5, color: context.colors.mutedStrong),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _valid ? () => Navigator.pop(context, _amount) : null,
                icon: const Icon(Icons.send_rounded),
                label: Text('negotiation.send_offer'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
