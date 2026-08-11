import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';

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
      label: 'Destacado',
      foreground: context.colors.gold,
      background: context.colors.premiumBg,
      border: context.colors.premiumBorder,
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
      label: label ?? 'Oferta',
      foreground: AppColors.onGold,
      background: AppColors.gold,
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
      decoration: const BoxDecoration(
        color: AppColors.gold,
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
          color: AppColors.onGold,
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
      ListingStatus.featured => (c.gold, c.premiumBg),
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
      AccountType.estudiante => 'Estudiante verificado',
      AccountType.negocio => 'Negocio verificado',
      AccountType.particular => 'Verificado',
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
  });

  final ComputedStatus status;
  final String? nextAvailableDay;
  final String? opensAt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Tres familias, no ocho colores: disponible (sage), pendiente/con fecha
    // (oro) y no disponible (gris). Ocho tonos distintos obligarían a leer
    // el texto para saber si puedo comprar; tres se distinguen de reojo.
    final (String label, Color foreground, Color background) = switch (status) {
      ComputedStatus.available => ('Disponible', c.success, c.successBg),
      ComputedStatus.soldOut => ('Agotado', c.mutedStrong, c.neutralBg),
      ComputedStatus.availableOtherDay => (
        nextAvailableDay != null
            ? 'Disponible el $nextAvailableDay'
            : 'Próximamente',
        c.gold,
        c.pendingBg,
      ),
      ComputedStatus.closed => (
        opensAt != null ? 'Disponible: $opensAt' : 'Cerrado',
        c.gold,
        c.pendingBg,
      ),
      ComputedStatus.reserved => ('Apartado', c.gold, c.pendingBg),
      ComputedStatus.negotiating => (
        'En negociación',
        c.accent,
        c.surfaceMuted,
      ),
      ComputedStatus.sold => ('Vendido', c.mutedStrong, c.neutralBg),
      ComputedStatus.paused => ('Pausado', c.mutedStrong, c.neutralBg),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
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
        isOpen ? 'Abierto' : 'Cerrado',
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
