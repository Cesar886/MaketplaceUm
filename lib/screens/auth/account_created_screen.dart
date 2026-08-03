import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_logo.dart';
import '../main_shell.dart';

class AccountCreatedScreen extends StatelessWidget {
  const AccountCreatedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              const AppLogo(size: 64, showText: false),
              const SizedBox(height: 20),
              Text(
                '¡Cuenta creada!',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Bienvenido${user?['name'] != null ? ', ${user!['name']}' : ''}',
                style: TextStyle(
                  color: context.colors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 28),

              // ─── Card de resumen ─────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.colors.border),
                ),
                child: Column(
                  children: [
                    _SummaryRow(
                      label: 'Tipo de cuenta',
                      value: auth.accountTypeLabel,
                    ),
                    const Divider(height: 20),
                    _SummaryRow(
                      label: 'Estado de verificación',
                      value: _verificationLabel(auth),
                    ),
                    const SizedBox(height: 12),
                    _buildVerificationBadge(context, auth),
                  ],
                ),
              ),
              const Spacer(flex: 3),

              // ─── Tips ─────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.teal.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lightbulb_rounded,
                      color: AppColors.teal,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Puedes completar o modificar tu verificación desde tu perfil en cualquier momento.',
                        style: TextStyle(
                          color: context.colors.accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute<void>(
                        builder: (_) => const MainShell(),
                      ),
                      (_) => false,
                    );
                  },
                  child: const Text('Ir al inicio'),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  String _verificationLabel(AuthProvider auth) {
    switch (auth.verificationStatus) {
      case VerificationStatus.noIniciada:
        return 'Sin verificar';
      case VerificationStatus.pendiente:
        return 'En revisión';
      case VerificationStatus.aprobada:
        return 'Verificada';
      case VerificationStatus.rechazada:
        return 'Rechazada';
    }
  }

  Widget _buildVerificationBadge(BuildContext context, AuthProvider auth) {
    switch (auth.verificationStatus) {
      case VerificationStatus.noIniciada:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: context.colors.muted.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: context.colors.muted.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.visibility_off_rounded,
                size: 16,
                color: context.colors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                'Sin verificar',
                style: TextStyle(
                  color: context.colors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      case VerificationStatus.pendiente:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.22)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hourglass_bottom_rounded,
                size: 16,
                color: AppColors.gold,
              ),
              SizedBox(width: 6),
              Text(
                'En revisión',
                style: TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      case VerificationStatus.aprobada:
        return _buildApprovedBadge(auth);
      case VerificationStatus.rechazada:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.18)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gpp_bad_rounded, size: 16, color: AppColors.danger),
              SizedBox(width: 6),
              Text(
                'Rechazada',
                style: TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildApprovedBadge(AuthProvider auth) {
    String label;
    IconData icon;
    Color color;

    switch (auth.accountType) {
      case AccountType.estudiante:
        label = 'Verificado UM';
        icon = Icons.school_rounded;
        color = AppColors.teal;
      case AccountType.particular:
        label = 'Identidad verificada';
        icon = Icons.badge_rounded;
        color = AppColors.primary;
      case AccountType.negocio:
        label = 'Negocio confirmado';
        icon = Icons.store_rounded;
        color = AppColors.gold;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.colors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: context.colors.ink,
          ),
        ),
      ],
    );
  }
}
