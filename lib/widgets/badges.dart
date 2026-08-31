import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';

// TODO: Destacar publicaciones pendiente para próxima actualización - no
// eliminar. Este badge ya no se pinta en ninguna parte mientras
// kDestacarHabilitado sea false: todos sus puntos de uso (carrusel, foto de
// la tarjeta, título del detalle) están detrás de esa bandera. Se reactiva
// al ponerla en true (ver features/highlight/destacar_flag.dart).
class FeaturedBadge extends StatelessWidget {
  const FeaturedBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Destacado y oferta comparten el oro a propósito (es el único acento
    // del sistema), pero NO el tratamiento: destacado va en crema con texto
    // latón, oferta va en oro sólido con texto navy. Así el descuento
    // siempre pesa más en la jerarquía visual que el "patrocinado".
    return _Badge(
      icon: Icons.star_rounded,
      label: 'badge.featured'.tr(),
      foreground: context.colors.accent,
      background: context.colors.accentTint,
      border: context.colors.accentTintBorder,
      compact: compact,
    );
  }
}

class OfferBadge extends StatelessWidget {
  const OfferBadge({super.key, this.label, this.compact = false});

  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Oro sólido con texto navy: el descuento es la razón por la que alguien
    // se detiene en la tarjeta, así que se lee como una etiqueta pegada al
    // producto y no como un texto flotando encima de la foto.
    return _Badge(
      icon: Icons.local_offer_rounded,
      label: label ?? 'badge.offer'.tr(),
      foreground: context.colors.onPrimary,
      background: context.colors.primary,
      compact: compact,
    );
  }
}

