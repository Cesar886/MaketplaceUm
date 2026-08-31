import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta y piezas visuales compartidas por las dos pantallas del enigma.
///
/// Estas pantallas NO usan `context.colors` ni respetan el tema del usuario,
/// y es a propósito: el resto de la app es un mercado claro y amable que
/// además cambia de color según el swatch elegido, así que cualquier cosa
/// pintada con esa paleta se lee como "otra sección más". Lo que se busca
/// aquí es lo contrario — que quien cruce la puerta sienta que salió de la
/// app. Un solo mundo fijo, oscuro y de latón, igual para todos.
class SecretoColors {
  /// Fondo: azul de medianoche, más profundo que el navy de marca.
  static const noche = Color(0xFF0B111C);
  static const nocheProfunda = Color(0xFF060A11);

  /// Latón viejo. El acento entero del mundo secreto: bordes, numerales,
  /// el cursor del campo. Cálido para que el azul no se sienta clínico.
  static const laton = Color(0xFFC9A96A);
  static const latonClaro = Color(0xFFE7D3A8);
  static const latonProfundo = Color(0xFF8A6F3C);

  static const tinta = Color(0xFFF2EDE3);
  static const tintaTenue = Color(0x99F2EDE3);
  static const tintaSusurro = Color(0x5AF2EDE3);
}

class SecretoType {
  static TextStyle titulo(double size, {Color color = SecretoColors.tinta}) =>
      GoogleFonts.baloo2(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.15,
      );

  static TextStyle verso(double size, {Color color = SecretoColors.tinta}) =>
      GoogleFonts.workSans(
        fontSize: size,
        fontWeight: FontWeight.w300,
        color: color,
        height: 1.75,
        // El interletrado abierto es lo que separa un verso de un párrafo de
        // ayuda: obliga a leer despacio, que es el ritmo del acertijo.
        letterSpacing: 0.4,
      );

  static TextStyle cuerpo(double size, {Color color = SecretoColors.tintaTenue}) =>
      GoogleFonts.workSans(
        fontSize: size,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.5,
      );

  /// Versalitas espaciadas para etiquetas cortas ("el enigma", "posición").
  static TextStyle sello(double size, {Color color = SecretoColors.laton}) =>
      GoogleFonts.workSans(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.2,
        letterSpacing: 3.2,
      );
}

/// Fondo vivo de las dos pantallas: un degradado de medianoche con motas de
/// polvo dorado a la deriva.
///
/// Las motas se dibujan en un [CustomPainter] con una sola animación de 0 a 1
/// que se repite, y cada una calcula su posición a partir de esa fracción:
/// así el número de partículas no cambia el costo por frame más que un poco
/// de aritmética, y no hay una lista de objetos mutando en cada tick.
class SecretoFondo extends StatefulWidget {
  const SecretoFondo({super.key, required this.child, this.motas = 34});

  final Widget child;

  /// Cuántas motas. Suficientes para que el aire se sienta habitado, no
  /// tantas como para que parezca nieve.
  final int motas;

  @override
  State<SecretoFondo> createState() => _SecretoFondoState();
}

class _SecretoFondoState extends State<SecretoFondo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _deriva = AnimationController(
    vsync: this,
    // Muy lento a propósito: el movimiento tiene que notarse solo si te
    // quedas mirando, no competir con el texto que hay que leer.
    duration: const Duration(seconds: 40),
  )..repeat();

  @override
  void dispose() {
    _deriva.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          // Centro desplazado hacia arriba: deja el halo detrás del título y
          // la parte baja de la pantalla en sombra, que es donde va el campo.
          center: Alignment(0, -0.55),
          radius: 1.25,
          colors: [Color(0x80162031), SecretoColors.nocheProfunda],
          stops: [0.0, 1.0],
        ),
        color: SecretoColors.noche,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _deriva,
              builder: (context, _) => CustomPaint(
                painter: _PolvoPainter(
                  fase: _deriva.value,
                  cantidad: widget.motas,
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _PolvoPainter extends CustomPainter {
  _PolvoPainter({required this.fase, required this.cantidad});

  final double fase;
  final int cantidad;

  @override
  void paint(Canvas canvas, Size size) {
    // Semilla fija: las motas caen siempre en las mismas trayectorias entre
    // repintados. Con una aleatoria, cada frame las teletransportaría.
    final rnd = math.Random(7);
    final pincel = Paint();

    for (var i = 0; i < cantidad; i++) {
      final x = rnd.nextDouble();
      final velocidad = 0.35 + rnd.nextDouble() * 0.9;
      final radio = 0.6 + rnd.nextDouble() * 1.7;
      final brillo = 0.10 + rnd.nextDouble() * 0.35;
      // Deriva horizontal mínima, con desfase propio: sin ella todas subirían
      // en líneas paralelas perfectas y se leería como una cortina.
      final vaiven = math.sin((fase * velocidad + x) * math.pi * 2) * 0.02;

      // La mota sube y reaparece por abajo: (posición inicial - avance) mod 1.
      final y = (rnd.nextDouble() - fase * velocidad) % 1.0;

      // Se apagan al nacer y al morir para que nadie vea el salto del ciclo.
      final borde = math.min(y, 1 - y);
      final opacidad = brillo * (borde < 0.12 ? borde / 0.12 : 1.0);

      pincel.color = SecretoColors.latonClaro.withValues(alpha: opacidad);
      canvas.drawCircle(
        Offset((x + vaiven) * size.width, y * size.height),
        radio,
        pincel,
      );
    }
  }

  @override
  bool shouldRepaint(_PolvoPainter anterior) =>
      anterior.fase != fase || anterior.cantidad != cantidad;
}

/// Filete de latón: una línea que se desvanece hacia los extremos. Separa
/// bloques sin meter una caja ni un Divider de app normal.
class SecretoFilete extends StatelessWidget {
  const SecretoFilete({super.key, this.ancho = 120});

  final double ancho;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ancho,
      height: 1,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0x00C9A96A),
            SecretoColors.laton,
            Color(0x00C9A96A),
          ],
        ),
      ),
    );
  }
}

/// Entrada escalonada: cada hijo aparece un poco después del anterior.
///
/// El escalonado es la mitad de la sensación de "esto es otra cosa": el
/// contenido no está ahí cuando llegas, se revela.
class SecretoAparicion extends StatefulWidget {
  const SecretoAparicion({
    super.key,
    required this.child,
    this.retraso = Duration.zero,
    this.duracion = const Duration(milliseconds: 900),
    this.desplazamiento = 14,
  });

  final Widget child;
  final Duration retraso;
  final Duration duracion;

  /// Cuánto sube el hijo mientras aparece, en píxeles lógicos.
  final double desplazamiento;

  @override
  State<SecretoAparicion> createState() => _SecretoAparicionState();
}

class _SecretoAparicionState extends State<SecretoAparicion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duracion,
  );
  late final CurvedAnimation _curva = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    if (widget.retraso == Duration.zero) {
      _c.forward();
    } else {
      // `mounted` porque el retraso puede sobrevivir a la pantalla si el
      // usuario se sale antes de que el último bloque aparezca.
      Future<void>.delayed(widget.retraso, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _curva.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curva,
      builder: (context, hijo) => Opacity(
        opacity: _curva.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _curva.value) * widget.desplazamiento),
          child: hijo,
        ),
      ),
      child: widget.child,
    );
  }
}
