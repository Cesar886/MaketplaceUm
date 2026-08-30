import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Botón "Continuar con Google" con el aspecto que pide el branding de
/// Google: fondo blanco, borde gris claro, la G a color a la izquierda,
/// texto oscuro centrado y esquinas suaves.
///
/// Sigue funcionando en tema oscuro, donde Google permite el fondo #131314
/// con borde #8E918F.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.cargando = false,
    this.etiqueta,
  });

  /// null deja el botón deshabilitado (mientras corre otra petición, o
  /// mientras no haya Client ID configurado).
  final VoidCallback? onPressed;

  /// Pinta el spinner en lugar del texto, sin cambiar el tamaño del botón.
  final bool cargando;

  /// Texto alterno. Por defecto "Continuar con Google", que sirve igual para
  /// iniciar sesión que para registrarse — es lo que recomienda Google, y
  /// aquí además es literal: el mismo botón hace las dos cosas según si la
  /// cuenta existe.
  final String? etiqueta;

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final fondo = oscuro ? const Color(0xFF131314) : Colors.white;
    final borde = oscuro ? const Color(0xFF8E918F) : const Color(0xFFDADCE0);
    final texto = oscuro ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F);

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: cargando ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: fondo,
          foregroundColor: texto,
          disabledBackgroundColor: fondo.withValues(alpha: 0.6),
          side: BorderSide(color: borde),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: cargando
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.muted,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const GoogleLogo(size: 20),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      etiqueta ?? 'auth.google_continue'.tr(),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: texto,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// La G de Google, dibujada en el canvas.
///
/// Se dibuja en vez de cargarse como imagen para no meter un binario al
/// repo por un icono de 20 px. Si algún día hace falta el archivo oficial
/// exacto (developers.google.com/identity/branding-guidelines), basta con
/// sustituir este widget por un `Image.asset`: nadie más lo usa.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  static const _azul = Color(0xFF4285F4);
  static const _rojo = Color(0xFFEA4335);
  static const _amarillo = Color(0xFFFBBC05);
  static const _verde = Color(0xFF34A853);

  static double _rad(double grados) => grados * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final lado = math.min(size.width, size.height);
    final grosor = lado * 0.23;
    final radio = (lado - grosor) / 2;
    final centro = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: centro, radius: radio);

    final trazo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor;

    // Ángulos en grados, 0° a las 3 en punto y creciendo en sentido horario
    // (el sistema de Flutter, con la Y hacia abajo). Los cuatro arcos cubren
    // la circunferencia completa y reparten los colores como el logo: rojo
    // arriba, azul a la derecha, verde abajo, amarillo a la izquierda.
    final arcos = <(Color, double, double)>[
      (_rojo, 190, 110),
      (_azul, 300, 68),
      (_verde, 8, 92),
      (_amarillo, 100, 90),
    ];
    for (final (color, inicio, barrido) in arcos) {
      canvas.drawArc(
        rect,
        _rad(inicio),
        _rad(barrido),
        false,
        trazo..color = color,
      );
    }

    // La barra horizontal azul: arranca en el centro y sale hasta el borde
    // derecho, a la altura del centro. Es lo que convierte el anillo en una
    // G y no en una C.
    final barra = Paint()..color = _azul;
    canvas.drawRect(
      Rect.fromLTRB(
        centro.dx - lado * 0.02,
        centro.dy - grosor / 2,
        centro.dx + radio + grosor / 2,
        centro.dy + grosor / 2,
      ),
      barra,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Separador "o" entre el formulario de correo y el botón de Google.
class SeparadorODivider extends StatelessWidget {
  const SeparadorODivider({super.key, this.texto});

  final String? texto;

  @override
  Widget build(BuildContext context) {
    final linea = Expanded(child: Divider(color: context.colors.border));
    return Row(
      children: [
        linea,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            texto ?? 'auth.or'.tr(),
            style: TextStyle(
              color: context.colors.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        linea,
      ],
    );
  }
}
