// Modelos del módulo de pagos.
//
// Lo que se prueba aquí es lo que decide qué ve una persona cuando algo sale
// mal (los códigos de rechazo de Mercado Pago) y lo que decide si una
// tarjeta se puede usar. Nada de esto llama a la red.

import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/features/payments/payment_models.dart';

void main() {
  group('SavedCard', () {
    test('solo expone los últimos cuatro dígitos y la marca', () {
      final tarjeta = SavedCard.fromJson({
        'id': 'card_123',
        'lastFourDigits': '4242',
        'paymentMethod': 'visa',
        'expirationMonth': 12,
        'expirationYear': 2030,
      });

      expect(tarjeta.lastFourDigits, '4242');
      expect(tarjeta.marcaLegible, 'Visa');
      expect(tarjeta.vencimiento, '12/30');
    });

    test('una tarjeta vale hasta el último día de su mes de vencimiento', () {
      final ahora = DateTime.now();

      final esteMes = SavedCard(
        id: 'c',
        lastFourDigits: '1111',
        paymentMethod: 'visa',
        expirationMonth: ahora.month,
        expirationYear: ahora.year,
      );
      // Vence este mes: todavía sirve, aunque hoy sea día 28.
      expect(esteMes.estaVencida, isFalse);

      final mesPasado = SavedCard(
        id: 'c',
        lastFourDigits: '1111',
        paymentMethod: 'visa',
        expirationMonth: ahora.month == 1 ? 12 : ahora.month - 1,
        expirationYear: ahora.month == 1 ? ahora.year - 1 : ahora.year,
      );
      expect(mesPasado.estaVencida, isTrue);
    });

    test('sin fecha de vencimiento no se marca como vencida', () {
      const tarjeta = SavedCard(
        id: 'c',
        lastFourDigits: '1111',
        paymentMethod: 'visa',
      );
      expect(tarjeta.estaVencida, isFalse);
      expect(tarjeta.vencimiento, '');
    });

    test('una marca desconocida se muestra tal cual, no como vacío', () {
      const tarjeta = SavedCard(
        id: 'c',
        lastFourDigits: '1111',
        paymentMethod: 'elo',
      );
      expect(tarjeta.marcaLegible, 'elo');
    });
  });

  group('CheckoutResult', () {
    CheckoutResult resultado(String status, [String? detail]) =>
        CheckoutResult.fromJson({
          'orderId': 'ord_1',
          'status': status,
          'amount': 250.0,
          if (detail != null) 'statusDetail': detail,
        });

    test('mapea los estados de Mercado Pago a los tres que muestra la app', () {
      expect(resultado('approved').estado, EstadoPago.aprobado);
      expect(resultado('in_process').estado, EstadoPago.pendiente);
      expect(resultado('pending').estado, EstadoPago.pendiente);
      expect(resultado('rejected').estado, EstadoPago.rechazado);
      expect(resultado('cancelled').estado, EstadoPago.rechazado);
    });

    test('un estado que no conocemos se trata como rechazo, no como éxito', () {
      // Si MP inventa un estado nuevo, darlo por bueno significaría decirle a
      // alguien que pagó cuando quizá no. El sesgo tiene que ir al otro lado.
      expect(resultado('estado_futuro_desconocido').estado, EstadoPago.rechazado);
    });

    test('cada código de rechazo da un mensaje accionable distinto', () {
      final cvv = resultado('rejected', 'cc_rejected_bad_filled_security_code');
      final fondos = resultado('rejected', 'cc_rejected_insufficient_amount');

      expect(cvv.mensaje, contains('CVV'));
      expect(fondos.mensaje, contains('fondos'));
      expect(cvv.mensaje, isNot(equals(fondos.mensaje)));
    });

    test('un código desconocido da un mensaje útil, nunca vacío', () {
      final r = resultado('rejected', 'cc_rejected_codigo_que_no_existe');
      expect(r.mensaje, isNotEmpty);
      expect(r.mensaje, contains('otra tarjeta'));
    });

    test('ningún mensaje filtra el código técnico de Mercado Pago', () {
      for (final detalle in [
        'cc_rejected_bad_filled_security_code',
        'cc_rejected_high_risk',
        'cc_rejected_inventado',
      ]) {
        final mensaje = resultado('rejected', detalle).mensaje;
        expect(mensaje, isNot(contains('cc_rejected')));
        expect(mensaje, isNot(contains('_')));
      }
    });
  });

  group('PaymentOrder', () {
    test('el subtotal de cada línea usa el precio congelado de la orden', () {
      final orden = PaymentOrder.fromJson({
        'id': 'ord_1',
        'vendorId': 's1',
        'amount': 600.0,
        'applicationFee': 30.0,
        'currency': 'MXN',
        'status': 'pending',
        'items': [
          {
            'productId': 'p1',
            'quantity': 2,
            'unitPrice': 300.0,
            'title': 'Sudadera',
          },
        ],
      });

      expect(orden.items.single.subtotal, 600.0);
      expect(orden.amount, 600.0);
      expect(orden.estaPagada, isFalse);
    });

    test('la comisión no se suma al total que paga quien compra', () {
      final orden = PaymentOrder.fromJson({
        'id': 'ord_1',
        'vendorId': 's1',
        'amount': 100.0,
        'applicationFee': 5.0,
        'currency': 'MXN',
        'status': 'paid',
        'items': const [],
      });

      // El total es 100, no 105: la comisión sale de lo que recibe el
      // vendedor.
      expect(orden.amount, 100.0);
      expect(orden.applicationFee, 5.0);
      expect(orden.estaPagada, isTrue);
    });
  });
}
