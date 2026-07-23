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
      border: AppColors.premiumBorder,
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
      border: AppColors.orange.withValues(alpha: 0.18),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
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
      border: AppColors.teal.withValues(alpha: 0.18),
      compact: compact,
    );
  }
}

class AvailabilityBadge extends StatelessWidget {
  const AvailabilityBadge({super.key, required this.availability});

  final ProductAvailability availability;

  @override
  Widget build(BuildContext context) {
    final (Color foreground, Color background, Color border) =
        switch (availability) {
      ProductAvailability.available => (
        AppColors.success,
        AppColors.success.withValues(alpha: 0.08),
        AppColors.success.withValues(alpha: 0.18),
      ),
      ProductAvailability.reserved => (
        AppColors.orange,
        AppColors.orange.withValues(alpha: 0.08),
        AppColors.orange.withValues(alpha: 0.18),
      ),
      ProductAvailability.sold => (
        AppColors.danger,
        AppColors.danger.withValues(alpha: 0.08),
        AppColors.danger.withValues(alpha: 0.18),
      ),
      ProductAvailability.negotiating => (
        AppColors.primary,
        AppColors.primary.withValues(alpha: 0.08),
        AppColors.primary.withValues(alpha: 0.18),
      ),
      ProductAvailability.paused => (
        AppColors.muted,
        AppColors.muted.withValues(alpha: 0.08),
        AppColors.muted.withValues(alpha: 0.18),
      ),
      ProductAvailability.unavailable => (
        AppColors.muted,
        AppColors.muted.withValues(alpha: 0.08),
        AppColors.muted.withValues(alpha: 0.18),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        availability.label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
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
        border: AppColors.gold.withValues(alpha: 0.22),
        compact: compact,
      );
    }

    if (verificationStatus == VerificationStatus.rechazada) {
      return _Badge(
        icon: Icons.gpp_bad_rounded,
        label: 'Rechazada',
        foreground: AppColors.danger,
        background: AppColors.danger.withValues(alpha: 0.08),
        border: AppColors.danger.withValues(alpha: 0.18),
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
          border: AppColors.teal.withValues(alpha: 0.22),
          compact: compact,
        );
      case AccountType.particular:
        return _Badge(
          icon: Icons.badge_rounded,
          label: 'Identidad verificada',
          foreground: AppColors.primary,
          background: AppColors.primary.withValues(alpha: 0.10),
          border: AppColors.primary.withValues(alpha: 0.22),
          compact: compact,
        );
      case AccountType.negocio:
        return _Badge(
          icon: Icons.store_rounded,
          label: 'Negocio confirmado',
          foreground: AppColors.gold,
          background: AppColors.champagne,
          border: AppColors.premiumBorder,
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
    required this.border,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final Color border;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 13 : 15, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
