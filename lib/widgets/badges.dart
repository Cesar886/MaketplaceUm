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
      background: AppColors.champagne,
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

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _Badge(
      icon: Icons.verified_rounded,
      label: 'Verificado',
      foreground: AppColors.teal,
      background: AppColors.teal.withValues(alpha: 0.08),
      compact: compact,
    );
  }
}

class AvailabilityBadge extends StatelessWidget {
  const AvailabilityBadge({super.key, required this.availability});

  final ProductAvailability availability;

  @override
  Widget build(BuildContext context) {
    final (Color foreground, Color background) = switch (availability) {
      ProductAvailability.available => (
        AppColors.success,
        AppColors.success.withValues(alpha: 0.08),
      ),
      ProductAvailability.reserved => (
        AppColors.orange,
        AppColors.orange.withValues(alpha: 0.08),
      ),
      ProductAvailability.sold => (
        AppColors.danger,
        AppColors.danger.withValues(alpha: 0.08),
      ),
      ProductAvailability.negotiating => (
        AppColors.primary,
        AppColors.primary.withValues(alpha: 0.08),
      ),
      ProductAvailability.paused => (
        AppColors.muted,
        AppColors.muted.withValues(alpha: 0.08),
      ),
      ProductAvailability.unavailable => (
        AppColors.muted,
        AppColors.muted.withValues(alpha: 0.08),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        availability.label,
        style: TextStyle(
          color: foreground,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Badge contextual que muestra el nivel de verificación según el tipo de cuenta.
class VerificationStatusBadge extends StatelessWidget {
  const VerificationStatusBadge({
    super.key,
    required this.accountType,
    required this.verificationStatus,
    this.compact = false,
  });

  final AccountType accountType;
  final VerificationStatus verificationStatus;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // No mostrar nada si no hay verificación iniciada
    if (verificationStatus == VerificationStatus.noIniciada) {
      return const SizedBox.shrink();
    }

    // Si está pendiente o rechazada, mostrar status genérico
    if (verificationStatus == VerificationStatus.pendiente) {
      return _Badge(
        icon: Icons.hourglass_bottom_rounded,
        label: 'En revisión',
        foreground: AppColors.gold,
        background: AppColors.gold.withValues(alpha: 0.10),
        compact: compact,
      );
    }

    if (verificationStatus == VerificationStatus.rechazada) {
      return _Badge(
        icon: Icons.gpp_bad_rounded,
        label: 'Rechazada',
        foreground: AppColors.danger,
        background: AppColors.danger.withValues(alpha: 0.08),
        compact: compact,
      );
    }

    // Aprobada → badge según tipo de cuenta
    switch (accountType) {
      case AccountType.estudiante:
        return _Badge(
          icon: Icons.school_rounded,
          label: 'Verificado UM',
          foreground: AppColors.teal,
          background: AppColors.teal.withValues(alpha: 0.10),
          compact: compact,
        );
      case AccountType.particular:
        return _Badge(
          icon: Icons.badge_rounded,
          label: 'Identidad verificada',
          foreground: AppColors.primary,
          background: AppColors.primary.withValues(alpha: 0.10),
          compact: compact,
        );
      case AccountType.negocio:
        return _Badge(
          icon: Icons.store_rounded,
          label: 'Negocio confirmado',
          foreground: AppColors.gold,
          background: AppColors.champagne,
          compact: compact,
        );
    }
  }
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
