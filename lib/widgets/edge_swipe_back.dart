import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Franja de swipe-back nativo (iOS) ligeramente más ancha que el default de
/// Flutter (~20px, ver `_kBackGestureWidth` en `flutter/cupertino/route.dart`
/// — privado, no configurable). En vez de forkear ese código o depender de
/// un paquete de terceros sin mantenimiento (`cupertino_back_gesture`, sin
/// updates hace 5 años), esta clase delega el 100% de la animación y del
/// gesto interactivo de los primeros ~20px al [CupertinoPageTransitionsBuilder]
/// estándar, y solo agrega una franja extra angosta y ADYACENTE (20px-34px)
/// donde un swipe hacia la derecha dispara un pop no interactivo — mismo
/// resultado (mismo return, misma animación de salida), sin el efecto
/// "sigue al dedo en vivo" en esos últimos px extra, que sí tiene la franja
/// nativa. Al no solaparse con la franja nativa no hay ambigüedad de gesture
/// arena ni doble-pop.
class SensitiveCupertinoPageTransitionsBuilder extends PageTransitionsBuilder {
  const SensitiveCupertinoPageTransitionsBuilder();

  static const double _nativeEdgeWidth = 20.0;
  static const double _extraEdgeWidth = 14.0;

  @override
  Duration get transitionDuration =>
      const CupertinoPageTransitionsBuilder().transitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      const CupertinoPageTransitionsBuilder().delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final native = const CupertinoPageTransitionsBuilder().buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
    return _ExtraEdgeSwipeBack(
      route: route,
      innerWidth: _nativeEdgeWidth,
      outerWidth: _nativeEdgeWidth + _extraEdgeWidth,
      child: native,
    );
  }
}

/// Detecta un swipe hacia la derecha que empieza en la franja
/// [innerWidth]-[outerWidth] (justo después de donde termina la franja nativa
/// de Flutter) y hace pop de [route] si hay suficiente distancia/velocidad.
class _ExtraEdgeSwipeBack extends StatefulWidget {
  const _ExtraEdgeSwipeBack({
    required this.route,
    required this.innerWidth,
    required this.outerWidth,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final double innerWidth;
  final double outerWidth;
  final Widget child;

  @override
  State<_ExtraEdgeSwipeBack> createState() => _ExtraEdgeSwipeBackState();
}

class _ExtraEdgeSwipeBackState extends State<_ExtraEdgeSwipeBack> {
  late final HorizontalDragGestureRecognizer _recognizer;
  double _totalDx = 0;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = (_) {
        _totalDx = 0;
      }
      ..onUpdate = _onUpdate
      ..onEnd = _onEnd
      ..onCancel = () {
        _totalDx = 0;
      };
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  bool get _enabled =>
      widget.route.isCurrent && (widget.route.navigator?.canPop() ?? false);

  void _onUpdate(DragUpdateDetails details) {
    _totalDx += _rtl ? -details.delta.dx : details.delta.dx;
  }

  void _onEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx * (_rtl ? -1 : 1);
    // Umbral simple (distancia O velocidad): no hay drag en vivo en esta
    // franja extra, así que basta un swipe claro para completar el pop.
    if (_totalDx > 40 || velocity > 300) {
      widget.route.navigator?.maybePop();
    }
    _totalDx = 0;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_enabled) _recognizer.addPointer(event);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        PositionedDirectional(
          start: widget.innerWidth,
          width: widget.outerWidth - widget.innerWidth,
          top: 0,
          bottom: 0,
          child: Listener(
            onPointerDown: _handlePointerDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}
