import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../services/api_error.dart';
import 'mp_tokenizer.dart';
import 'payment_models.dart';
import 'payments_api.dart';

/// Formulario de tarjeta nueva.
///
/// El número y el CVV NO pasan por nuestro backend: se envían directamente a
/// `api.mercadopago.com/v1/card_tokens` con la clave pública (ver
/// [MpTokenizer]) y lo único que llega a nuestro servidor es el token
/// resultante. Los controladores se limpian al salir para no dejar los
/// datos vivos en memoria más de lo necesario.
class AddCardScreen extends StatefulWidget {
  const AddCardScreen({super.key});

  @override
  State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numero = TextEditingController();
  final _vencimiento = TextEditingController();
  final _cvv = TextEditingController();
  final _titular = TextEditingController();

  PaymentsConfig? _config;
  String? _error;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarConfig();
  }

  @override
  void dispose() {
    // Limpiar antes de soltar: los datos de tarjeta no tienen por qué seguir
    // en memoria después de cerrar la pantalla.
    _numero.clear();
    _cvv.clear();
    _numero.dispose();
    _vencimiento.dispose();
    _cvv.dispose();
    _titular.dispose();
    super.dispose();
  }

  Future<void> _cargarConfig() async {
    try {
      final config = await PaymentsApi.getConfig();
      if (!mounted) return;
      setState(() => _config = config);
    } catch (e, s) {
      if (!mounted) return;
      setState(() => _error = mensajeDeError(
        e,
        fallback: 'Los pagos no están disponibles en este momento.',
        stack: s,
      ));
    }
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final config = _config;
    if (config == null) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final partes = _vencimiento.text.split('/');
      final mes = int.parse(partes[0]);
      // Se captura a dos dígitos y se completa al siglo actual.
      final anio = 2000 + int.parse(partes[1]);

      // 1) Tarjeta → Mercado Pago, DIRECTO desde el dispositivo.
      final token = await MpTokenizer.tokenizarTarjetaNueva(
        publicKey: config.publicKey,
        numero: _numero.text,
        mesVencimiento: mes,
        anioVencimiento: anio,
        cvv: _cvv.text,
        nombreTitular: _titular.text.trim(),
      );

      // 2) Solo el token → nuestro backend.
      final tarjeta = await PaymentsApi.guardarTarjeta(token);

      if (!mounted) return;
      Navigator.pop(context, tarjeta);
    } catch (e, s) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = mensajeDeError(
          e,
          fallback: 'No se pudo guardar la tarjeta.',
          stack: s,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Agregar tarjeta')),
      body: SafeArea(
        child: _config == null && _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.muted),
                  ),
                ),
              )
            : _config == null
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    _CampoTarjeta(
                      controller: _numero,
                      etiqueta: 'Número de tarjeta',
                      hint: '4111 1111 1111 1111',
                      teclado: TextInputType.number,
                      formatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(19),
                        _EspaciadorTarjeta(),
                      ],
                      validador: _validarNumero,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _CampoTarjeta(
                            controller: _vencimiento,
                            etiqueta: 'Vencimiento',
                            hint: 'MM/AA',
                            teclado: TextInputType.number,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                              _FormateadorVencimiento(),
                            ],
                            validador: _validarVencimiento,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _CampoTarjeta(
                            controller: _cvv,
                            etiqueta: 'CVV',
                            hint: '123',
                            teclado: TextInputType.number,
                            ocultar: true,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            validador: (v) =>
                                (v == null || v.length < 3)
                                    ? 'CVV incompleto'
                                    : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _CampoTarjeta(
                      controller: _titular,
                      etiqueta: 'Nombre del titular',
                      hint: 'Como aparece en la tarjeta',
                      teclado: TextInputType.name,
                      formatters: [
                        UpperCaseTextFormatter(),
                        LengthLimitingTextInputFormatter(40),
                      ],
                      validador: (v) => (v == null || v.trim().length < 3)
                          ? 'Escribe el nombre del titular'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colors.danger.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(fontSize: 13, color: colors.ink),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    FilledButton(
                      onPressed: _guardando ? null : _guardar,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _guardando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Guardar tarjeta'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.lock_outline, size: 14, color: colors.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Los datos de tu tarjeta viajan cifrados a Mercado '
                            'Pago. Mercadito UM nunca los recibe ni los guarda.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: colors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// Valida con el algoritmo de Luhn antes de gastar una llamada a MP: casi
  /// todos los errores de captura los detecta aquí mismo, al instante.
  String? _validarNumero(String? valor) {
    final digitos = (valor ?? '').replaceAll(' ', '');
    if (digitos.length < 13) return 'Número incompleto';
    var suma = 0;
    var alterna = false;
    for (var i = digitos.length - 1; i >= 0; i--) {
      var n = int.parse(digitos[i]);
      if (alterna) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      suma += n;
      alterna = !alterna;
    }
    return suma % 10 == 0 ? null : 'El número de tarjeta no es válido';
  }

  String? _validarVencimiento(String? valor) {
    final v = valor ?? '';
    if (v.length != 5) return 'MM/AA';
    final mes = int.tryParse(v.substring(0, 2));
    final anio = int.tryParse(v.substring(3));
    if (mes == null || anio == null || mes < 1 || mes > 12) return 'Fecha inválida';

    // Una tarjeta vale hasta el ÚLTIMO día de su mes de vencimiento.
    final ahora = DateTime.now();
    final ultimoDia = DateTime(2000 + anio, mes + 1, 0);
    if (ultimoDia.isBefore(DateTime(ahora.year, ahora.month, ahora.day))) {
      return 'Tarjeta vencida';
    }
    return null;
  }
}

class _CampoTarjeta extends StatelessWidget {
  const _CampoTarjeta({
    required this.controller,
    required this.etiqueta,
    required this.hint,
    required this.teclado,
    required this.validador,
    this.formatters,
    this.ocultar = false,
  });

  final TextEditingController controller;
  final String etiqueta;
  final String hint;
  final TextInputType teclado;
  final String? Function(String?) validador;
  final List<TextInputFormatter>? formatters;
  final bool ocultar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextFormField(
      controller: controller,
      keyboardType: teclado,
      obscureText: ocultar,
      inputFormatters: formatters,
      validator: validador,
      style: TextStyle(color: colors.ink),
      decoration: InputDecoration(
        labelText: etiqueta,
        hintText: hint,
        filled: true,
        fillColor: colors.surfaceMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
      ),
    );
  }
}

/// Agrupa el número en bloques de 4 mientras se escribe.
class _EspaciadorTarjeta extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue anterior,
    TextEditingValue nuevo,
  ) {
    final digitos = nuevo.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (var i = 0; i < digitos.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digitos[i]);
    }
    final texto = buffer.toString();
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// Inserta la barra de MM/AA.
class _FormateadorVencimiento extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue anterior,
    TextEditingValue nuevo,
  ) {
    final digitos = nuevo.text.replaceAll('/', '');
    final texto = digitos.length <= 2
        ? digitos
        : '${digitos.substring(0, 2)}/${digitos.substring(2)}';
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// El nombre en las tarjetas va en mayúsculas.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue anterior,
    TextEditingValue nuevo,
  ) => TextEditingValue(
    text: nuevo.text.toUpperCase(),
    selection: nuevo.selection,
  );
}
