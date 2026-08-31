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
  final ScrollController _scroll = ScrollController();

  /// Ancla el campo dentro del scroll: al enfocar, se pide que ESTE widget
  /// quede visible, no un punto fijo de la pantalla. Con un offset fijo el
  /// campo se habría quedado mal ubicado en pantallas de otro alto.
  final GlobalKey _campoKey = GlobalKey();

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
  void initState() {
    super.initState();
    // El teclado tarda en abrirse: se espera a que la animación de inserción
    // del framework termine (~300ms es lo que tarda en Android e iOS) antes
    // de medir dónde quedó el campo, si no `ensureVisible` calcula la
    // posición contra el layout viejo y se queda corto.
    _focus.addListener(() {
      if (!_focus.hasFocus) return;
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        final contexto = _campoKey.currentContext;
        if (!mounted || contexto == null) return;
        Scrollable.ensureVisible(
          contexto,
          alignment: 0.5,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      });
    });
  }

  @override
  void dispose() {
    _sacudida.dispose();
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
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
      await Navigator.of(
        context,
      ).pushReplacement(_transicionAlPremio(resuelto));
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
      pageBuilder: (context, animacion, secundaria) =>
          EnigmaResueltoScreen(resultado: resuelto),
      transitionsBuilder: (context, animacion, secundaria, hijo) =>
          FadeTransition(
            opacity: CurvedAnimation(
              parent: animacion,
              curve: Curves.easeInOut,
            ),
            child: hijo,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = SecretoPalette.of(context);

    return Scaffold(
      backgroundColor: p.fondo,
      // El teclado empuja el contenido; con `resizeToAvoidBottomInset` en
      // true el fondo se recortaría y las motas saltarían al abrirse.
      resizeToAvoidBottomInset: false,
      body: SecretoFondo(
        child: SafeArea(
          child: Stack(
            children: [
              const _SalidaDiscreta(),
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      32,
                      48,
                      32,
                      // El teclado no encoge el Scaffold (resize en false),
                      // así que el aire de sobra hay que crearlo a mano: sin
                      // este padding no hay nada que desplazar y
                      // `ensureVisible` no tendría hacia dónde mover el
                      // campo cuando el teclado lo tapa.
                      48 + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    // `ConstrainedBox` con la altura del viewport: con
                    // contenido corto (teclado cerrado) el Column se centra
                    // como antes; en cuanto el padding del teclado hace que
                    // el contenido exceda esa altura, dejan de aplicar
                    // `mainAxisAlignment.center` y `ensureVisible` puede
                    // desplazar de verdad.
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
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
                                  style: p.verso(16.5),
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
                                  'Di mi nombre.\nSin espacios, sin mayúsculas, todo junto.',
                                  textAlign: TextAlign.center,
                                  style: p.verso(16.5, color: p.latonClaro),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                          SecretoAparicion(
                            retraso: const Duration(milliseconds: 5400),
                            duracion: const Duration(milliseconds: 1200),
                            child: _Campo(
                              key: _campoKey,
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
                                style: p.cuerpo(13.5, color: p.tintaSusurro),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
    final p = SecretoPalette.of(context);

    return Column(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: p.latonProfundo, width: 1),
            gradient: RadialGradient(
              colors: [
                p.laton.withValues(alpha: 0.20),
                p.laton.withValues(alpha: 0),
              ],
            ),
          ),
          child: Icon(Icons.key_outlined, size: 22, color: p.laton),
        ),
        const SizedBox(height: 22),
        Text('E L   E N I G M A', style: p.sello(11)),
        const SizedBox(height: 14),
        Text(
          'Encontraste la puerta.',
          textAlign: TextAlign.center,
          style: p.titulo(26),
        ),
        const SizedBox(height: 10),
        Text(
          'Nadie te va a decir si vas bien.\nY nadie más sabe que estás aquí.',
          textAlign: TextAlign.center,
          style: p.cuerpo(13.5),
        ),
      ],
    );
  }
}

/// Campo de respuesta: una tarjeta de cristal con borde de latón, no una
/// línea subrayada — el resto de la pantalla ya es todo tipografía y aire,
/// así que el único elemento con el que se interactúa se merece pesar un
/// poco más que texto.
class _Campo extends StatefulWidget {
  const _Campo({
    super.key,
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
  State<_Campo> createState() => _CampoState();
}

class _CampoState extends State<_Campo> {
  @override
  void initState() {
    super.initState();
    // El halo y el color del borde dependen de si el campo tiene foco, y eso
    // no lo notifica `controller` — sin este listener, enfocar el campo no
    // repintaría nada hasta la primera tecla.
    widget.focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focus.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final p = SecretoPalette.of(context);
    final conFoco = widget.focus.hasFocus;

    return AnimatedBuilder(
      animation: widget.sacudida,
      builder: (context, hijo) {
        // Tres vaivenes que se apagan: seno de 3 ciclos por una envolvente
        // lineal descendente.
        final t = widget.sacudida.value;
        final desplazamiento = t == 0
            ? 0.0
            : (1 - t) * 9 * math.sin(t * 3 * 2 * math.pi);
        return Transform.translate(
          offset: Offset(desplazamiento, 0),
          child: hijo,
        );
      },
      child: Column(
        children: [
          Text('TU RESPUESTA', style: p.sello(9.5)),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            padding: const EdgeInsets.fromLTRB(22, 4, 8, 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: (p.esOscuro ? Colors.white : Colors.black).withValues(
                alpha: conFoco ? 0.05 : 0.03,
              ),
              border: Border.all(
                color: conFoco
                    ? p.laton
                    : p.latonProfundo.withValues(alpha: 0.7),
                width: conFoco ? 1.4 : 1,
              ),
              boxShadow: conFoco
                  ? [
                      BoxShadow(
                        color: p.laton.withValues(alpha: 0.16),
                        blurRadius: 22,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focus,
                    enabled: !widget.enviando,
                    autofocus: false,
                    textAlign: TextAlign.center,
                    maxLength: 60,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => widget.onEnviar(),
                    cursorColor: p.laton,
                    cursorWidth: 1.4,
                    cursorRadius: const Radius.circular(2),
                    style: p.verso(18, color: p.latonClaro),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '· · ·',
                      hintStyle: p.verso(18, color: p.tintaSusurro),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _BotonEnviar(
                  controller: widget.controller,
                  enviando: widget.enviando,
                  onEnviar: widget.onEnviar,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón de envío: relleno con degradado de latón cuando hay algo que
/// mandar, apagado cuando no. Redondo e integrado en la pastilla del campo,
/// no un ícono suelto al lado.
class _BotonEnviar extends StatelessWidget {
  const _BotonEnviar({
    required this.controller,
    required this.enviando,
    required this.onEnviar,
  });

  final TextEditingController controller;
  final bool enviando;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context) {
    final p = SecretoPalette.of(context);
    // El brazo del botón siempre es latón sólido en los dos temas; lo que
    // cambia es el color de encima para que el trazo se lea: en oscuro el
    // latón queda claro (ícono oscuro), en claro el latón queda más denso
    // (ícono claro).
    final colorEnBoton = p.esOscuro ? p.fondoProfundo : Colors.white;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, valor, _) {
        final habilitado = !enviando && valor.text.trim().isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: habilitado
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [p.latonClaro, p.laton],
                  )
                : null,
            color: habilitado
                ? null
                : (p.esOscuro ? Colors.white : Colors.black).withValues(
                    alpha: 0.04,
                  ),
            border: habilitado ? null : Border.all(color: p.latonProfundo),
            boxShadow: habilitado
                ? [
                    BoxShadow(
                      color: p.laton.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: habilitado ? onEnviar : null,
              child: Center(
                child: enviando
                    ? SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: colorEnBoton,
                        ),
                      )
                    : Icon(
                        Icons.arrow_forward_rounded,
                        size: 19,
                        color: habilitado ? colorEnBoton : p.tintaSusurro,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// La salida: una flecha apenas visible en la esquina. Existe porque de toda
/// pantalla se tiene que poder salir, pero no compite con el acertijo.
class _SalidaDiscreta extends StatelessWidget {
  const _SalidaDiscreta();

  @override
  Widget build(BuildContext context) {
    final p = SecretoPalette.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: Icon(Icons.close_rounded, size: 20, color: p.tintaSusurro),
        tooltip: 'Salir',
      ),
    );
  }
}
