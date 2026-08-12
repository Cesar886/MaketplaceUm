import 'package:flutter/material.dart';

/// Panel de color detrás de la foto de perfil.
///
/// El color es SIEMPRE `context.colors.primary` — el mismo acento que ya se
/// elige en Apariencia y pinta AppBar/botones — así que no hay un segundo
/// selector que mantener ni un campo nuevo en el backend: personalizar el
/// perfil ya personaliza el banner.
///
/// Dos decisiones que evitan que esto se vea como un bloque sólido pegado
/// detrás del texto:
///
///  - El color entra a ~42% de alpha, nunca opaco. Con navy o wine (los dos
///    swatches oscuros) un panel sólido detrás del nombre podría bajar el
///    contraste del texto (tinta oscura sobre navy oscuro); a 42% incluso el
///    swatch más saturado queda en un lavado medio-claro con de sobra AA.
///  - Se desvanece con un degradado hacia `fadeTo` (la superficie de
///    alrededor: la tarjeta o el fondo de página, según dónde se use). Es un
///    degradado y no un blur real (`BackdropFilter`) a propósito: no hay
///    nada detrás que desenfocar, así que un blur real solo gastaría GPU
///    para producir el mismo resultado visual que un gradiente.
///
/// El alto se calcula solo: el panel cubre el alto natural de [child] más
/// [extraFade] px de desvanecido por debajo — así "llega un poco más abajo"
/// de la foto sin importar cuánto mida el contenido que se le pase (un
/// avatar solo, o un avatar junto con el nombre).
class ProfileBanner extends StatelessWidget {
  const ProfileBanner({
    super.key,
    required this.color,
    required this.fadeTo,
    required this.child,
    this.extraFade = 30,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
  });

  final Color color;
  final Color fadeTo;
  final Widget child;

  /// Cuánto se extiende el desvanecido por debajo del contenido.
  final double extraFade;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withValues(alpha: 0.42), fadeTo],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: extraFade),
            child: child,
          ),
        ],
      ),
    );
  }
}
