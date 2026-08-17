import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';

/// Da un rebote de escala cuando [value] **sube**, y solo cuando sube.
///
/// Es la reacción que le faltaba al corazón de favoritos: el contador del
/// header ya se refresca al volver del detalle (`home_screen.dart`), o sea
/// que el momento "se agregó algo" ya existía en la app — lo único que no
/// había era acuse de recibo. Sin él, marcar un favorito y volver al home
/// no produce ninguna señal de que algo pasó.
///
/// Baja y se queda igual NO animan, a propósito. Un rebote que se dispara en
/// cualquier cambio deja de significar "se agregó" y pasa a ser ruido; que
/// solo suba es lo que le da sentido al gesto. Por eso quitar un favorito es
/// silencioso aunque el contador cambie.
///
/// Sirve igual para un contador (`badgeCount`) que para un booleano, pasando
/// `fav ? 1 : 0`: false→true es un aumento y true→false no lo es, que es
/// exactamente la semántica que se quiere en los dos casos.
class BounceOnIncrease extends StatefulWidget {
  const BounceOnIncrease({
    super.key,
    required this.value,
    required this.child,
    this.maxScale = 1.26,
    this.haptic = false,
  });

  /// Valor observado. El rebote se dispara cuando el nuevo es mayor.
  final int value;

  final Widget child;

  /// Pico de la escala. Por encima de ~1.3 el ícono empuja a sus vecinos en
  /// una fila apretada como la del header, y el rebote pasa de elegante a
  /// aparatoso.
  final double maxScale;

  /// Acompañar el rebote con un toque háptico. Apagado por defecto: en el
  /// header el aumento llega solo (al volver del detalle), y vibrar por algo
  /// que el usuario no acaba de tocar se siente como un error de la app. Se
  /// enciende donde el aumento SÍ es respuesta directa a un tap.
  final bool haptic;

  @override
  State<BounceOnIncrease> createState() => _BounceOnIncreaseState();
}

class _BounceOnIncreaseState extends State<BounceOnIncrease>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppAnimations.fast,
  );

  late final Animation<double> _scale = TweenSequence<double>([
    // Sube rápido y baja más lento: el peso de la animación queda en el
    // regreso, que es lo que la hace leerse como rebote y no como parpadeo.
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: widget.maxScale)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(begin: widget.maxScale, end: 1.0)
          .chain(CurveTween(curve: AppAnimations.entrance)),
      weight: 60,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(covariant BounceOnIncrease oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value > oldWidget.value) {
      _controller.forward(from: 0);
      if (widget.haptic) HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}
