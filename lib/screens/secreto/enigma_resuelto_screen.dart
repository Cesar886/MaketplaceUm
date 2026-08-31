import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/api_service.dart';
import 'secreto_theme.dart';

/// La segunda puerta: lo que hay al otro lado del acertijo.
///
/// Aquí no se valida nada — cuando esta pantalla se construye, el servidor ya
/// dijo que sí y ya guardó la posición. Solo se muestra la hazaña.
class EnigmaResueltoScreen extends StatefulWidget {
  const EnigmaResueltoScreen({super.key, required this.resultado});

  final EnigmaResuelto resultado;

  @override
  State<EnigmaResueltoScreen> createState() => _EnigmaResueltoScreenState();
}

class _EnigmaResueltoScreenState extends State<EnigmaResueltoScreen>
    with SingleTickerProviderStateMixin {
  /// Late el sello despacio, como una brasa. Se repite en reversa para que no
  /// haya salto entre ciclos.
  late final AnimationController _brasa = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    // Solo para quien lo acaba de lograr: repetir la celebración cada vez que
    // vuelve a entrar la abarataría.
    if (!widget.resultado.repetida) {
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _brasa.dispose();
    super.dispose();
  }

  String get _titulo {
    if (widget.resultado.repetida) return 'Sigues siendo\nel número ${widget.resultado.posicion}.';
    if (widget.resultado.esElPrimero) return 'Nadie llegó\nantes que tú.';
    return 'Lo resolviste.';
  }

  String get _subtitulo {
    if (widget.resultado.esElPrimero) {
      return 'Eres la primera persona en resolver el enigma de Mercadito.\nEsa posición ya no se puede volver a ganar.';
    }
    final antes = widget.resultado.posicion - 1;
    return 'Antes que tú lo lograron $antes ${antes == 1 ? 'persona' : 'personas'}.\nDespués de ti, quien llegue tendrá que conformarse con el ${widget.resultado.total + 1}.';
  }

  void _compartir() {
    // Se comparte la hazaña, nunca la frase ni la respuesta: el juego sigue
    // vivo mientras el siguiente tenga que encontrarlo por su cuenta.
    final n = widget.resultado.posicion;
    Share.share(
      n == 1
          ? 'Resolví el enigma escondido de Mercadito. Fui el #1. No te voy a decir dónde está.'
          : 'Resolví el enigma escondido de Mercadito. Soy el #$n. No te voy a decir dónde está.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SecretoColors.noche,
      body: SecretoFondo(
        // Más polvo que en el acertijo: la sala del final está más viva.
        motas: 60,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SecretoAparicion(
                    duracion: const Duration(milliseconds: 1600),
                    desplazamiento: 0,
                    child: _Sello(
                      posicion: widget.resultado.posicion,
                      brasa: _brasa,
                    ),
                  ),
                  const SizedBox(height: 34),
                  SecretoAparicion(
                    retraso: const Duration(milliseconds: 700),
                    child: Text(
                      _titulo,
                      textAlign: TextAlign.center,
                      style: SecretoType.titulo(30),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SecretoAparicion(
                    retraso: const Duration(milliseconds: 1300),
                    child: Column(
                      children: [
                        const SecretoFilete(ancho: 90),
                        const SizedBox(height: 20),
                        Text(
                          _subtitulo,
                          textAlign: TextAlign.center,
                          style: SecretoType.cuerpo(14.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  SecretoAparicion(
                    retraso: const Duration(milliseconds: 1900),
                    child: _Acta(resultado: widget.resultado),
                  ),
                  const SizedBox(height: 40),
                  SecretoAparicion(
                    retraso: const Duration(milliseconds: 2400),
                    child: Column(
                      children: [
                        _BotonLaton(
                          etiqueta: 'Presumirlo sin decir dónde',
                          icono: Icons.ios_share_rounded,
                          onTap: _compartir,
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: TextButton.styleFrom(
                            foregroundColor: SecretoColors.tintaSusurro,
                          ),
                          child: Text(
                            'Volver al mercado',
                            style: SecretoType.cuerpo(
                              13.5,
                              color: SecretoColors.tintaSusurro,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El numeral: la posición grabada en un disco de latón con un halo que late.
class _Sello extends StatelessWidget {
  const _Sello({required this.posicion, required this.brasa});

  final int posicion;
  final Animation<double> brasa;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: brasa,
      builder: (context, hijo) {
        final t = brasa.value;
        return Container(
          width: 148,
          height: 148,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Color.lerp(
                SecretoColors.latonProfundo,
                SecretoColors.laton,
                t,
              )!,
              width: 1.2,
            ),
            gradient: RadialGradient(
              colors: [
                SecretoColors.laton.withValues(alpha: 0.05 + t * 0.09),
                const Color(0x00C9A96A),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: SecretoColors.laton.withValues(alpha: 0.06 + t * 0.10),
                blurRadius: 40 + t * 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: hijo,
        );
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('POSICIÓN', style: SecretoType.sello(9)),
          const SizedBox(height: 6),
          // El numeral con degradado de latón: un ShaderMask sobre el texto,
          // que es lo más cerca del pan de oro que se llega sin una imagen.
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                SecretoColors.latonClaro,
                SecretoColors.laton,
                SecretoColors.latonProfundo,
              ],
            ).createShader(rect),
            child: Text(
              '$posicion',
              style: SecretoType.titulo(
                // Un 1 y un 128 no pueden medir lo mismo: el tamaño baja con
                // los dígitos para que el disco nunca se quede corto.
                posicion < 10
                    ? 62
                    : posicion < 100
                    ? 50
                    : 40,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El acta: los datos fríos de la hazaña, en versalitas, como un registro.
class _Acta extends StatelessWidget {
  const _Acta({required this.resultado});

  final EnigmaResuelto resultado;

  static const _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  String get _fecha {
    final fecha = resultado.resueltoEn?.toLocal();
    if (fecha == null) return 'hoy';
    final hora = fecha.hour.toString().padLeft(2, '0');
    final minuto = fecha.minute.toString().padLeft(2, '0');
    return '${fecha.day} de ${_meses[fecha.month - 1]} de ${fecha.year}, $hora:$minuto';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SecretoColors.latonProfundo.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          _Linea(etiqueta: 'RESUELTO', valor: _fecha),
          const SizedBox(height: 12),
          _Linea(
            etiqueta: 'LO HAN LOGRADO',
            valor: '${resultado.total} ${resultado.total == 1 ? 'persona' : 'personas'}',
          ),
        ],
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(etiqueta, style: SecretoType.sello(9)),
        const SizedBox(width: 18),
        Flexible(
          child: Text(
            valor,
            textAlign: TextAlign.right,
            style: SecretoType.cuerpo(13, color: SecretoColors.tinta),
          ),
        ),
      ],
    );
  }
}

/// Botón de latón: relleno tenue, borde fino, sin sombra de Material. El
/// único botón "lleno" del mundo secreto.
class _BotonLaton extends StatelessWidget {
  const _BotonLaton({
    required this.etiqueta,
    required this.icono,
    required this.onTap,
  });

  final String etiqueta;
  final IconData icono;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SecretoColors.laton.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: const BorderSide(color: SecretoColors.latonProfundo),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: SecretoColors.laton.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 16, color: SecretoColors.latonClaro),
              const SizedBox(width: 10),
              Text(
                etiqueta,
                style: SecretoType.cuerpo(14, color: SecretoColors.latonClaro),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
