import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../features/highlight/destacar_flag.dart';
import '../models.dart';
import '../utils/number_format.dart';
import 'badges.dart';
import 'mock_product_image.dart';
import 'price_tag.dart';

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

  /// Versión aligerada: sin descripción ni fila de atributos.
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
    // TODO: Destacar publicaciones pendiente para próxima actualización - no
    // eliminar. El realce visual de "destacado" (borde dorado + sombra
    // elevada) queda apagado mientras kDestacarHabilitado sea false; el de
    // oferta no cambia. Ver features/highlight/destacar_flag.dart.
    final destacado = kDestacarHabilitado && product.isFeatured;
    final hasAccent = product.isOffer || destacado;
    final borderColor = product.isOffer
        ? context.colors.primary
        : destacado
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
        // En `dense` no va descripción: esa variante ya renunció a esta línea
        // por falta de alto.
        if (!dense) ...[
          const SizedBox(height: 3),
          SizedBox(
            width: double.infinity,
            child: Text(
              product.description,
              textAlign: TextAlign.justify,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body(
                11,
                color: context.colors.muted,
              ).copyWith(height: 1.25),
            ),
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
            const SizedBox(width: 6),
            // El badge también cede ancho, mismo criterio que la fila de la
            // tarjeta horizontal: con el badge a su tamaño natural, la fila
            // solo aguantaba mientras el texto del estado no creciera, y
            // subirle el grosor de w600 a w700 bastó para desbordarla en la
            // tarjeta angosta del carrusel. Flexible deja que se recorte
            // (su Text ya es maxLines 1 con ellipsis) en vez de pintar la
            // barra amarilla.
            Flexible(child: productStatusBadge(product)),
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
              const SizedBox(height: 2),
              // Aquí SÍ se hace el intercambio atributos↔descripción; la
              // celda de la cuadrícula ya no lo hace (se quedó con la
              // descripción a dos renglones). Esta tarjeta es más ancha y la
              // fila de badges cabe en un solo renglón, que es lo que en la
              // celda angosta del home no se cumplía.
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
                    size: 13,
                    color: normalizeCategoryColor(
                      product.category.color,
                      Theme.of(context).brightness,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Los dos textos ceden espacio y se recortan; el ícono de
                  // categoría y el badge de estado no. Las vistas ya se
                  // muestran sobre la foto (ver [_ViewsPill]), así que esta
                  // fila solo reparte tres cosas y no cuatro: con un solo
                  // Expanded, "hace 2 días" empujaba al badge fuera del
                  // borde. Con ambos flexibles la fila se aprieta en vez de
                  // desbordarse.
                  Flexible(
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
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      product.publishedAgo,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        11,
                        color: context.colors.muted,
                      ),
                    ),
                  ),
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
      // Las vistas van SOBRE la foto y no en la fila de texto de abajo: esa
      // fila ya reparte fecha de publicación y badge de estado, y en la
      // tarjeta horizontal (226 px, cuatro elementos) no sobraba margen —
      // cualquier variación de fuente la desbordaba. Sacar las vistas de ahí
      // libera la fila Y le da a la tarjeta un acabado más "marketplace
      // premium" (Depop/Vinted) en vez de una hilera de texto plano.
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          if (product.isAvailable)
            Positioned(
              right: 6,
              bottom: 6,
              child: _ViewsPill(views: product.views),
            ),
        ],
      ),
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
                    'status.sold_out'.tr(),
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

/// Contador de vistas en cápsula oscura, anclado a la esquina de la foto.
///
/// Fondo negro translúcido (no [context.colors.surface] como
/// [AvailabilityBadge.onPhoto]) a propósito: esta no es una señal de estado
/// que tenga que competir por atención, es un dato ambiental de fondo — el
/// tratamiento "chapa oscura sobre la foto" la mantiene discreta sin
/// importar qué tan clara u oscura sea la imagen de abajo.
class _ViewsPill extends StatelessWidget {
  const _ViewsPill({required this.views});

  final int views;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_rounded, size: 11, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              formatCompactNumber(views),
              style: AppTypography.label(
                10,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
