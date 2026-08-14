import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import 'badges.dart';
import 'mock_product_image.dart';
import 'price_tag.dart';
import 'views_counter.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.width,
    this.horizontal = false,
    this.heroEnabled = true,
    this.animationValue,
    this.dense = false,
    this.showPrice = true,
  });

  final Product product;
  final VoidCallback? onTap;
  final double? width;
  final bool horizontal;
  final bool heroEnabled;

  /// Oculta el precio y el espacio que reserva. Para carruseles donde la
  /// tarjeta es solo una vitrina (p.ej. "productos de este vendedor") y el
  /// precio no aporta al propósito de esa sección.
  final bool showPrice;

  /// Versión aligerada: sin descripción y sin contador de vistas.
  ///
  /// Para los carruseles del detalle de producto, donde la tarjeta es un
  /// apoyo y no el contenido principal: ahí lo que se decide de un vistazo
  /// es foto, precio y nombre, y el resto solo hace la tarjeta más alta y
  /// más densa de lo que esa decisión necesita. En el feed, en cambio, la
  /// tarjeta ES la pantalla y esos datos sí ayudan a comparar, así que el
  /// valor por defecto no cambia nada.
  final bool dense;

  /// 0.0 → invisible, 1.0 → fully visible. Null = sin animación.
  final double? animationValue;

  @override
  Widget build(BuildContext context) {
    Widget card = _buildCard(context);

    if (animationValue != null) {
      final anim = animationValue!.clamp(0.0, 1.0);
      card = Opacity(
        opacity: Curves.easeOut.transform(anim),
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - Curves.easeOutCubic.transform(anim))),
          child: card,
        ),
      );
    }

    if (width == null) return card;
    return SizedBox(width: width, child: card);
  }

  Widget _buildCard(BuildContext context) {
    final hasAccent = product.isOffer || product.isFeatured;
    final borderColor = product.isOffer
        ? context.colors.primary
        : product.isFeatured
        ? context.colors.accentTintBorder
        : Colors.transparent;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: hasAccent ? AppShadows.lifted : AppShadows.soft,
      ),
      child: Material(
        color: context.colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor, width: hasAccent ? 1.5 : 0),
        ),
        child: InkWell(
          onTap: onTap,
          splashColor: context.colors.primary.withValues(alpha: 0.06),
          highlightColor: context.colors.primary.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: horizontal
                ? _HorizontalProductCard(
                    product: product,
                    heroEnabled: heroEnabled,
                    showPrice: showPrice,
                  )
                : _GridProductCard(
                    product: product,
                    heroEnabled: heroEnabled,
                    dense: dense,
                    showPrice: showPrice,
                  ),
          ),
        ),
      ),
    );
  }
}

class _GridProductCard extends StatelessWidget {
  const _GridProductCard({
    required this.product,
    required this.heroEnabled,
    this.dense = false,
    this.showPrice = true,
  });

  final Product product;
  final bool heroEnabled;
  final bool dense;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroProductImage(
          product: product,
          enabled: heroEnabled,
          child: AspectRatio(
            aspectRatio: 4 / 3.4,
            child: MockProductImage(product: product, height: double.infinity),
          ),
        ),
        const SizedBox(height: 8),
        if (showPrice) ...[
          PriceTag(product: product),
          const SizedBox(height: 4),
        ],
        Text(
          product.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.label(
            13.5,
            weight: FontWeight.w700,
            color: context.colors.ink,
          ),
        ),
        // Los atributos clave de la categoría (talla, estado, "Acepta
        // mascotas") TOMAN EL LUGAR de la descripción, no se suman a ella: la
        // celda tiene alto fijo y no hay renglón de sobra. Ver
        // [AtributosDestacadosRow] para por qué el cambio también conviene
        // aunque hubiera espacio.
        //
        // En `dense` no va ninguno de los dos: esa variante ya renunció a
        // esta línea por falta de alto.
        if (!dense) ...[
          const SizedBox(height: 2),
          if (product.atributosDestacados.isNotEmpty)
            AtributosDestacadosRow(atributos: product.atributosDestacados)
          else
            Text(
              product.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body(11.5, color: context.colors.muted),
            ),
        ],
        const Spacer(),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                product.publishedAgo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body(11, color: context.colors.muted),
              ),
            ),
            if (!dense) ...[
              ViewsCounter(views: product.views),
              const SizedBox(width: 6),
            ],
            productStatusBadge(product),
          ],
        ),
      ],
    );
  }
}

class _HorizontalProductCard extends StatelessWidget {
  const _HorizontalProductCard({
    required this.product,
    required this.heroEnabled,
    this.showPrice = true,
  });

  final Product product;
  final bool heroEnabled;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: _HeroProductImage(
            product: product,
            enabled: heroEnabled,
            child: MockProductImage(product: product, height: 96),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showPrice) ...[
                PriceTag(product: product),
                const SizedBox(height: 5),
              ],
              Text(
                product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label(
                  13.5,
                  weight: FontWeight.w700,
                  color: context.colors.ink,
                ),
              ),
              const SizedBox(height: 3),
              // Mismo intercambio que en la tarjeta de cuadrícula: los
              // atributos sustituyen a la descripción.
              if (product.atributosDestacados.isNotEmpty)
                AtributosDestacadosRow(atributos: product.atributosDestacados)
              else
                Text(
                  product.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body(12, color: context.colors.muted),
                ),
              const Spacer(),
              Row(
                children: [
                  Icon(
                    product.category.icon,
                    size: 14,
                    color: normalizeCategoryColor(
                      product.category.color,
                      Theme.of(context).brightness,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      product.category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        11,
                        color: context.colors.muted,
                      ),
                    ),
                  ),
                  Text(
                    product.publishedAgo,
                    style: AppTypography.body(11, color: context.colors.muted),
                  ),
                  const SizedBox(width: 6),
                  ViewsCounter(views: product.views),
                  const SizedBox(width: 6),
                  productStatusBadge(product),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroProductImage extends StatelessWidget {
  const _HeroProductImage({
    required this.product,
    required this.enabled,
    required this.child,
  });

  final Product product;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: child,
    );

    if (!product.isAvailable) {
      content = Stack(
        children: [
          content,
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: Colors.white.withValues(alpha: 0.65),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    'Agotado',
                    style: AppTypography.label(
                      13,
                      weight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (!enabled) return content;
    return Hero(tag: 'product-${product.id}', child: content);
  }
}
