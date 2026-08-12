import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';

/// Campo de código de verificación de 6 dígitos.
///
/// Avanza solo al escribir, retrocede al borrar una casilla vacía y reparte
/// el código completo si el usuario lo pega (o si el sistema lo autocompleta
/// desde el SMS). Avisa por [onCompleto] en cuanto están las 6 casillas, para
/// no obligar a tocar un botón extra.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.onCompleto,
    this.onCambio,
    this.longitud = 6,
    this.habilitado = true,
  });

  final ValueChanged<String> onCompleto;

  /// Se dispara en cada edición con el código parcial. Lo usa la pantalla
  /// para habilitar el botón "Verificar código" solo cuando están las 6
  /// casillas, sin tener que sondear el estado de este widget.
  final ValueChanged<String>? onCambio;

  final int longitud;
  final bool habilitado;

  @override
  State<OtpInput> createState() => OtpInputState();
}

class OtpInputState extends State<OtpInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focos;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.longitud,
      (_) => TextEditingController(),
    );
    _focos = List.generate(widget.longitud, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focos) {
      f.dispose();
    }
    super.dispose();
  }

  /// Vacía el campo y devuelve el foco al inicio. Lo usa la pantalla al
  /// pedir un código nuevo o tras un intento fallido.
  void limpiar() {
    for (final c in _controllers) {
      c.clear();
    }
    widget.onCambio?.call('');
    if (mounted) {
      setState(() {});
      _focos.first.requestFocus();
    }
  }

  String get _codigo => _controllers.map((c) => c.text).join();

  void _alCambiar(int indice, String valor) {
    // Código pegado o autocompletado: se reparte entre las casillas a partir
    // de la actual en vez de quedarse con un solo dígito.
    if (valor.length > 1) {
      final digitos = valor.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i + indice < widget.longitud && i < digitos.length; i++) {
        _controllers[indice + i].text = digitos[i];
      }
      final ultima = (indice + digitos.length).clamp(0, widget.longitud - 1);
      _focos[ultima].requestFocus();
      _avisarSiEstaCompleto();
      setState(() {});
      return;
    }

    if (valor.isNotEmpty && indice < widget.longitud - 1) {
      _focos[indice + 1].requestFocus();
    }
    _avisarSiEstaCompleto();
    setState(() {});
  }

  void _avisarSiEstaCompleto() {
    final codigo = _codigo;
    widget.onCambio?.call(codigo);
    if (codigo.length == widget.longitud) {
      widget.onCompleto(codigo);
    }
  }

  /// Backspace sobre una casilla vacía devuelve el foco a la anterior: sin
  /// esto el usuario se queda atorado y tiene que tocar la casilla a mano.
  KeyEventResult _alPresionarTecla(int indice, KeyEvent evento) {
    if (evento is KeyDownEvent &&
        evento.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[indice].text.isEmpty &&
        indice > 0) {
      _controllers[indice - 1].clear();
      _focos[indice - 1].requestFocus();
      widget.onCambio?.call(_codigo);
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.longitud, (i) {
        final lleno = _controllers[i].text.isNotEmpty;
        return Padding(
          padding: EdgeInsets.only(right: i == widget.longitud - 1 ? 0 : 8),
          child: SizedBox(
            width: 46,
            child: Focus(
              onKeyEvent: (_, evento) => _alPresionarTecla(i, evento),
              child: TextField(
                controller: _controllers[i],
                focusNode: _focos[i],
                enabled: widget.habilitado,
                autofocus: i == 0,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                // El autofill del SMS entrega el código completo a un solo
                // campo; _alCambiar lo reparte.
                autofillHints: i == 0
                    ? const [AutofillHints.oneTimeCode]
                    : null,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: AppTypography.heading(22, color: context.colors.ink),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: lleno
                          ? context.colors.primary
                          : context.colors.border,
                      width: lleno ? 1.6 : 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: context.colors.primary,
                      width: 1.8,
                    ),
                  ),
                ),
                onChanged: (valor) => _alCambiar(i, valor),
              ),
            ),
          ),
        );
      }),
    );
  }
}
