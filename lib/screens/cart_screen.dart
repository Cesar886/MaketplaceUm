import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../models.dart';
import '../widgets/badges.dart';
import '../widgets/mock_product_image.dart';
import 'auth/login_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  List<CartItem> _items = [];
  List<int> _quantities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCart();
  }

  Future<void> _loadCart() async {
    try {
      final items = await ApiService.getCart();
      if (!mounted) return;
      setState(() {
        _items = items;
        _quantities = items.map((item) => item.quantity).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int get _subtotal {
    var total = 0;
    for (var i = 0; i < _items.length; i++) {
      total += _priceValue(_items[i].product.price) * _quantities[i];
    }
    return total;
  }

  int get _estimatedSavings {
    var total = 0;
    for (var i = 0; i < _items.length; i++) {
      final product = _items[i].product;
      if (product.previousPrice == null) continue;
      total +=
          (_priceValue(product.previousPrice!) - _priceValue(product.price)) *
          _quantities[i];
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (_loading) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Carrito')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shopping_bag_outlined,
                    size: 64, color: AppColors.muted),
                const SizedBox(height: 20),
                Text(
                  'Tu carrito',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Inicia sesión para guardar productos y coordinar compras.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const LoginScreen()),
                    ),
                    child: const Text('Iniciar sesión'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Carrito')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          _CartCountBadge(
            count: _quantities.fold<int>(
              0,
              (sum, quantity) => sum + quantity,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Productos guardados para coordinar compra dentro del campus.',
            style: TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('El carrito esta vacio.',
                    style: TextStyle(color: AppColors.muted)),
              ),
            )
          else
            for (var i = 0; i < _items.length; i++) ...[
            _CartItemTile(
              item: _items[i],
              quantity: _quantities[i],
              onAdd: () async {
                final newQty = _quantities[i] + 1;
                setState(() => _quantities[i] = newQty);
                try {
                  await ApiService.updateCartQuantity(_items[i].id, newQty);
                } catch (_) {
                  // Silently fail — estado local ya se actualizó
                }
              },
              onRemove: () async {
                if (_quantities[i] <= 1) return;
                final newQty = _quantities[i] - 1;
                setState(() => _quantities[i] = newQty);
                try {
                  await ApiService.updateCartQuantity(_items[i].id, newQty);
                } catch (_) {}
              },
            ),
            const SizedBox(height: 12),
          ],
          if (_items.isNotEmpty) ...[
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
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Guardar para despues'),
          ),
        ],
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shopping_bag_outlined,
            color: AppColors.primary,
            size: 17,
          ),
          const SizedBox(width: 6),
          Text(
            '$count productos',
            style: const TextStyle(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w700,
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: product.isOffer
              ? AppColors.orange.withValues(alpha: 0.24)
              : AppColors.border,
        ),
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
                              fontWeight: FontWeight.w700,
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
                          Product.formatPrice(product.price),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        if (product.previousPrice != null)
                          Text(
                            Product.formatPrice(product.previousPrice!),
                            style: const TextStyle(
                              color: AppColors.muted,
                              decoration: TextDecoration.lineThrough,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.seller.name,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
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
                      Icons.place_outlined,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        item.meetingPoint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w500,
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
        color: AppColors.surfaceMuted,
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
              style: const TextStyle(fontWeight: FontWeight.w700),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
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
            accent: AppColors.success,
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
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: accent ?? AppColors.primaryDark,
              fontSize: highlighted ? 22 : 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

int _priceValue(double price) {
  return price.round();
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
