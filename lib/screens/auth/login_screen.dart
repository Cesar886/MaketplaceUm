import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../models.dart';
import '../../providers/accent_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/support_conversation.dart';
import '../../config/google_auth_config.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/google_sign_in_button.dart';
import '../../main.dart' show mainShellKey;
import '../main_shell.dart';
import '../chat_screen.dart';
import 'google_auth_flow.dart';
import 'register_type_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  Future<void> _mostrarRestriccion(RestriccionCuentaException restriccion) {
    final hasta = restriccion.suspendidaHasta;
    final fecha = hasta == null
        ? null
        : '${hasta.day.toString().padLeft(2, '0')}/'
              '${hasta.month.toString().padLeft(2, '0')}/${hasta.year} a las '
              '${hasta.hour.toString().padLeft(2, '0')}:'
              '${hasta.minute.toString().padLeft(2, '0')}';
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          restriccion.esBaneo ? Icons.block_rounded : Icons.schedule_rounded,
          color: restriccion.esBaneo
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
          size: 34,
        ),
        title: Text(
          restriccion.esBaneo ? 'Cuenta inhabilitada' : 'Cuenta suspendida',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(restriccion.mensaje),
            if (restriccion.motivo?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 18),
              Text('Motivo', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(restriccion.motivo!.trim()),
            ],
            if (fecha != null) ...[
              const SizedBox(height: 18),
              Text(
                'Acceso disponible de nuevo',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(fecha),
            ],
            const SizedBox(height: 18),
            const Text(
              'Si consideras que fue un error, comunícate con soporte de Marketplace UM.',
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.support_agent_rounded),
            label: const Text('Hablar con soporte'),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                final support = await prepareReportsConversation();
                if (!mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatScreen(
                      conversationId: support.conversationId,
                      sellerId: support.contact.id,
                      otherUser: ChatUser.deSeller(support.contact),
                      initialDraft:
                          'Hola, quiero solicitar una revisión de la medida aplicada a mi cuenta. '
                          'El motivo que recibí fue: ${restriccion.motivo?.trim().isNotEmpty == true ? restriccion.motivo!.trim() : 'no especificado'}.',
                    ),
                  ),
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'No pudimos abrir el chat de soporte. Intenta nuevamente.',
                    ),
                  ),
                );
              }
            },
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  const AppLogo(size: 48, showText: false),
                  const SizedBox(height: 16),
                  Text(
                    'auth.login_title'.tr(),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'auth.login_subtitle'.tr(),
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'auth.email_label'.tr(),
                      prefixIcon: const Icon(Icons.email_rounded),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty)
                        return 'validation.email_required'.tr();
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'auth.password_label'.tr(),
                      prefixIcon: const Icon(Icons.lock_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    obscureText: _obscure,
                    validator: (v) {
                      if (v == null || v.isEmpty)
                        return 'validation.password_required'.tr();
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: auth.isLoading
                          ? null
                          : () async {
                              if (!_formKey.currentState!.validate()) return;
                              bool ok;
                              try {
                                ok = await auth.login(
                                  _emailController.text.trim(),
                                  _passwordController.text,
                                );
                              } on RestriccionCuentaException catch (
                                restriccion
                              ) {
                                if (context.mounted) {
                                  await _mostrarRestriccion(restriccion);
                                }
                                return;
                              }
                              if (!context.mounted) return;
                              if (ok) {
                                // Iniciar sesión puede traer un perfil con
                                // otro color que el que dejó la sesión
                                // anterior en este teléfono, así que el
                                // servidor manda desde ya.
                                final sellerId = auth.backendSellerId;
                                if (sellerId != null) {
                                  context
                                      .read<AccentProvider>()
                                      .sincronizarDesdeBackend(sellerId);
                                }
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        MainShell(key: mainShellKey),
                                  ),
                                  (_) => false,
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('auth.login_failed'.tr()),
                                  ),
                                );
                              }
                            },
                      child: auth.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('auth.login_button'.tr()),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // ─── Continuar con Google ───────────────────
                  //
                  // Va DEBAJO del formulario de correo, que sigue siendo el
                  // camino principal. Mientras no haya Client ID pegado el
                  // botón se muestra deshabilitado y con una nota, en vez de
                  // esconderse: así se ve que la función existe y que solo
                  // falta configurarla.
                  const SeparadorODivider(),
                  const SizedBox(height: 16),
                  GoogleSignInButton(
                    cargando: auth.isLoading,
                    onPressed: GoogleAuthConfig.estaConfigurado
                        ? () => continuarConGoogle(context)
                        : null,
                  ),
                  if (!GoogleAuthConfig.estaConfigurado) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        'auth.google_unavailable'.tr(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'auth.no_account'.tr(),
                        style: TextStyle(
                          color: context.colors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => const RegisterTypeScreen(),
                          ),
                        ),
                        child: Text(
                          'auth.create_account'.tr(),
                          style: TextStyle(
                            color: context.colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
