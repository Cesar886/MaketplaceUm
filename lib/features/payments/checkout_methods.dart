// TODO: Mercado Pago pendiente para próxima actualización - no eliminar,
// solo descomentar/reactivar cuando esté listo (ver mercado_pago_flag.dart).
// Todo este archivo queda inactivo e inaccesible desde la UI mientras
// kMercadoPagoHabilitado sea false.
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import 'payment_models.dart';

/// Las piezas que hacen que la pantalla de pago admita varios métodos.
///
/// El objetivo de este archivo es que añadir "efectivo en tienda" u otra
/// billetera sea: un valor nuevo en [MetodoDePagoId], un [MetodoDePago] más
/// en la lista que arma el checkout, y el cuerpo que ese método necesite.
/// Nada de lo de aquí crece con el número de métodos.
///
/// Los colores salen todos de `context.colors`, que es lo que sigue al
/// swatch que la persona eligió (lavanda en las capturas). Ningún morado
/// literal: fijarlo aquí dejaría esta pantalla desalineada del resto de la
/// app en cuanto alguien cambie de swatch.

/// Un método de pago tal como se le ofrece al comprador en el checkout.
///
/// Es solo la TARJETA SELECCIONABLE: qué se lee, qué icono lleva y si se
/// puede elegir. Lo que pasa al elegirlo —el formulario, el botón, la
/// llamada— vive en la pantalla, porque cada método necesita cosas
/// distintas y meterlas aquí obligaría a este tipo a conocerlas todas.
class MetodoDePago {
  const MetodoDePago({
    required this.id,
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    this.motivoNoDisponible,
  });

  final MetodoDePagoId id;
  final String titulo;

  /// Una línea que explica qué va a pasar al elegirlo. Importa más de lo que
  /// parece en el pago con cuenta de Mercado Pago: si nadie avisa de que la
  /// app va a mandarte al navegador, la salida se lee como un fallo.
  final String subtitulo;

  /// Se construye con el color ya resuelto para que el icono acompañe al
  /// estado de la tarjeta (apagado cuando no está elegida).
  final Widget Function(BuildContext context, Color color) icono;

  /// Por qué no se puede elegir, ya redactado. Null si sí se puede.
  final String? motivoNoDisponible;

  bool get disponible => motivoNoDisponible == null;
}

/// Selector de método: radio-cards apiladas.
///
/// Se eligieron radio-cards y no tabs porque los métodos traen un motivo de
/// por qué NO están disponibles, y una tab deshabilitada no tiene dónde
/// ponerlo. También porque la lista está pensada para crecer: cuatro tabs en
/// una pantalla de móvil ya no caben, y cuatro tarjetas sí.
///
/// Con un solo método disponible no se dibuja nada: un selector de una
/// opción es ruido que hace pensar que falta algo.
class SelectorDeMetodoDePago extends StatelessWidget {
  const SelectorDeMetodoDePago({
    super.key,
    required this.metodos,
    required this.seleccionado,
    required this.onSeleccionar,
  });

  final List<MetodoDePago> metodos;
  final MetodoDePagoId seleccionado;
  final ValueChanged<MetodoDePagoId> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    if (metodos.length < 2) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final metodo in metodos)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TarjetaDeMetodo(
              metodo: metodo,
              seleccionado: metodo.id == seleccionado,
              onSeleccionar: metodo.disponible
                  ? () => onSeleccionar(metodo.id)
                  : null,
            ),
          ),
      ],
    );
  }
}

class _TarjetaDeMetodo extends StatelessWidget {
  const _TarjetaDeMetodo({
    required this.metodo,
    required this.seleccionado,
    required this.onSeleccionar,
  });

  final MetodoDePago metodo;
  final bool seleccionado;
  final VoidCallback? onSeleccionar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final apagado = !metodo.disponible;

    return InkWell(
      onTap: onSeleccionar,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: seleccionado ? colors.accentTint : colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: seleccionado ? colors.accentTintBorder : colors.border,
            width: seleccionado ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // El radio es explícito y no solo el borde teñido: sin él, con
            // dos tarjetas de aspecto casi igual, cuál está elegida se
            // adivina por el color del marco y eso no se ve en un móvil al
            // sol ni con daltonismo.
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                seleccionado
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: apagado
                    ? colors.muted
                    : (seleccionado ? colors.accent : colors.muted),
              ),
            ),
            const SizedBox(width: 12),
            metodo.icono(context, apagado ? colors.muted : colors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metodo.titulo,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: apagado ? colors.muted : colors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metodo.motivoNoDisponible ?? metodo.subtitulo,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: apagado ? colors.danger : colors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Marca de Mercado Pago para la tarjeta de su método.
///
/// Es una pieza dibujada, no el logotipo oficial: meter el SVG de Mercado
/// Pago como asset obliga a respetar su manual de marca (proporciones, área
/// de resguardo, fondos permitidos) y a mantenerlo cuando lo cambien. Un
/// distintivo propio en su azul corporativo identifica igual dentro de una
/// lista de dos o tres opciones.
///
/// El azul es el de Mercado Pago (#009EE3) y NO se tiñe con el swatch: es el
/// único color literal de este archivo, y lo es a propósito — teñir de
/// lavanda el distintivo de otra marca la vuelve irreconocible, que es justo
/// lo que la tarjeta necesita comunicar de un vistazo.
class MarcaMercadoPago extends StatelessWidget {
  const MarcaMercadoPago({super.key, this.apagado = false, this.tamano = 34});

  /// Se pinta en gris cuando el método no está disponible, para que no
  /// destaque una opción que no se puede elegir.
  final bool apagado;
  final double tamano;

  static const azulMercadoPago = Color(0xFF009EE3);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fondo = apagado ? colors.surfaceMuted : azulMercadoPago;

    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(
        Icons.account_balance_wallet_rounded,
        size: tamano * 0.55,
        color: apagado ? colors.muted : Colors.white,
      ),
    );
  }
}

/// La caja de error de la pantalla de pago.
///
/// Existe como widget y no como un `Container` copiado en cada rama porque
/// los dos métodos fallan de formas distintas y tienen que fallar IGUAL de
/// cara al usuario: mismo fondo, mismo borde, mismo sitio. Cuando se añada
/// un tercero, el error ya está resuelto.
class CajaDeError extends StatelessWidget {
  const CajaDeError({super.key, required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.danger.withValues(alpha: 0.3)),
      ),
      child: Text(
        mensaje,
        style: TextStyle(fontSize: 13, height: 1.4, color: colors.ink),
      ),
    );
  }
}

/// El botón de pagar, con su estado de carga.
///
/// Igual que [CajaDeError]: lo comparten todos los métodos para que
/// "cargando" se vea siempre igual, y para que ninguno se olvide de
/// deshabilitarse mientras hay una operación en vuelo.
class BotonDePago extends StatelessWidget {
  const BotonDePago({
    super.key,
    required this.etiqueta,
    required this.onPressed,
    required this.cargando,
    this.icono,
  });

  final String etiqueta;
  final VoidCallback? onPressed;
  final bool cargando;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final contenido = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        etiqueta,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );

    if (cargando) {
      return FilledButton(
        onPressed: null,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return icono == null
        ? FilledButton(onPressed: onPressed, child: contenido)
        : FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icono, size: 19),
            label: contenido,
          );
  }
}
