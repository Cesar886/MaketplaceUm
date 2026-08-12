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
/// El alto se calcula solo: el panel cubre el alto natural de [child] a
/// color SÓLIDO (nunca lo atraviesa un fade, sin importar cuánto mida el
/// contenido: un avatar solo, o un avatar junto con nombre, calificación y
/// badges), y solo DESPUÉS agrega una franja de [extraFade] px que hace la
/// transición hacia `fadeTo`. Por eso es un `Column` con dos bloques y no un
/// gradiente estirado sobre toda la altura: con un solo gradiente de 0 a 1,
/// el punto donde "empieza a desvanecer" se mueve cada vez que el contenido
/// cambia de alto, y el fade podía terminar comiéndose texto en vez de
/// quedar debajo de él.
class ProfileBanner extends StatelessWidget {
  const ProfileBanner({
    super.key,
    required this.color,
    required this.fadeTo,
    required this.child,
    this.extraFade = 64,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.expand = true,
  });

  final Color color;
  final Color fadeTo;
  final Widget child;

  /// Alto en px de la franja de desvanecido que sigue al contenido.
  final double extraFade;
  final BorderRadius borderRadius;

  /// Si es true (default), el panel se estira al ancho que le da su padre
  /// — para eso hace falta envolverlo en algo que ya fije ese ancho, como
  /// `SizedBox(width: double.infinity)` dentro de un `ListView` (caso del
  /// banner de perfil de vendedor). Si es false, el panel se ENCOGE al
  /// ancho natural de [child] — para cuando va suelto dentro de un `Row`
  /// junto a otro contenido (caso de la miniatura de foto en el perfil
  /// propio): con stretch ahí, el panel reclama todo el ancho disponible
  /// de la fila en vez de solo el de la foto, y le quita espacio al resto.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final tint = color.withValues(alpha: 0.42);
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(color: tint, child: child),
        SizedBox(
          height: extraFade,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tint, fadeTo],
              ),
            ),
          ),
        ),
      ],
    );
    return ClipRRect(
      borderRadius: borderRadius,
      child: expand ? column : IntrinsicWidth(child: column),
    );
  }
}
