import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';

/// Etiqueta de precio con forma asimétrica — el elemento firma de MercadoUm.
///
/// En oferta: fondo ámbar, esquina superior izquierda recta (simulando etiqueta doblada).
/// Sin oferta: solo texto plano en Sora Bold.
class PriceTag extends StatelessWidget {
  const PriceTag({super.key, required this.product, this.large = false});

  final Product product;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return _PriceTagContent(product: product, large: large);
  }
}

/// Versión animada: escala desde 0.78 con fade al aparecer (efecto stamp).
class AnimatedPriceTag extends StatelessWidget {
  const AnimatedPriceTag({
    super.key,
    required this.product,
    required this.animation,
    this.large = false,
  });

  final Product product;
  final Animation<double> animation;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.78, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: AppAnimations.entrance),
        ),
        alignment: Alignment.centerLeft,
        child: _PriceTagContent(product: product, large: large),
      ),
    );
  }
}

class _PriceTagContent extends StatelessWidget {
  const _PriceTagContent({required this.product, required this.large});

  final Product product;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final hasOffer = product.isOffer;
    final priceSize = large ? 26.0 : 17.0;
    final oldPriceSize = large ? 14.0 : 12.0;
    final discountSize = large ? 13.0 : 11.0;

    if (!hasOffer) {
      // Sin oferta: precio plano, sin contenedor
      return Text(
        Product.formatPrice(product.price),
        style: AppTypography.price(priceSize, color: AppColors.ink),
      );
    }

    // Con oferta: etiqueta ámbar asimétrica
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.amber,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(3),       // esquina "doblada" — el detalle que nos identifica
          topRight: Radius.circular(13),
          bottomRight: Radius.circular(13),
          bottomLeft: Radius.circular(13),
        ),
        boxShadow: large ? AppShadows.amber : null,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: large ? 12 : 8,
          vertical: large ? 7 : 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              Product.formatPrice(product.price),
              style: AppTypography.price(priceSize, color: AppColors.amberDark),
            ),
            if (product.previousPrice != null) ...[
              const SizedBox(width: 6),
              Text(
                Product.formatPrice(product.previousPrice!),
                style: AppTypography.body(
                  oldPriceSize,
                  color: AppColors.amberDark.withValues(alpha: 0.60),
                ).copyWith(decoration: TextDecoration.lineThrough),
              ),
              if (product.discountLabel != null) ...[
                const SizedBox(width: 5),
                Text(
                  product.discountLabel!,
                  style: AppTypography.label(
                    discountSize,
                    weight: FontWeight.w800,
                    color: AppColors.amberDark,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
