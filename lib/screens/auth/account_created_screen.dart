import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/badges.dart';
import '../../main.dart' show mainShellKey;
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
                'auth.account_created_title'.tr(),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                // Dos claves distintas en vez de concatenar: en inglés el
                // saludo con nombre no es 'Welcome' + ', Ana', y armarlo
                // por pedazos deja la coma fuera de la traducción.
                user?['name'] != null
                    ? 'auth.welcome_named'.tr(
                        namedArgs: {'name': '${user!['name']}'},
                      )
                    : 'auth.welcome'.tr(),
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
                      label: 'auth.account_type'.tr(),
                      value: auth.accountTypeLabel,
                    ),
                    const Divider(height: 20),
                    _SummaryRow(
                      label: 'auth.verification_status'.tr(),
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
                  color: context.colors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: context.colors.accent.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_rounded,
                      color: context.colors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'auth.verification_later_hint'.tr(),
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
                        builder: (_) => MainShell(key: mainShellKey),
                      ),
                      (_) => false,
                    );
                  },
                  child: Text('auth.go_home'.tr()),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// La verificación ya no tiene estado "en revisión": el backend la
  /// resuelve al instante, así que la cuenta solo puede estar verificada o
  /// no. Si no lo está, es porque el usuario pospuso el trámite o porque sus
  /// datos fueron rechazados; en ambos casos puede retomarlo desde el perfil.
  String _verificationLabel(AuthProvider auth) =>
      auth.isVerified ? 'auth.verified'.tr() : 'auth.unverified'.tr();

  Widget _buildVerificationBadge(BuildContext context, AuthProvider auth) {
    if (auth.isVerified) {
      return InsigniaVerificada(tipo: auth.accountType);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.muted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.colors.muted.withValues(alpha: 0.18)),
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
            'auth.unverified'.tr(),
            style: TextStyle(
              color: context.colors.muted,
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
