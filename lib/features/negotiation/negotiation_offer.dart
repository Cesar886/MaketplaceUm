import 'dart:convert';

const _negotiationPrefix = '__UM_NEGOTIATION_V1__:';

class NegotiationOffer {
  const NegotiationOffer({
    required this.productId,
    required this.productTitle,
    required this.listPrice,
    required this.amount,
    required this.senderRole,
    this.replyToOfferId,
  });

  factory NegotiationOffer? fromMessageText(String text) {
    if (!text.startsWith(_negotiationPrefix)) return null;
    try {
      final encoded = text.substring(_negotiationPrefix.length);
      final normalized = base64Url.normalize(encoded);
      final json = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (json is! Map<String, dynamic> || json['kind'] != 'proposal') {
        return null;
      }
      final listPrice = json['listPrice'];
      final amount = json['amount'];
      final role = json['senderRole'];
      if (json['productId'] is! String ||
          json['productTitle'] is! String ||
          listPrice is! num ||
          amount is! num ||
          (role != 'buyer' && role != 'seller')) {
        return null;
      }
      return NegotiationOffer(
        productId: json['productId'] as String,
        productTitle: json['productTitle'] as String,
        listPrice: listPrice.toDouble(),
        amount: amount.toDouble(),
        senderRole: role as String,
        replyToOfferId: json['replyToOfferId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  final String productId;
  final String productTitle;
  final double listPrice;
  final double amount;
  final String senderRole;
  final String? replyToOfferId;

  bool get isCounterOffer => replyToOfferId != null;
  double get savings => listPrice - amount;
  int get discountPercent => listPrice <= 0
      ? 0
      : ((listPrice - amount) * 100 / listPrice).round().clamp(0, 100);
}

String negotiationMessagePreview(String text) {
  final offer = NegotiationOffer.fromMessageText(text);
  if (offer == null) return text;
  final label = offer.isCounterOffer ? 'Contraoferta' : 'Oferta';
  return '💎 $label: \$${_formatAmount(offer.amount)}';
}

String _formatAmount(double amount) {
  final whole = amount.floor();
  final cents = ((amount - whole) * 100).round();
  final formatted = whole.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match.group(1)},',
  );
  return cents == 0 ? formatted : '$formatted.${cents.toString().padLeft(2, '0')}';
}
