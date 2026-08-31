import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta oscura del mundo secreto: azul de medianoche y latón viejo.
///
/// A diferencia de `context.colors` (que cambia con el swatch elegido), esta
/// paleta es fija — el latón y el azul son el único vestuario del enigma, en
/// los dos temas. Lo que sí sigue al usuario es CUÁL de las dos paletas se
/// usa: [SecretoPalette.of] elige esta o [_SecretoColoresClaros] según el
/// modo oscuro/claro que ya eligió para el resto de la app. Ver
/// [SecretoPalette].
class _SecretoColoresOscuros {
  const _SecretoColoresOscuros();

  Color get fondo => const Color(0xFF0B111C);
  Color get fondoProfundo => const Color(0xFF060A11);
  Color get halo => const Color(0x80162031);

  Color get laton => const Color(0xFFC9A96A);
  Color get latonClaro => const Color(0xFFE7D3A8);
  Color get latonProfundo => const Color(0xFF8A6F3C);

  /// Color de las motas de polvo: el más claro de latón, para que brillen
  /// como chispas contra el azul oscuro.
  Color get mota => latonClaro;

  Color get tinta => const Color(0xFFF2EDE3);
  Color get tintaTenue => const Color(0x99F2EDE3);
  Color get tintaSusurro => const Color(0x5AF2EDE3);
}

/// Paleta clara: pergamino cálido en vez de medianoche, con el mismo latón
/// pero en tonos más profundos — sobre un fondo claro, el latón pálido de la
/// versión oscura se perdería por falta de contraste.
class _SecretoColoresClaros {
  const _SecretoColoresClaros();

  Color get fondo => const Color(0xFFF7F1E3);
  Color get fondoProfundo => const Color(0xFFE9DEC2);
  Color get halo => const Color(0x40C9A96A);

  Color get laton => const Color(0xFF9C7A3F);
  Color get latonClaro => const Color(0xFFB8935A);
  Color get latonProfundo => const Color(0xFF6B4F24);

  /// Sobre pergamino, la mota tiene que ser la más oscura del set: el latón
  /// claro de la versión nocturna es casi invisible aquí.
  Color get mota => latonProfundo;

  Color get tinta => const Color(0xFF241C10);
  Color get tintaTenue => const Color(0x99241C10);
  Color get tintaSusurro => const Color(0x5A241C10);
}

/// Paleta resuelta del mundo secreto, ya elegida entre oscura y clara.
///
/// Se obtiene con [SecretoPalette.of], que lee `Theme.of(context).brightness`
/// — el mismo brightness que ya decide el modo oscuro/claro del resto de la
/// app (ver `ThemeProvider` y `main.dart`), así que el enigma cambia de
/// vestuario solo con lo que el usuario ya eligió, sin leer esa preferencia
/// por su cuenta.
class SecretoPalette {
  const SecretoPalette._(this._oscuro, this._claro, this.esOscuro);

  factory SecretoPalette.of(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return SecretoPalette._(
      const _SecretoColoresOscuros(),
      const _SecretoColoresClaros(),
      oscuro,
    );
  }

  final _SecretoColoresOscuros _oscuro;
  final _SecretoColoresClaros _claro;
  final bool esOscuro;

  Color get fondo => esOscuro ? _oscuro.fondo : _claro.fondo;
  Color get fondoProfundo =>
      esOscuro ? _oscuro.fondoProfundo : _claro.fondoProfundo;
  Color get halo => esOscuro ? _oscuro.halo : _claro.halo;
  Color get laton => esOscuro ? _oscuro.laton : _claro.laton;
  Color get latonClaro => esOscuro ? _oscuro.latonClaro : _claro.latonClaro;
  Color get latonProfundo =>
      esOscuro ? _oscuro.latonProfundo : _claro.latonProfundo;
  Color get mota => esOscuro ? _oscuro.mota : _claro.mota;
  Color get tinta => esOscuro ? _oscuro.tinta : _claro.tinta;
  Color get tintaTenue => esOscuro ? _oscuro.tintaTenue : _claro.tintaTenue;
  Color get tintaSusurro =>
      esOscuro ? _oscuro.tintaSusurro : _claro.tintaSusurro;

