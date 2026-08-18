import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../providers/accent_provider.dart';
import '../providers/auth_provider.dart';
import '../services/anonymous_id.dart';
import '../services/deep_link_service.dart';
import '../services/onboarding_service.dart';
import '../widgets/app_logo.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // Pequeña pausa para mostrar el splash
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // Asegura que exista un device_id local — es el único requisito de
    // arranque. No se pide login/registro para entrar: el feed, el detalle
    // de productos/"se busca" y el contacto por WhatsApp funcionan sin
    // cuenta. El registro solo se pide más adelante, al intentar publicar.
    await AnonymousId.get();

    if (!mounted) return;

    // Restaurar sesión guardada si existe (no bloquea el arranque si no hay).
    final auth = context.read<AuthProvider>();
    await auth.tryAutoLogin();

    if (!mounted) return;

    // El color de la app vive en el perfil del backend, así que se pide aquí
    // y no al abrir la pantalla de perfil: tras reinstalar, el caché local
    // está vacío y esta es la primera (y única) oportunidad de pintar la app
    // con el color elegido antes de que se vea nada. No se espera con await
    // para no retrasar el arranque — cuando responda, el tema se repinta.
    final sellerId = auth.backendSellerId;
    if (sellerId != null) {
      context.read<AccentProvider>().sincronizarDesdeBackend(sellerId);
    }

    final vioOnboarding = await OnboardingService.hasSeenOnboarding();

    if (!mounted) return;

    // Se captura ANTES de salir del árbol: el pushReplacement desmonta el
    // splash, así que `context` ya no sirve dentro del callback que le
    // pasamos al onboarding.
    final navigator = Navigator.of(context);

    void entrarAlaApp() {
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const MainShell()),
      );

      // Recién ahora hay una pantalla sobre la cual apilar. Si la app se
      // abrió desde un link compartido, el deep link quedó esperando aquí:
      // apilarlo antes lo habría borrado el pushReplacement de arriba.
      //
      // Va aquí dentro y no antes del onboarding a propósito: en una
      // instalación nueva abierta desde un link, el producto compartido debe
      // aparecer AL TERMINAR el onboarding, no debajo de él.
      DeepLinkService.instance.marcarAppLista();
    }

    if (!vioOnboarding) {
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OnboardingScreen(onFinish: entrarAlaApp),
        ),
      );
      return;
    }

    entrarAlaApp();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Spacer(),
                const AppLogo(size: 78, showText: false),
                const SizedBox(height: 28),
                Text(
                  'app.name'.tr(),
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(fontSize: 34),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'app.tagline'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const LinearProgressIndicator(
                  minHeight: 5,
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
