import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../mock_data.dart';
import '../models.dart';
import '../widgets/badges.dart';
import '../widgets/mock_product_image.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late final List<int> _quantities = mockCartItems
      .map((item) => item.quantity)
      .toList();

  int get _subtotal {
    var total = 0;
    for (var i = 0; i < mockCartItems.length; i++) {
      total += _priceValue(mockCartItems[i].product.price) * _quantities[i];
    }
    return total;
  }

  int get _estimatedSavings {
    var total = 0;
    for (var i = 0; i < mockCartItems.length; i++) {
      final product = mockCartItems[i].product;
      if (product.previousPrice == null) continue;
      total +=
          (_priceValue(product.previousPrice!) - _priceValue(product.price)) *
          _quantities[i];
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Carrito',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              _CartCountBadge(
                count: _quantities.fold<int>(
                  0,
                  (sum, quantity) => sum + quantity,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Productos guardados para coordinar compra dentro del campus.',
            style: TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < mockCartItems.length; i++) ...[
            _CartItemTile(
              item: mockCartItems[i],
              quantity: _quantities[i],
              onAdd: () => setState(() => _quantities[i]++),
              onRemove: () => setState(() {
                if (_quantities[i] > 1) _quantities[i]--;
              }),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          _CartSummary(subtotal: _subtotal, savings: _estimatedSavings),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () =>
                _showMockMessage(context, 'Solicitud de compra simulada'),
            icon: const Icon(Icons.chat_rounded),
            label: const Text('Coordinar compra'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _showMockMessage(
              context,
              'Carrito guardado localmente como mock',
            ),
            icon: const Icon(Icons.bookmark_add_rounded),
            label: const Text('Guardar para despues'),
          ),
        ],
      ),
    );
  }

  void _showMockMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CartCountBadge extends StatelessWidget {
  const _CartCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.champagne,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.premiumBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shopping_bag_rounded,
            color: AppColors.primaryDark,
            size: 17,
          ),
          const SizedBox(width: 6),
          Text(
            '$count items',
            style: const TextStyle(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final CartItem item;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final product = item.product;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: product.isOffer
              ? AppColors.orange.withValues(alpha: 0.45)
              : AppColors.border,
        ),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                child: MockProductImage(
                  product: product,
                  height: 88,
                  showFeaturedBadge: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            product.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (product.isOffer)
                          OfferBadge(
                            label: product.discountLabel,
                            compact: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 7,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        Text(
                          product.price,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        if (product.previousPrice != null)
                          Text(
                            product.previousPrice!,
                            style: const TextStyle(
                              color: AppColors.muted,
                              decoration: TextDecoration.lineThrough,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.seller.name,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.place_rounded,
                      size: 16,
                      color: AppColors.teal,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        item.meetingPoint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _QuantityStepper(
                quantity: quantity,
                onAdd: onAdd,
                onRemove: onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.remove_rounded),
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _CartSummary extends StatelessWidget {
  const _CartSummary({required this.subtotal, required this.savings});

  final int subtotal;
  final int savings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.premiumBorder.withValues(alpha: 0.7),
        ),
        boxShadow: AppShadows.lifted,
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: 'Subtotal',
            value: _money(subtotal),
            highlighted: true,
          ),
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'Ahorro estimado',
            value: _money(savings),
            accent: AppColors.gold,
          ),
          const SizedBox(height: 10),
          const _SummaryRow(label: 'Entrega', value: 'A coordinar en campus'),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.highlighted = false,
    this.accent,
  });

  final String label;
  final String value;
  final bool highlighted;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: accent ?? Colors.white,
            fontSize: highlighted ? 22 : 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

int _priceValue(String price) {
  final digits = price.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digits) ?? 0;
}

String _money(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return '\$${buffer.toString()}';
}
