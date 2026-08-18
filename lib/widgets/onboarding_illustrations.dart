import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Las tres escenas del onboarding.
enum OnboardingArte { puesto, descubre, vende }

/// Ilustración del onboarding, dibujada con formas en vez de un PNG.
///
/// La razón no es ahorrar peso: es que la app deja elegir entre ocho colores
/// de acento y tiene modo oscuro, así que una ilustración de mapa de bits
/// quedaría fija en un color mientras el resto de la pantalla se repinta —
/// y en oscuro traería su propio fondo claro pegado. Dibujada, toma
/// `context.colors` y se repinta sola con el swatch que el usuario eligió.
///
/// Respeta la regla de color de la app (ver [AppColors]): el acento aparece
/// como relleno y como línea, nunca como texto. Aquí no hay texto, así que
/// la regla se cumple sola.
class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({
    super.key,
    required this.arte,
    this.size = 220,
  });

  final OnboardingArte arte;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final paleta = _Paleta(
      acento: c.accent,
      tinte: c.accentTint,
      tinteBorde: c.accentTintBorder,
      relleno: c.primary,
      superficie: c.surface,
      borde: c.border,
      tinta: c.ink,
    );

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: switch (arte) {
          OnboardingArte.puesto => _PuestoPainter(paleta),
          OnboardingArte.descubre => _DescubrePainter(paleta),
          OnboardingArte.vende => _VendePainter(paleta),
        },
      ),
    );
  }
}

/// Colores que las escenas reciben ya resueltos, para que los painters no
/// dependan de BuildContext (y `shouldRepaint` pueda compararlos).
class _Paleta {
  const _Paleta({
    required this.acento,
    required this.tinte,
    required this.tinteBorde,
    required this.relleno,
    required this.superficie,
    required this.borde,
    required this.tinta,
  });

  final Color acento;
  final Color tinte;
  final Color tinteBorde;
  final Color relleno;
  final Color superficie;
  final Color borde;
  final Color tinta;

  @override
  bool operator ==(Object other) =>
      other is _Paleta &&
      other.acento == acento &&
      other.tinte == tinte &&
      other.tinteBorde == tinteBorde &&
      other.relleno == relleno &&
      other.superficie == superficie &&
      other.borde == borde &&
      other.tinta == tinta;

  @override
  int get hashCode =>
      Object.hash(acento, tinte, tinteBorde, relleno, superficie, borde, tinta);
}

/// Base con los helpers que comparten las tres escenas.
///
/// Todo se dibuja en un espacio de diseño de 100×100 y se escala al tamaño
/// real, así las coordenadas se leen como porcentajes y la escena se ve igual
/// a 160 px que a 260.
abstract class _EscenaPainter extends CustomPainter {
  const _EscenaPainter(this.p);

  final _Paleta p;

  void pintar(Canvas canvas);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    pintar(canvas);
    canvas.restore();
  }

  Paint get _relleno => Paint()..style = PaintingStyle.fill;

  Paint trazo(Color color, [double ancho = 2.2]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = ancho
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  Paint lleno(Color color) => _relleno..color = color;

  void caja(
    Canvas canvas,
    Rect rect, {
    required Color fondo,
    Color? borde,
    double radio = 4,
  }) {
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radio));
    canvas.drawRRect(rrect, Paint()..color = fondo);
    if (borde != null) canvas.drawRRect(rrect, trazo(borde, 1.8));
  }

  @override
  bool shouldRepaint(covariant _EscenaPainter old) => old.p != p;
}

/// Escena 1 — el puesto de mercado: qué es Marketplace UM.
class _PuestoPainter extends _EscenaPainter {
  const _PuestoPainter(super.p);

  @override
  void pintar(Canvas canvas) {
    // Piso: una elipse tenue que asienta el puesto en vez de dejarlo
    // flotando en el vacío.
    canvas.drawOval(
      const Rect.fromLTWH(12, 78, 76, 12),
      lleno(p.tinte.withValues(alpha: 0.7)),
    );

    // Toldo ondulado. Las ondas son lo que lo hace leer como "puesto de
    // mercado" y no como una casa genérica.
    final toldo = Path()..moveTo(14, 34);
    toldo.lineTo(22, 16);
    toldo.lineTo(78, 16);
    toldo.lineTo(86, 34);
    for (var x = 86.0; x > 14; x -= 12) {
      toldo.arcToPoint(
        Offset(x - 12, 34),
        radius: const Radius.circular(7),
        clockwise: false,
      );
    }
    toldo.close();
    canvas.drawPath(toldo, lleno(p.relleno));

    // Franjas del toldo, en el acento y recortadas a la forma para que no se
    // salgan por las ondas.
    canvas.save();
    canvas.clipPath(toldo);
    for (var x = 22.0; x < 86; x += 16) {
      canvas.drawRect(Rect.fromLTWH(x, 14, 8, 22), lleno(p.acento));
    }
    canvas.restore();

    // Postes.
    canvas.drawLine(const Offset(20, 34), const Offset(20, 80), trazo(p.tinta));
    canvas.drawLine(const Offset(80, 34), const Offset(80, 80), trazo(p.tinta));

    // Mostrador.
    caja(
      canvas,
      const Rect.fromLTWH(18, 62, 64, 18),
      fondo: p.superficie,
      borde: p.tinta,
      radio: 3,
    );

    // Mercancía sobre el mostrador: cajas y una fruta, apenas insinuadas.
    caja(
      canvas,
      const Rect.fromLTWH(26, 48, 16, 14),
      fondo: p.tinte,
      borde: p.tinteBorde,
      radio: 2,
    );
    caja(
      canvas,
      const Rect.fromLTWH(46, 52, 12, 10),
      fondo: p.acento,
      radio: 2,
    );
    canvas.drawCircle(const Offset(68, 56), 6, lleno(p.relleno));
  }
}