/// Etiqueta de descuento anclada a la esquina superior izquierda de la foto.
///
/// A diferencia de [OfferBadge] (píldora suelta que puede ir en cualquier
/// fila), esta va pegada al borde: solo redondea las dos esquinas interiores,
/// así se lee como una etiqueta adherida al producto y no como un elemento
/// flotando encima de la imagen.
class OfferCornerTag extends StatelessWidget {
  const OfferCornerTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.primary,
        borderRadius: BorderRadius.only(
          bottomRight: Radius.circular(10),
          topLeft: Radius.circular(10),
        ),
      ),
      child: Text(
        label,
        style: AppTypography.label(
          11,
          weight: FontWeight.w800,
          color: context.colors.onPrimary,
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final ListingStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color color, Color background) = switch (status) {
      ListingStatus.active => (c.success, c.successBg),
      // TODO: Destacar publicaciones pendiente para próxima actualización -
      // no eliminar. Este caso queda inalcanzable en la práctica (nadie puede
      // dejar una publicación en estado 'featured' con la feature apagada),
      // pero el enum debe seguir siendo exhaustivo.
      ListingStatus.featured => (c.accent, c.accentTint),
      ListingStatus.expired => (c.danger, c.neutralBg),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Insignia de cuenta verificada, que se muestra junto al nombre del usuario
/// en el perfil, en las tarjetas de publicaciones y en cualquier otro lugar
/// donde aparezca su nombre — solo si `seller.verified == true`.
///
/// Los tres tipos comparten el MISMO ícono de check y el MISMO color azul
/// (estilo Meta/Instagram/Facebook) a propósito: verificarse significa lo
/// mismo en los tres casos (el backend comprobó automáticamente un dato
/// real de contacto), solo cambia qué dato se comprobó y la etiqueta que
/// se muestra en la variante no compacta.
class InsigniaVerificada extends StatelessWidget {
  const InsigniaVerificada({
    super.key,
    required this.tipo,
    this.compact = false,
    this.size = 16,
  }) : _tipoCrudo = null;

  /// Variante para construir la insignia con el `tipoCuenta` tal como llega
  /// del backend ('estudiante' | 'negocio' | 'particular'), sin tener que
  /// mapear el string a [AccountType] en cada call site.
  const InsigniaVerificada.desdeTipo(
    String tipoCuenta, {
    super.key,
    this.compact = false,
    this.size = 16,
  }) : _tipoCrudo = tipoCuenta,
       tipo = AccountType.particular;

  final AccountType tipo;
  final bool compact;

  /// Tamaño del ícono en la variante compacta. Existe para que los call
  /// sites conserven el tamaño que ya tenían.
  final double size;
  final String? _tipoCrudo;

  /// Un tipo desconocido cae a 'particular', el estilo más neutro: nunca se
  /// le atribuye a una cuenta un nivel de verificación que no tiene.
  AccountType get _tipoEfectivo => _tipoCrudo == null
      ? tipo
      : (_tipoCrudo.toAccountType ?? AccountType.particular);

  @override
  Widget build(BuildContext context) {
    final etiqueta = switch (_tipoEfectivo) {
      AccountType.estudiante => 'badge.verified_student'.tr(),
      AccountType.negocio => 'badge.verified_business'.tr(),
      AccountType.particular => 'badge.verified'.tr(),
    };
    const color = AppColors.verifiedBlue;

    // En modo compacto (tarjetas de producto, listas) solo cabe el ícono: la
    // etiqueta completa competiría con el título del producto.
    if (compact) {
      return Icon(Icons.verified_rounded, size: size, color: color);
    }

    return _Badge(
      icon: Icons.verified_rounded,
      label: etiqueta,
      foreground: color,
      background: color.withValues(alpha: 0.08),
      compact: false,
    );
  }
}

/// Badge de solo-lectura para compradores: renderiza directamente el
/// [ComputedStatus] que ya llegó calculado desde el backend
/// (`computeProductStatus` en `products.js`, jerarquía de 5 niveles:
/// manual > inventario > días disponibles > horario > disponible). El
/// selector de edición (`publish_product_screen.dart`) solo expone los 4
/// estados manuales pegajosos, no estos 8.
class AvailabilityBadge extends StatelessWidget {
  const AvailabilityBadge({
    super.key,
    required this.status,
    this.nextAvailableDay,
    this.opensAt,
    this.onPhoto = false,
  });

  final ComputedStatus status;
  final String? nextAvailableDay;
  final String? opensAt;

  /// Variante para cuando el badge va ENCIMA de la foto del producto y no
  /// sobre la superficie de la tarjeta.
  ///
  /// Los tintes suaves (`successBg`, `accentTint`) están calculados para
  /// leerse sobre `surface`; sobre una foto cualquiera pueden caer sobre un
  /// fondo del mismo tono y desaparecer. Aquí el relleno pasa a ser la
  /// superficie opaca de la tarjeta con una sombra corta, así el badge se
  /// separa de la foto sin cambiar el color del texto, que es lo que
  /// codifica el estado.
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Tres familias, no ocho colores: disponible (sage), pendiente/con fecha
    // (oro) y no disponible (gris). Ocho tonos distintos obligarían a leer
    // el texto para saber si puedo comprar; tres se distinguen de reojo.
    final (String label, Color foreground, Color background) = switch (status) {
      ComputedStatus.available => (
        'status.available'.tr(),
        c.success,
        c.successBg,
      ),
      ComputedStatus.soldOut => (
        'status.sold_out'.tr(),
        c.mutedStrong,
        c.neutralBg,
      ),
      ComputedStatus.availableOtherDay => (
        nextAvailableDay != null
            ? 'status.available_on'.tr(namedArgs: {'day': nextAvailableDay!})
            : 'status.coming_soon'.tr(),
        c.accent,
        c.accentTint,
      ),
      ComputedStatus.closed => (
        opensAt != null
            ? 'status.available_at'.tr(namedArgs: {'time': opensAt!})
            : 'status.closed'.tr(),
        c.accent,
        c.accentTint,
      ),
      ComputedStatus.reserved => (
        'status.reserved'.tr(),
        c.accent,
        c.accentTint,
      ),
      ComputedStatus.negotiating => (
        'status.negotiating'.tr(),
        c.accent,
        c.surfaceMuted,
      ),
      ComputedStatus.sold => ('status.sold'.tr(), c.mutedStrong, c.neutralBg),
      ComputedStatus.paused => (
        'status.paused'.tr(),
        c.mutedStrong,
        c.neutralBg,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: onPhoto ? c.surface : background,
        borderRadius: BorderRadius.circular(999),
        boxShadow: onPhoto
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Badge de "Abierto"/"Cerrado" según el horario de atención del negocio.
/// A diferencia de [AvailabilityBadge] (que es por producto), este refleja
/// el horario general del vendedor — se usa en [BusinessHoursCard] y en el
/// detalle de producto junto al horario, no como badge de un producto.
class OpenStatusBadge extends StatelessWidget {
  const OpenStatusBadge({super.key, required this.isOpen});

  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final (Color foreground, Color background) = isOpen
        ? (context.colors.success, context.colors.successBg)
        : (context.colors.mutedStrong, context.colors.neutralBg);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isOpen ? 'status.open'.tr() : 'status.closed'.tr(),
        style: TextStyle(
          color: foreground,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Badge de estado de un producto: el badge de disponibilidad viene
/// enteramente calculado por el backend en [Product.computedStatus], así
/// que aquí solo se renderiza — no hay lógica de negocio en el cliente.
Widget productStatusBadge(Product product) {
  return AvailabilityBadge(
    status: product.computedStatus,
    nextAvailableDay: product.nextAvailableDay,
    opensAt: product.opensAt,
  );
}

/// "Responde rápido": la MEDIANA del tiempo de respuesta del vendedor está
/// por debajo del umbral del sistema. El umbral y el cálculo viven en el
/// backend — la app solo pinta el booleano.
///
/// Va en verde sage (el mismo de "Disponible") y no en oro: el oro está
/// reservado a lo que termina en una compra, y esto es una señal de
/// confianza sobre el vendedor, no sobre el producto.
class RespondeRapidoBadge extends StatelessWidget {
  const RespondeRapidoBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _Badge(
      icon: Icons.bolt_rounded,
      label: 'badge.fast_replies'.tr(),
      foreground: context.colors.success,
      background: context.colors.successBg,
      compact: compact,
    );
  }
}

/// Racha de publicación: semanas consecutivas en las que el vendedor publicó
/// algo. Solo cuenta publicar — ver `computeRachaPublicaciones` en el
/// backend.
class RachaBadge extends StatelessWidget {
  const RachaBadge({super.key, required this.semanas, this.compact = false});

  final int semanas;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _Badge(
      icon: Icons.local_fire_department_rounded,
      label: '$semanas semanas activo',
      foreground: context.colors.accent,
      background: context.colors.surfaceMuted,
      compact: compact,
    );
  }
}

/// Insignia del enigma escondido: la lleva quien lo resolvió, con la posición
/// en la que lo hizo (1 = fue el primero de toda la app).
///
/// Es el único rastro público de un juego que no se anuncia en ninguna parte,
/// así que la etiqueta no explica nada: dice "Enigma #3" y ya. Quien lo
/// resolvió sabe qué significa, y quien no, no debería enterarse por aquí —
/// esa es toda la gracia.
///
/// Va en latón sobre navy, la paleta de las pantallas del secreto
/// (screens/secreto/), y no en los colores del acento elegido: el resto de
/// insignias son métricas del mercado (verificación, constancia, rapidez) y
/// esta no lo es. Que desentone un poco es la intención.
class InsigniaEnigma extends StatelessWidget {
  const InsigniaEnigma({super.key, required this.posicion, this.compact = false});

  final int posicion;
  final bool compact;

  /// Latón, el acento del mundo secreto. Fijo en los dos temas: es el color
  /// de un objeto, no de una superficie, y en claro se lee igual de bien
  /// sobre su propio tinte que en oscuro.
  static const _laton = Color(0xFFA07F42);
  static const _latonEnOscuro = Color(0xFFD9BC7E);

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final color = oscuro ? _latonEnOscuro : _laton;

    return _Badge(
      icon: Icons.vpn_key_rounded,
      label: 'Enigma #$posicion',
      foreground: color,
      background: color.withValues(alpha: oscuro ? 0.14 : 0.10),
      border: color.withValues(alpha: 0.32),
      compact: compact,
    );
  }
}

/// Los 1-2 atributos clave de una publicación, para la tarjeta del listado:
/// la talla en ropa, el estado en libros, "Acepta mascotas" en hospedaje.
///
/// Cuáles son los decide el SERVIDOR (`atributosDestacados`), no esta clase.
/// La tarjeta aparece en el home, la búsqueda, el perfil del vendedor y los
/// carruseles del detalle: si cada pantalla eligiera por su cuenta, el mismo
/// producto se vería distinto según de dónde se llegó a él.
///
/// Se pinta en una sola línea de alto fijo, y OCUPA EL LUGAR de la línea de
/// descripción en la tarjeta (ver ProductCard) en vez de sumarse a ella. La
/// celda de la cuadrícula tiene alto fijo por `childAspectRatio` y los
/// resultados de búsqueda van dentro de un `SizedBox` de alto fijo (ver
/// `ProductGridMetrics.horizontalCardHeight`): ahí no
/// existe "queda un poco apretado", lo que sobra desborda y raya la pantalla
/// de amarillo. El alto va acotado (17 px) por la misma razón.
///
/// El intercambio con la descripción no es solo por espacio: la descripción
/// en la tarjeta es una primera línea truncada a mitad de una frase, mientras
/// que "M · Poco uso" es exactamente el dato con el que se decide si vale la
/// pena abrir la publicación.
class AtributosDestacadosRow extends StatelessWidget {
  const AtributosDestacadosRow({super.key, required this.atributos});

  final List<AtributoDestacado> atributos;

  @override
  Widget build(BuildContext context) {
    if (atributos.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 20,
      child: Row(
        children: [
          for (final (i, atributo) in atributos.indexed) ...[
            if (i > 0) const SizedBox(width: 5),
            // Loose, no `alignment`: un Container CON alignment se estira a
            // las constraints máximas que le den, y dentro de un Flexible
            // eso es todo el ancho libre de la tarjeta. Por eso "Nuevo"
            // salía como una barra de borde a borde y dos atributos se
            // repartían la fila entera truncándose ("Con garant…") aunque
            // los dos textos juntos midieran la mitad. Sin alignment el chip
            // mide lo que mide su texto, y el Flexible solo entra en acción
            // cuando de verdad no cabe.
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: context.colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: context.colors.border),
                ),
                child: Text(
                  atributo.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                    color: context.colors.mutedStrong,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    required this.compact,
    this.border,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final bool compact;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 11 : 12, color: foreground),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: compact ? 10 : 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
