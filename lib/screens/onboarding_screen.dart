import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_illustrations.dart';

/// Una lámina del onboarding.
class OnboardingSlide {
  const OnboardingSlide({
    required this.arte,
    required this.titulo,
    required this.cuerpo,
  });

  final OnboardingArte arte;
  final String titulo;
  final String cuerpo;
}

/// Las tres láminas, en orden: qué es → cómo compras → cómo vendes.
///
/// Tres y no cinco: el onboarding compite con las ganas de entrar a la app,
/// y lo único que tiene que dejar claro es que aquí se compra y se vende
/// entre estudiantes sin necesidad de cuenta para mirar.
const slidesOnboarding = <OnboardingSlide>[
  OnboardingSlide(
    arte: OnboardingArte.puesto,
    titulo: 'El mercadito de tu universidad',
    cuerpo:
        'Compra y vende entre estudiantes verificados de la UM. '
        'Sin intermediarios y sin salir del campus.',
  ),
  OnboardingSlide(
    arte: OnboardingArte.descubre,
    titulo: 'Encuentra y pregunta',
    cuerpo:
        'Explora el feed, guarda lo que te lata en favoritos y escríbele '
        'directo a quien vende. No necesitas cuenta para mirar.',
  ),
  OnboardingSlide(
    arte: OnboardingArte.vende,
    titulo: 'Publica en un minuto',
    cuerpo:
        'Una foto, un precio y listo. Tu publicación queda visible para '
        'toda la comunidad al instante.',
  ),
];

/// Onboarding de primer arranque.
///
/// Va antes del login porque la app se navega entera sin cuenta (ver
/// `splash_screen.dart`): pedir registro aquí contradiría justo lo que la
/// segunda lámina promete.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinish});

  /// Qué hacer al terminar o saltar. La pantalla no navega por su cuenta:
  /// quien la muestra decide a dónde va después, que es lo que la hace
  /// probable sin montar el árbol de navegación completo.
  final VoidCallback onFinish;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _pagina = 0;

  bool get _esUltima => _pagina == slidesOnboarding.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _terminar() async {
    // Se marca ANTES de salir: si el usuario mata la app en el instante
    // exacto de la transición, el onboarding no debe reaparecer.
    await OnboardingService.markSeen();
    if (!mounted) return;
    widget.onFinish();
  }

  void _avanzar() {
    if (_esUltima) {
      _terminar();
      return;
    }
    _pageController.nextPage(
      duration: AppAnimations.medium,
      curve: AppAnimations.spring,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            // "Saltar" arriba a la derecha, y solo mientras haya algo que
            // saltar: en la última compite con "Empezar" justo donde el
            // usuario tiene que decidir.
            SizedBox(
              height: 52,
              child: Align(
                alignment: Alignment.centerRight,
                child: AnimatedOpacity(
                  opacity: _esUltima ? 0 : 1,
                  duration: AppAnimations.fast,
                  child: _esUltima
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: TextButton(
                            onPressed: _terminar,
                            child: Text(
                              'Saltar',
                              style: AppTypography.label(
                                15,
                                color: colors.muted,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _pagina = i),
                itemCount: slidesOnboarding.length,
                itemBuilder: (context, i) => _Lamina(slide: slidesOnboarding[i]),
              ),
            ),
            _Puntos(total: slidesOnboarding.length, activo: _pagina),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('onboarding-primario'),
                  onPressed: _avanzar,
                  child: Text(_esUltima ? 'Empezar' : 'Siguiente'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Lamina extends StatelessWidget {
  const _Lamina({required this.slide});

  final OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OnboardingIllustration(arte: slide.arte, size: 220),
          const SizedBox(height: 40),
          Text(
            slide.titulo,
            textAlign: TextAlign.center,
            style: AppTypography.heading(27, color: colors.ink),
          ),
          const SizedBox(height: 14),
          Text(
            slide.cuerpo,
            textAlign: TextAlign.center,
            style: AppTypography.body(16, color: colors.muted),
          ),
        ],
      ),
    );
  }
}

/// Indicador de posición. El punto activo se alarga en vez de solo cambiar
/// de color: la forma se distingue de un vistazo y sin depender del contraste
/// del acento elegido, que varía entre los ocho swatches.
class _Puntos extends StatelessWidget {
  const _Puntos({required this.total, required this.activo});

  final int total;
  final int activo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final esActivo = i == activo;
        return AnimatedContainer(
          duration: AppAnimations.fast,
          curve: AppAnimations.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: esActivo ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: esActivo ? colors.accent : colors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