/// Escena 2 — tarjeta de producto y burbuja de chat: descubre y contacta.
class _DescubrePainter extends _EscenaPainter {
  const _DescubrePainter(super.p);

  @override
  void pintar(Canvas canvas) {
    // Tarjeta de producto, con la misma anatomía que la real: foto arriba,
    // líneas de título y un precio corto abajo.
    caja(
      canvas,
      const Rect.fromLTWH(10, 18, 54, 64),
      fondo: p.superficie,
      borde: p.borde,
      radio: 6,
    );
    caja(canvas, const Rect.fromLTWH(16, 24, 42, 28), fondo: p.tinte, radio: 4);
    // Montañita dentro de la "foto": el símbolo universal de imagen.
    final foto = Path()
      ..moveTo(22, 48)
      ..lineTo(31, 36)
      ..lineTo(38, 44)
      ..lineTo(43, 39)
      ..lineTo(52, 48)
      ..close();
    canvas.drawPath(foto, lleno(p.tinteBorde));

    canvas.drawLine(
      const Offset(16, 60),
      const Offset(50, 60),
      trazo(p.borde, 3),
    );
    canvas.drawLine(
      const Offset(16, 67),
      const Offset(38, 67),
      trazo(p.borde, 3),
    );
    caja(canvas, const Rect.fromLTWH(16, 72, 20, 7), fondo: p.acento, radio: 3);

    // Burbuja de chat encimada a la tarjeta: el contacto sale del producto,
    // no es una pantalla aparte.
    final burbuja = RRect.fromRectAndRadius(
      const Rect.fromLTWH(52, 44, 40, 30),
      const Radius.circular(9),
    );
    canvas.drawRRect(burbuja, lleno(p.relleno));
    // Colita.
    final cola = Path()
      ..moveTo(60, 72)
      ..lineTo(58, 82)
      ..lineTo(70, 73)
      ..close();
    canvas.drawPath(cola, lleno(p.relleno));

    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(63 + i * 9, 59),
        3,
        lleno(p.superficie.withValues(alpha: 0.92)),
      );
    }
  }
}

/// Escena 3 — cámara y etiqueta de precio: publica lo tuyo.
class _VendePainter extends _EscenaPainter {
  const _VendePainter(super.p);

  @override
  void pintar(Canvas canvas) {
    // Cuerpo de la cámara.
    caja(
      canvas,
      const Rect.fromLTWH(14, 32, 58, 42),
      fondo: p.relleno,
      radio: 8,
    );
    // Visor sobre el cuerpo.
    caja(
      canvas,
      const Rect.fromLTWH(26, 24, 20, 10),
      fondo: p.relleno,
      radio: 3,
    );
    // Lente: anillo de acento y centro claro, para que el ojo caiga ahí.
    canvas.drawCircle(const Offset(43, 53), 15, lleno(p.acento));
    canvas.drawCircle(const Offset(43, 53), 9, lleno(p.superficie));
    canvas.drawCircle(const Offset(43, 53), 4, lleno(p.relleno));
    // Flash.
    canvas.drawCircle(const Offset(62, 41), 3.2, lleno(p.tinte));

    // Etiqueta de precio colgando en diagonal — el mismo objeto que
    // `price_tag.dart` dibuja en las tarjetas, con su ojal perforado.
    canvas.save();
    canvas.translate(74, 60);
    canvas.rotate(-0.35);
    final etiqueta = Path()
      ..moveTo(0, 8)
      ..lineTo(8, 0)
      ..lineTo(26, 0)
      ..lineTo(26, 22)
      ..lineTo(8, 22)
      ..close();
    canvas.drawPath(etiqueta, lleno(p.superficie));
    canvas.drawPath(etiqueta, trazo(p.tinta, 1.8));
    canvas.drawCircle(const Offset(9, 7), 2.2, trazo(p.tinta, 1.6));
    canvas.drawLine(
      const Offset(13, 13),
      const Offset(22, 13),
      trazo(p.acento, 2.4),
    );
    canvas.restore();
  }
}
