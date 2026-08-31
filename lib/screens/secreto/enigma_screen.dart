import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import 'enigma_resuelto_screen.dart';
import 'secreto_theme.dart';

/// La pantalla del acertijo. No hay ruta hacia aquí en ningún menú: se llega
/// escribiendo la frase exacta en el campo de comentarios de cualquier
/// publicación (ver backend/src/routes/comments.js).
///
/// Los textos van escritos en el archivo y no en `assets/translations`, al
/// revés que toda la app. Dos razones: un enigma tiene una sola voz — se
/// escribió en español y se lee en español, como un grabado —, y las claves
/// sueltas en el .json que cualquiera abre serían la pista más barata del
/// juego para alguien que ni siquiera lo está buscando.
class EnigmaScreen extends StatefulWidget {
  const EnigmaScreen({super.key});

  static const _versos = [
    'Sin manos sostengo lo que vendes.',
    'Sin voz pregono lo que ofreces.',
    'Sin ojos encuentro a quien te busca.',
    'Vivo en tu bolsillo y no peso nada.',
  ];

  @override
  State<EnigmaScreen> createState() => _EnigmaScreenState();
}

class _EnigmaScreenState extends State<EnigmaScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _enviando = false;

  /// Se muestra bajo el campo cuando la respuesta no era. Corto y sin pistas:
  /// el juego es el juego.
  String? _veredicto;

  /// Sacudida del campo al fallar. Un `AnimationController` que va de 0 a 1
  /// una sola vez por intento fallido; la curva seno de abajo lo convierte en
  /// tres vaivenes que se apagan.
  late final AnimationController _sacudida = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _sacudida.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _intentar() async {
    final respuesta = _controller.text.trim();
    if (respuesta.isEmpty || _enviando) return;

    setState(() {
      _enviando = true;
      _veredicto = null;
    });
    _focus.unfocus();

    try {
      final resuelto = await ApiService.resolverEnigma(respuesta);
      if (!mounted) return;

      if (resuelto == null) {
        setState(() {
          _enviando = false;
          _veredicto = 'No.';
        });
        _sacudida.forward(from: 0);
        HapticFeedback.mediumImpact();
        return;
      }

      HapticFeedback.heavyImpact();
      // `pushReplacement`: quien ya cruzó no vuelve al acertijo con el botón
      // atrás — vuelve a la publicación donde estaba, como si nada.
      await Navigator.of(context).pushReplacement(_transicionAlPremio(resuelto));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _veredicto = e.toString().replaceFirst('Exception: ', '');
      });
      _sacudida.forward(from: 0);
    }
  }

  /// Fundido a negro y de vuelta: el corte entre las dos pantallas del mundo
  /// secreto no debe parecer una navegación normal de la app.
  Route<void> _transicionAlPremio(EnigmaResuelto resuelto) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 900),
      reverseTransitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animacion, secundaria) => EnigmaResueltoScreen(resultado: resuelto),
      transitionsBuilder: (context, animacion, secundaria, hijo) => FadeTransition(
        opacity: CurvedAnimation(parent: animacion, curve: Curves.easeInOut),
        child: hijo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SecretoColors.noche,
      // El teclado empuja el contenido; con `resizeToAvoidBottomInset` en
      // true el fondo se recortaría y las motas saltarían al abrirse.
      resizeToAvoidBottomInset: false,
      body: SecretoFondo(
        child: SafeArea(
          child: Stack(
            children: [
              const _SalidaDiscreta(),
              Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    32,
                    48,
                    32,
                    48 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SecretoAparicion(
                        duracion: Duration(milliseconds: 1400),
                        child: _Encabezado(),
                      ),
                      const SizedBox(height: 40),
                      // Verso por verso, con casi un segundo entre líneas:
                      // el acertijo se revela al ritmo al que se lee.
                      for (var i = 0; i < EnigmaScreen._versos.length; i++)
                        SecretoAparicion(
                          retraso: Duration(milliseconds: 900 + i * 750),
                          duracion: const Duration(milliseconds: 1200),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              EnigmaScreen._versos[i],
                              textAlign: TextAlign.center,
                              style: SecretoType.verso(16.5),
                            ),
                          ),
                        ),
                      const SizedBox(height: 26),
                      SecretoAparicion(
                        retraso: const Duration(milliseconds: 4200),
                        duracion: const Duration(milliseconds: 1400),
                        child: Column(
                          children: [
                            const SecretoFilete(),
                            const SizedBox(height: 26),
                            Text(
                              'Di mi nombre.\nPero dilo como lo diría un espejo.',
                              textAlign: TextAlign.center,
                              style: SecretoType.verso(
                                16.5,
                                color: SecretoColors.latonClaro,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      SecretoAparicion(
                        retraso: const Duration(milliseconds: 5400),
                        duracion: const Duration(milliseconds: 1200),
                        child: _Campo(
                          controller: _controller,
                          focus: _focus,
                          enviando: _enviando,
                          sacudida: _sacudida,
                          onEnviar: _intentar,
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Altura reservada: sin ella, el veredicto empujaría
                      // el campo hacia arriba al aparecer.
                      SizedBox(
                        height: 22,
                        child: AnimatedOpacity(
                          opacity: _veredicto == null ? 0 : 1,
                          duration: const Duration(milliseconds: 220),
                          child: Text(
                            _veredicto ?? '',
                            textAlign: TextAlign.center,
                            style: SecretoType.cuerpo(
                              13.5,
                              color: SecretoColors.tintaSusurro,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: SecretoColors.latonProfundo, width: 1),
            gradient: const RadialGradient(
              colors: [Color(0x33C9A96A), Color(0x00C9A96A)],
            ),
          ),
          child: const Icon(
            Icons.key_outlined,
            size: 22,
            color: SecretoColors.laton,
          ),
        ),
        const SizedBox(height: 22),
        Text('E L   E N I G M A', style: SecretoType.sello(11)),
        const SizedBox(height: 14),
        Text(
          'Encontraste la puerta.',
          textAlign: TextAlign.center,
          style: SecretoType.titulo(26),
        ),
        const SizedBox(height: 10),
        Text(
          'Nadie te va a decir si vas bien.\nY nadie más sabe que estás aquí.',
          textAlign: TextAlign.center,
          style: SecretoType.cuerpo(13.5),
        ),
      ],
    );
  }
}

/// Campo de respuesta: sin caja de formulario, solo una línea de latón. Que
/// no se parezca a ningún input del resto de la app es la intención.
class _Campo extends StatelessWidget {
  const _Campo({
    required this.controller,
    required this.focus,
    required this.enviando,
    required this.sacudida,
    required this.onEnviar,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool enviando;
  final AnimationController sacudida;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sacudida,
      builder: (context, hijo) {
        // Tres vaivenes que se apagan: seno de 3 ciclos por una envolvente
        // lineal descendente.
        final t = sacudida.value;
        final desplazamiento = t == 0
            ? 0.0
            : (1 - t) * 9 * math.sin(t * 3 * 2 * math.pi);
        return Transform.translate(
          offset: Offset(desplazamiento, 0),
          child: hijo,
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              enabled: !enviando,
              autofocus: false,
              textAlign: TextAlign.center,
              maxLength: 60,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onEnviar(),
              cursorColor: SecretoColors.laton,
              cursorWidth: 1.2,
              style: SecretoType.verso(19, color: SecretoColors.latonClaro),
              decoration: InputDecoration(
                counterText: '',
                hintText: '· · ·',
                hintStyle: SecretoType.verso(
                  19,
                  color: SecretoColors.tintaSusurro,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 12),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: SecretoColors.latonProfundo),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: SecretoColors.laton, width: 1.4),
                ),
                disabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: SecretoColors.latonProfundo),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SizedBox(
              width: 44,
              height: 44,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, valor, _) {
                  final habilitado = !enviando && valor.text.trim().isNotEmpty;
                  return IconButton(
                    onPressed: habilitado ? onEnviar : null,
                    style: IconButton.styleFrom(
                      shape: const CircleBorder(
                        side: BorderSide(color: SecretoColors.latonProfundo),
                      ),
                      foregroundColor: SecretoColors.laton,
                      disabledForegroundColor: SecretoColors.tintaSusurro,
                    ),
                    icon: enviando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.4,
                              color: SecretoColors.laton,
                            ),
                          )
                        : const Icon(Icons.arrow_forward_rounded, size: 18),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La salida: una flecha apenas visible en la esquina. Existe porque de toda
/// pantalla se tiene que poder salir, pero no compite con el acertijo.
class _SalidaDiscreta extends StatelessWidget {
  const _SalidaDiscreta();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(
          Icons.close_rounded,
          size: 20,
          color: SecretoColors.tintaSusurro,
        ),
        tooltip: 'Salir',
      ),
    );
  }
}
