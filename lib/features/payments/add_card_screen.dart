// TODO: Mercado Pago pendiente para próxima actualización - no eliminar,
// solo descomentar/reactivar cuando esté listo (ver mercado_pago_flag.dart).
// Todo este archivo queda inactivo e inaccesible desde la UI mientras
// kMercadoPagoHabilitado sea false.
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../services/api_error.dart';
import 'mp_tokenizer.dart';
import 'payments_api.dart';

/// Formulario de tarjeta nueva.
///
/// El número y el CVV NO pasan por nuestro backend: se envían directamente a
/// `api.mercadopago.com/v1/card_tokens` con la clave pública (ver
/// [MpTokenizer]) y lo único que llega a nuestro servidor es el token
/// resultante. Los controladores se limpian al salir para no dejar los
/// datos vivos en memoria más de lo necesario.
/// La tarjeta se registra CON UN VENDEDOR concreto: en el modo marketplace
/// de Mercado Pago vive dentro de la cuenta de quien va a cobrarla, y el
/// token de otro vendedor no puede usarla. De ahí que haga falta el
/// [vendorId] y, sobre todo, la [publicKey] de ese vendedor — tokenizar con
/// la clave de la plataforma produciría un token que MP rechaza al cobrar.
class AddCardScreen extends StatefulWidget {
  const AddCardScreen({
    super.key,
    required this.vendorId,
    required this.publicKey,
    this.nombreVendedor,
  });

  final String vendorId;
  final String publicKey;
  final String? nombreVendedor;

  @override
  State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numero = TextEditingController();
  final _vencimiento = TextEditingController();
  final _cvv = TextEditingController();
  final _titular = TextEditingController();

  String? _error;
  bool _guardando = false;

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

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

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
        publicKey: widget.publicKey,
        numero: _numero.text,
        mesVencimiento: mes,
        anioVencimiento: anio,
        cvv: _cvv.text,
        nombreTitular: _titular.text.trim(),
      );

      // 2) Solo el token → nuestro backend.
      final tarjeta = await PaymentsApi.guardarTarjeta(widget.vendorId, token);

      if (!mounted) return;
      Navigator.pop(context, tarjeta);
    } catch (e, s) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = mensajeDeError(
          e,
          fallback: 'payments_api.save_card_error'.tr(),
          stack: s,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(title: Text('card.add'.tr())),
      body: SafeArea(
        // Ya no hay carga asíncrona previa: la clave pública del vendedor
        // llega como parámetro desde el checkout, que es quien la consultó.
        // El formulario se pinta directo y los errores se muestran dentro.
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              _CampoTarjeta(
                controller: _numero,
                etiqueta: 'card.number'.tr(),
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
                      validador: (v) => (v == null || v.length < 3)
                          ? 'card.cvv_incomplete'.tr()
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _CampoTarjeta(
                controller: _titular,
                etiqueta: 'card.holder'.tr(),
                hint: 'card.holder_hint'.tr(),
                teclado: TextInputType.name,
                formatters: [
                  UpperCaseTextFormatter(),
                  LengthLimitingTextInputFormatter(40),
                ],
                validador: (v) => (v == null || v.trim().length < 3)
                    ? 'card.holder_write'.tr()
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
                      : Text('card.save'.tr()),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: colors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'card.security_note'.tr(),
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
    if (digitos.length < 13) return 'card.number_incomplete'.tr();
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
    return suma % 10 == 0 ? null : 'card.number_invalid'.tr();
  }

  String? _validarVencimiento(String? valor) {
    final v = valor ?? '';
    if (v.length != 5) return 'MM/AA';
    final mes = int.tryParse(v.substring(0, 2));
    final anio = int.tryParse(v.substring(3));
    if (mes == null || anio == null || mes < 1 || mes > 12)
      return 'card.date_invalid'.tr();

    // Una tarjeta vale hasta el ÚLTIMO día de su mes de vencimiento.
    final ahora = DateTime.now();
    final ultimoDia = DateTime(2000 + anio, mes + 1, 0);
    if (ultimoDia.isBefore(DateTime(ahora.year, ahora.month, ahora.day))) {
      return 'card.expired'.tr();
    }
    return null;
  }
}

class _CampoTarjeta extends StatelessWidget {
  const _CampoTarjeta({
    required this.controller,
    required this.etiqueta,
    required this.teclado,
    required this.validador,
    this.hint,
    this.formatters,
    this.ocultar = false,
  });

  final TextEditingController controller;
  final String etiqueta;

  /// Placeholder del campo. Opcional a propósito: el número de tarjeta se
  /// queda SIN hint porque el único ejemplo que cabe ahí es un número con
  /// forma de tarjeta real, y un '4111 1111 1111 1111' en gris dentro del
  /// campo se lee como si el formulario ya viniera relleno.
  ///
  /// En los demás campos sí ayuda: 'MM/AA' y '123' comunican un formato, no
  /// un valor.
  final String? hint;
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
