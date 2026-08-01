import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';

/// Etiqueta de precio tipo "colgante de puesto" — el elemento firma de MercadoUm.
///
/// En oferta: etiqueta cempasúchil con ojal perforado y ligera rotación,
/// como una etiqueta de cartulina amarrada con hilo. Sin oferta: precio
/// plano en Baloo 2.
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

    // Con oferta: etiqueta de puesto — colgante cempasúchil con ojal, rotada.
    final holeSize = large ? 8.0 : 6.0;
    return Transform.rotate(
      angle: -3 * math.pi / 180,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.amber,
              borderRadius: BorderRadius.circular(large ? 10 : 8),
              boxShadow: large ? AppShadows.amber : null,
            ),
            child: Padding(
              padding: EdgeInsets.only(
                left: large ? 22 : 16,
                right: large ? 12 : 8,
                top: large ? 7 : 4,
                bottom: large ? 7 : 4,
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
          ),
          Positioned(
            left: large ? 8 : 6,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                width: holeSize,
                height: holeSize,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.amberDark.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
