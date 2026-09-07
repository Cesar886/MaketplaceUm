import 'package:flutter/material.dart';

import '../providers/auth_provider.dart';

typedef PublicationLimits = ({int active, int daily, int days});

PublicationLimits publicationLimitsFor(
  AuthProvider auth, {
  required bool wanted,
}) {
  if (auth.accountType == AccountType.negocio) {
    if (auth.isVerified) {
      return wanted
          ? (active: 10, daily: 3, days: 60)
          : (active: 40, daily: 8, days: 60);
    }
    return wanted
        ? (active: 4, daily: 1, days: 20)
        : (active: 15, daily: 3, days: 20);
  }
  if (auth.accountType == AccountType.estudiante) {
    if (auth.isVerified) {
      return wanted
          ? (active: 10, daily: 3, days: 60)
          : (active: 30, daily: 6, days: 60);
    }
    return wanted
        ? (active: 5, daily: 2, days: 30)
        : (active: 10, daily: 3, days: 30);
  }
  return wanted
      ? (active: 3, daily: 1, days: 30)
      : (active: 8, daily: 2, days: 30);
}

class PublicationLimitNotice extends StatelessWidget {
  const PublicationLimitNotice({
    super.key,
    required this.auth,
    required this.wanted,
  });

  final AuthProvider auth;
  final bool wanted;

  ({int active, int daily, int days}) get _limits {
    return publicationLimitsFor(auth, wanted: wanted);
  }

  @override
  Widget build(BuildContext context) {
    final limits = _limits;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: .9),
            Theme.of(context).colorScheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .18),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tu cuenta permite ${limits.active} publicaciones activas, ${limits.daily} nuevas al día y duran ${limits.days} días.',
            ),
          ),
        ],
      ),
    );
  }
}
