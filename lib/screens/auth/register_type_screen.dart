import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../config/google_auth_config.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/google_sign_in_button.dart';
import 'google_auth_flow.dart';
import 'register_form_screen.dart';

class RegisterTypeScreen extends StatelessWidget {
  const RegisterTypeScreen({super.key, this.google});

  /// Cuando se llega aquí desde "Continuar con Google" con una cuenta que
  /// todavía no existe: trae el idToken y el perfil para prellenar el
  /// formulario. En el registro normal es null y nada cambia.
  final GoogleRegistroPendiente? google;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('auth.create_account'.tr())),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'auth.register_type_title'.tr(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'auth.register_type_subtitle'.tr(),
                style: TextStyle(
                  color: context.colors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (google != null) ...[
                const SizedBox(height: 16),
                _AvisoGoogle(email: google!.email),
              ],
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    _TypeCard(
                      emoji: '🎓',
                      // Alumnos y personal comparten esta tarjeta y el mismo
                      // tipo_cuenta interno ('estudiante'): lo que los
                      // distingue es el dominio de correo que eligen al
                      // verificarse (ver constants/dominios_um.dart).
                      title: 'auth.type_student_title'.tr(),
                      subtitle: 'auth.type_student_subtitle'.tr(),
                      features: ['auth.type_student_feature_1'.tr()],
                      color: context.colors.accent,
                      onTap: () => _goToForm(context, 'estudiante'),
                    ),
                    const SizedBox(height: 12),
                    _TypeCard(
                      emoji: '🏪',
                      title: 'auth.type_vendor_title'.tr(),
                      subtitle: 'auth.type_vendor_subtitle'.tr(),
                      features: [
                        'auth.type_vendor_feature_1'.tr(),
                        'auth.type_vendor_feature_2'.tr(),
                      ],
                      color: context.colors.accent,
                      onTap: () => _goToForm(context, 'negocio'),
                    ),
                    const SizedBox(height: 12),
                    _TypeCard(
                      emoji: '🧑',
                      title: 'auth.type_external_title'.tr(),
                      subtitle: 'auth.type_external_subtitle'.tr(),
                      features: [
                        'auth.type_external_feature_1'.tr(),
                        'auth.type_external_feature_2'.tr(),
                      ],
                      color: context.colors.accent,
                      onTap: () => _goToForm(context, 'particular'),
                    ),
                  ],
                ),
              ),
              // ─── Registrarse con Google ─────────────────────
              //
              // Solo cuando NO se llegó aquí desde Google: si ya se
              // autenticó, volver a ofrecerlo sería un bucle. El registro
              // por correo de arriba no cambia.
              if (google == null && GoogleAuthConfig.estaConfigurado) ...[
                const SizedBox(height: 16),
                const SeparadorODivider(),
                const SizedBox(height: 14),
                GoogleSignInButton(
                  cargando: context.watch<AuthProvider>().isLoading,
                  etiqueta: 'auth.google_signup'.tr(),
                  onPressed: () => continuarConGoogle(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _goToForm(BuildContext context, String type) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RegisterFormScreen(userType: type, google: google),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.features,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final List<String> features;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.colors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final f in features) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 6),
                          child: Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: context.colors.accent,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            f,
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}

/// Recordatorio de con qué cuenta de Google se está registrando, para que
/// nadie complete el formulario creyendo que va a otro correo.
class _AvisoGoogle extends StatelessWidget {
  const _AvisoGoogle({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          const GoogleLogo(size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'auth.google_registering_as'.tr(namedArgs: {'email': email}),
              style: TextStyle(
                color: context.colors.muted,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
