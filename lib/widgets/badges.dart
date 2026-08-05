import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';

class FeaturedBadge extends StatelessWidget {
  const FeaturedBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _Badge(
      icon: Icons.star_rounded,
      label: 'Destacado',
      foreground: AppColors.gold,
      background: context.colors.premiumBg,
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
    return _Badge(
      icon: Icons.local_offer_rounded,
      label: label ?? 'Oferta',
      foreground: AppColors.orange,
      background: AppColors.orange.withValues(alpha: 0.08),
      compact: compact,
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final ListingStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ListingStatus.active => AppColors.success,
      ListingStatus.featured => AppColors.gold,
      ListingStatus.expired => AppColors.danger,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
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
/// Los tres tipos comparten el MISMO ícono de check a propósito: el color
/// comunica de qué tipo de cuenta se trata sin sugerir que una es "más
/// confiable" que otra. Verificarse significa lo mismo en los tres casos
/// (el backend comprobó automáticamente un dato real de contacto), solo
/// cambia qué dato se comprobó.
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
  const InsigniaVerificada.desdeTipo(String tipoCuenta, {
    super.key,
    this.compact = false,
    this.size = 16,
  })  : _tipoCrudo = tipoCuenta,
        tipo = AccountType.particular;

  final AccountType tipo;
  final bool compact;

  /// Tamaño del ícono en la variante compacta. Existe para que los call
  /// sites conserven el tamaño que ya tenían.
  final double size;
  final String? _tipoCrudo;

  /// Un tipo desconocido cae a 'particular', el estilo más neutro: nunca se
  /// le atribuye a una cuenta un nivel de verificación que no tiene.
  AccountType get _tipoEfectivo =>
      _tipoCrudo == null ? tipo : (_tipoCrudo.toAccountType ?? AccountType.particular);

  @override
  Widget build(BuildContext context) {
    final (color, etiqueta) = switch (_tipoEfectivo) {
      AccountType.estudiante => (AppColors.primary, 'Estudiante verificado'),
      AccountType.negocio => (AppColors.teal, 'Negocio verificado'),
      AccountType.particular => (AppColors.muted, 'Verificado'),
    };

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
    final (String label, Color foreground) = switch (status) {
      ComputedStatus.available => ('Disponible', AppColors.success),
      ComputedStatus.soldOut => ('Agotado', context.colors.muted),
      ComputedStatus.availableOtherDay => (
        nextAvailableDay != null
            ? 'Disponible el $nextAvailableDay'
            : 'Disponible otro día',
        AppColors.orange,
      ),
      ComputedStatus.closed => (
        opensAt != null ? 'Abre a las $opensAt' : 'Cerrado por ahora',
        context.colors.muted,
      ),
      ComputedStatus.reserved => ('Apartado', AppColors.orange),
      ComputedStatus.negotiating => ('En negociación', AppColors.primary),
      ComputedStatus.sold => ('Vendido', context.colors.muted),
      ComputedStatus.paused => ('Pausado', context.colors.muted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.08),
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
        ? (AppColors.success, AppColors.success.withValues(alpha: 0.08))
        : (context.colors.muted, context.colors.muted.withValues(alpha: 0.08));

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
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
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