  TextStyle titulo(double size, {Color? color}) => GoogleFonts.baloo2(
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: color ?? tinta,
    height: 1.15,
  );

  TextStyle verso(double size, {Color? color}) => GoogleFonts.workSans(
    fontSize: size,
    fontWeight: FontWeight.w300,
    color: color ?? tinta,
    height: 1.75,
    // El interletrado abierto es lo que separa un verso de un párrafo de
    // ayuda: obliga a leer despacio, que es el ritmo del acertijo.
    letterSpacing: 0.4,
  );

  TextStyle cuerpo(double size, {Color? color}) => GoogleFonts.workSans(
    fontSize: size,
    fontWeight: FontWeight.w400,
    color: color ?? tintaTenue,
    height: 1.5,
  );

  /// Versalitas espaciadas para etiquetas cortas ("el enigma", "posición").
  TextStyle sello(double size, {Color? color}) => GoogleFonts.workSans(
    fontSize: size,
    fontWeight: FontWeight.w600,
    color: color ?? laton,
    height: 1.2,
    letterSpacing: 3.2,
  );
}

/// Fondo vivo de las dos pantallas: un degradado con motas de polvo dorado a
/// la deriva. Los colores salen de [SecretoPalette.of], así que cambian solos
/// entre el pergamino claro y la medianoche según el tema del usuario.
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
    final p = SecretoPalette.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          // Centro desplazado hacia arriba: deja el halo detrás del título y
          // la parte baja de la pantalla en sombra, que es donde va el campo.
          center: const Alignment(0, -0.55),
          radius: 1.25,
          colors: [p.halo, p.fondoProfundo],
          stops: const [0.0, 1.0],
        ),
        color: p.fondo,
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
                  color: p.mota,
                  // Sobre pergamino claro las motas necesitan pesar más para
                  // notarse; sobre medianoche, menos, porque compiten con
                  // menos ruido de fondo.
                  brilloBase: p.esOscuro ? 0.10 : 0.16,
                  brilloExtra: p.esOscuro ? 0.35 : 0.30,
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
  _PolvoPainter({
    required this.fase,
    required this.cantidad,
    required this.color,
    required this.brilloBase,
    required this.brilloExtra,
  });

  final double fase;
  final int cantidad;
  final Color color;
  final double brilloBase;
  final double brilloExtra;

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
      final brillo = brilloBase + rnd.nextDouble() * brilloExtra;
      // Deriva horizontal mínima, con desfase propio: sin ella todas subirían
      // en líneas paralelas perfectas y se leería como una cortina.
      final vaiven = math.sin((fase * velocidad + x) * math.pi * 2) * 0.02;

      // La mota sube y reaparece por abajo: (posición inicial - avance) mod 1.
      final y = (rnd.nextDouble() - fase * velocidad) % 1.0;

      // Se apagan al nacer y al morir para que nadie vea el salto del ciclo.
      final borde = math.min(y, 1 - y);
      final opacidad = brillo * (borde < 0.12 ? borde / 0.12 : 1.0);

      pincel.color = color.withValues(alpha: opacidad);
      canvas.drawCircle(
        Offset((x + vaiven) * size.width, y * size.height),
        radio,
        pincel,
      );
    }
  }

  @override
  bool shouldRepaint(_PolvoPainter anterior) =>
      anterior.fase != fase ||
      anterior.cantidad != cantidad ||
      anterior.color != color;
}

/// Filete de latón: una línea que se desvanece hacia los extremos. Separa
/// bloques sin meter una caja ni un Divider de app normal.
class SecretoFilete extends StatelessWidget {
  const SecretoFilete({super.key, this.ancho = 120});

  final double ancho;

  @override
  Widget build(BuildContext context) {
    final laton = SecretoPalette.of(context).laton;
    return Container(
      width: ancho,
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            laton.withValues(alpha: 0),
            laton,
            laton.withValues(alpha: 0),
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
