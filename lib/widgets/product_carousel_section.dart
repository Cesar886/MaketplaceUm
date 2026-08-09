import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import 'product_card.dart';
import 'product_card_skeleton.dart';

/// Carrusel horizontal de publicaciones con encabezado, para las secciones
/// "También te puede interesar" y "Más de este vendedor" del detalle.
///
/// Reutiliza [ProductCard] tal cual, sin variante propia: una tarjeta que se
/// viera distinta aquí obligaría a mantener dos estilos en paralelo y, peor,
/// haría dudar al usuario de si está viendo lo mismo que en el home.
///
/// Se omite por completo (ni encabezado ni hueco) cuando no hay nada que
/// mostrar y ya terminó de cargar: una sección vacía en medio del detalle no
/// informa de nada, solo separa lo que sí importa.
class ProductCarouselSection extends StatelessWidget {
  const ProductCarouselSection({
    super.key,
    required this.title,
    required this.products,
    required this.onProductTap,
    this.icon = Icons.auto_awesome_rounded,
    this.loading = false,
    this.compact = false,
    this.bleed = 0,
  });

  final String title;
  final List<Product> products;
  final void Function(Product product) onProductTap;
  final IconData icon;

  /// El detalle todavía está en vuelo: se pintan esqueletos en vez de la
  /// lista. Las publicaciones llegan en la MISMA respuesta que el resto del
  /// detalle, así que esto es el mismo estado de carga, no uno propio.
  final bool loading;

  /// Versión reducida para cuando el carrusel va anidado dentro de otra
  /// tarjeta (la del vendedor), donde el ancho útil es menor.
  final bool compact;

  /// Cuánto se sale la fila del padding lateral de la pantalla, en píxeles.
  ///
  /// Sirve para el asomo: con dos tarjetas del ancho del feed la fila ocupa
  /// justo el ancho útil y la tercera queda fuera de vista, así que nada
  /// sugiere que se desliza. Dejándola invadir el margen, la siguiente
  /// tarjeta se asoma por el borde. Se pasa el mismo valor que el padding
  /// horizontal de la pantalla; 0 la deja contenida.
  final double bleed;

  /// Cuántas tarjetas caben a lo ancho del área útil.
  ///
  /// Algo más que las dos del grid del home: aquí la tarjeta va en modo
  /// [ProductCard.dense] (sin descripción ni vistas), así que su fila de pie
  /// deja de ir apretada y la tarjeta aguanta ser más angosta sin que el
  /// contenido se estorbe. Dentro de la tarjeta del vendedor hay menos ancho
  /// útil, y ahí se muestran menos tarjetas en vez de tarjetas más chicas.
  double get _tarjetasVisibles => compact ? 2 : 2.3;

  /// Más alta que ancha, pero menos que en el grid del home (0.64): sin
  /// descripción y sin vistas hay dos bloques menos de texto que acomodar
  /// debajo de la foto.
  static const double _aspectRatioTarjeta = 0.66;

  static const double _separacion = 12;

  /// Ancho por debajo del cual la tarjeta deja de respirar: el título se
  /// parte en dos líneas y el pie ya no le cabe al alto calculado. En
  /// pantallas angostas se prefiere mostrar menos tarjetas antes que
  /// apretarlas: la fila se desliza igual.
  static const double _anchoMinimoTarjeta = 148;

  /// Cuántos esqueletos pintar mientras carga. Suficientes para llenar el
  /// ancho visible; ninguno más, que igual no se ve.
  static const int _esqueletos = 3;

  @override
  Widget build(BuildContext context) {
    if (!loading && products.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final anchoTarjeta = math.max(
          (constraints.maxWidth - _separacion) / _tarjetasVisibles,
          _anchoMinimoTarjeta,
        );
        final altoTarjeta = anchoTarjeta / _aspectRatioTarjeta;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.heading(15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: altoTarjeta,
              // La fila se pinta más ancha que su hueco (bleed) y recupera el
              // margen con su propio padding: las tarjetas siguen alineadas
              // con el texto, pero al deslizar entran y salen por el borde de
              // la pantalla en vez de cortarse contra el margen.
              child: OverflowBox(
                minWidth: constraints.maxWidth + bleed * 2,
                maxWidth: constraints.maxWidth + bleed * 2,
                child: loading
                    ? _FilaEsqueletos(ancho: anchoTarjeta, bleed: bleed)
                    : _FilaProductos(
                        products: products,
                        ancho: anchoTarjeta,
                        bleed: bleed,
                        onProductTap: onProductTap,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Entrada de la fila ya cargada: fade + un desplazamiento corto hacia
/// arriba. Corto y rápido (110 ms) porque el resto del detalle ya está en
/// pantalla: lo que se busca es que la sección se asiente, no que se anuncie.
class _FilaProductos extends StatelessWidget {
  const _FilaProductos({
    required this.products,
    required this.ancho,
    required this.bleed,
    required this.onProductTap,
  });

  final List<Product> products;
  final double ancho;
  final double bleed;
  final void Function(Product product) onProductTap;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 110),
      curve: AppAnimations.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Devuelve el margen que el bleed le quitó a la fila, para que la
        // primera tarjeta quede alineada con el texto de las secciones de
        // arriba y no pegada al borde de la pantalla.
        padding: EdgeInsets.symmetric(horizontal: bleed),
        clipBehavior: Clip.none,
        itemCount: products.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: ProductCarouselSection._separacion),
        itemBuilder: (context, index) {
          final product = products[index];
          return ProductCard(
            product: product,
            width: ancho,
            // Foto, precio y nombre: lo que decide si vale la pena tocar.
            // La descripción y las vistas son para comparar en el feed, no
            // para una fila de apoyo dentro de otra publicación.
            dense: true,
            onTap: () => onProductTap(product),
            // El Hero es del carrusel de fotos del detalle en el que ya
            // estamos parados: dos widgets con la misma tag en pantalla
            // rompen la animación al navegar.
            heroEnabled: false,
          );
        },
      ),
    );
  }
}

class _FilaEsqueletos extends StatelessWidget {
  const _FilaEsqueletos({required this.ancho, required this.bleed});

  final double ancho;
  final double bleed;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: bleed),
      physics: const NeverScrollableScrollPhysics(),
      clipBehavior: Clip.none,
      itemCount: ProductCarouselSection._esqueletos,
      separatorBuilder: (_, _) =>
          const SizedBox(width: ProductCarouselSection._separacion),
      itemBuilder: (context, _) =>
          SizedBox(width: ancho, child: const ProductCardSkeleton(dense: true)),
    );
  }
}
