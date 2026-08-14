// La sección "Pagar con tarjeta" del detalle de producto.
//
// Lo que se prueba es su regla más importante: cuándo NO existe. Un botón de
// pagar que lleva a un cobro imposible —porque el vendedor desconectó su
// cuenta de Mercado Pago— es peor que no ofrecer el pago, y por eso la
// condición se consulta en vivo al backend en vez de leerse de los métodos
// que el vendedor anuncia en su perfil.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/features/payments/pay_with_card_section.dart';
import 'package:mercadito_um/features/payments/payment_models.dart';
import 'package:mercadito_um/models.dart';

const _categoria = MarketplaceCategory(
  id: 'otros',
  name: 'Otros',
  emoji: '📦',
  icon: Icons.category,
  color: Color(0xFF607D8B),
);

const _vendedor = Seller(
  id: 'v_1',
  name: 'Tacos UM',
  avatarInitials: 'TU',
  major: '',
  rating: 5,
  reviews: 3,
  verified: true,
  paymentMethods: ['efectivo', 'tarjeta'],
);

Product _producto({
  double precio = 120,
  double? precioAnterior,
  String? etiquetaDescuento,
  bool oferta = false,
  int? stock,
  Seller? vendedor,
}) => Product(
  stockQuantity: stock,
  id: 'p_1',
  title: 'Orden de tacos',
  price: precio,
  previousPrice: precioAnterior,
  discountLabel: etiquetaDescuento,
  isOffer: oferta,
  category: _categoria,
  description: 'Ricos',
  publishedAgo: 'hace 1 h',
  seller: vendedor ?? _vendedor,
  imageIcon: Icons.fastfood,
  imageColor: const Color(0xFF607D8B),
);

/// [tarjetaDisponible] es lo que responde el backend en `cardEnabled`: si la
/// cuenta de Mercado Pago del vendedor puede cobrar AHORA. [declaraTarjeta]
/// es si además marcó el checkbox en su perfil — deliberadamente distinto,
/// porque la sección no debe depender de eso.
VendorPaymentMethods _metodos({
  required bool tarjetaDisponible,
  bool declaraTarjeta = true,
  String? clavePublica = 'APP_USR-pk',
}) => VendorPaymentMethods(
  vendorId: 'v_1',
  methods: [
    const VendorPaymentMethod(id: 'efectivo', available: true),
    if (declaraTarjeta)
      VendorPaymentMethod(id: 'tarjeta', available: tarjetaDisponible),
  ],
  cardEnabled: tarjetaDisponible && clavePublica != null,
  cardPublicKey: tarjetaDisponible ? clavePublica : null,
);

Future<void> _montar(
  WidgetTester tester, {
  required Product producto,
  required Future<VendorPaymentMethods> Function(String) cargar,
  ValueChanged<int>? onPagar,
  bool pagando = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: PayWithCardSection(
          product: producto,
          pagando: pagando,
          onPagar: onPagar ?? (_) {},
          cargarMetodos: cargar,
        ),
      ),
    ),
  );
  // pump() y no pumpAndSettle(): con `pagando: true` el botón muestra un
  // CircularProgressIndicator, que anima para siempre y nunca "asienta".
  await tester.pump(); // resuelve el future de la consulta de métodos
  await tester.pump(); // pinta el resultado
}

void main() {
  testWidgets('se muestra cuando el vendedor puede cobrar con tarjeta', (
    tester,
  ) async {
    await _montar(
      tester,
      producto: _producto(),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
    );

    expect(find.text('Pagar ahora'), findsOneWidget);
  });

  testWidgets('no dibuja NADA si la cuenta del vendedor está caída', (
    tester,
  ) async {
    await _montar(
      tester,
      producto: _producto(),
      cargar: (_) async => _metodos(tarjetaDisponible: false),
    );

    // Ni el botón ni un aviso ni un hueco: el detalle de producto no es el
    // sitio donde explicarle al comprador la situación del vendedor.
    expect(find.text('Pagar ahora'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    final tamano = tester.getSize(find.byType(PayWithCardSection));
    expect(tamano.height, 0);
  });

  testWidgets(
    'se muestra si la cuenta cobra, aunque no haya marcado "tarjeta"',
    (tester) async {
      // El caso que motivó todo esto: conectar Mercado Pago y marcar el
      // checkbox del perfil son dos acciones distintas, y la gente hace la
      // primera sin la segunda. /payments/checkout solo exige la cuenta
      // conectada, así que esconder el pago aquí le niega ventas que su
      // cuenta cobraría hoy mismo.
      await _montar(
        tester,
        producto: _producto(),
        cargar: (_) async =>
            _metodos(tarjetaDisponible: true, declaraTarjeta: false),
      );

      expect(find.text('Pagar ahora'), findsOneWidget);
    },
  );

  testWidgets('no dibuja nada si el vendedor no tiene clave pública', (
    tester,
  ) async {
    // Una cuenta conectada pero sin public key deja al comprador en un
    // callejón: la opción aparece y no hay con qué tokenizar la tarjeta.
    await _montar(
      tester,
      producto: _producto(),
      cargar: (_) async =>
          _metodos(tarjetaDisponible: true, clavePublica: null),
    );

    expect(find.text('Pagar ahora'), findsNothing);
  });

  testWidgets('no dibuja nada si la consulta al backend falla', (tester) async {
    await _montar(
      tester,
      producto: _producto(),
      cargar: (_) async => throw Exception('sin red'),
    );

    expect(find.text('Pagar ahora'), findsNothing);
    expect(tester.getSize(find.byType(PayWithCardSection)).height, 0);
  });

  testWidgets('la sección no repite el precio, que ya está arriba', (
    tester,
  ) async {
    await _montar(
      tester,
      producto: _producto(
        precio: 80,
        precioAnterior: 100,
        etiquetaDescuento: '-20%',
        oferta: true,
      ),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
    );

    // El precio ya lo pinta la etiqueta grande del detalle; repetirlo aquí
    // dejaba dos precios distintos compitiendo en la misma pantalla.
    expect(find.textContaining('80'), findsNothing);
    expect(find.textContaining('100'), findsNothing);
    expect(find.text('-20%'), findsNothing);
    expect(find.text('Pagar ahora'), findsOneWidget);
  });

  testWidgets('el botón queda inerte mientras se crea la orden', (
    tester,
  ) async {
    var toques = 0;
    await _montar(
      tester,
      producto: _producto(),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
      onPagar: (_) => toques++,
      pagando: true,
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    // Sin esto, dos toques seguidos crean dos órdenes por el mismo producto.
    expect(toques, 0);
    expect(find.text('Preparando tu pago…'), findsOneWidget);
  });

  testWidgets('fuera de horario la sección se muestra pero no deja pagar', (
    tester,
  ) async {
    var toques = 0;
    await _montar(
      tester,
      producto: _producto(vendedor: _vendedorCerrado()),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
      onPagar: (_) => toques++,
    );

    // Se ve, con el motivo — no desaparece. Si desapareciera, el comprador
    // creería que el producto no se vende, en vez de volver más tarde.
    expect(find.textContaining('Cerrado ahora mismo'), findsOneWidget);
    expect(find.text('Pagar ahora'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(toques, 0, reason: 'el botón tiene que estar inerte');
  });

  testWidgets('agotado tampoco deja pagar, y lo dice', (tester) async {
    var toques = 0;
    await _montar(
      tester,
      producto: _producto(stock: 0),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
      onPagar: (_) => toques++,
    );

    expect(find.textContaining('Agotado'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(toques, 0);
  });

  testWidgets('con stock y dentro de horario sí se puede pagar', (
    tester,
  ) async {
    var toques = 0;
    await _montar(
      tester,
      producto: _producto(stock: 3),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
      onPagar: (_) => toques++,
    );

    expect(find.textContaining('Cerrado'), findsNothing);
    expect(find.textContaining('Agotado'), findsNothing);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(toques, 1);
  });

  testWidgets('un producto sin stock definido no se bloquea', (tester) async {
    // Quedan productos viejos con stock null. Bloquearlos castigaría al
    // comprador por un dato que solo el vendedor puede arreglar.
    var toques = 0;
    await _montar(
      tester,
      producto: _producto(stock: null),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
      onPagar: (_) => toques++,
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(toques, 1);
  });

  // ─── Selector de cantidad ───────────────────────────────────

  testWidgets('la cantidad arranca en 1 y no baja de ahí', (tester) async {
    await _montar(
      tester,
      producto: _producto(stock: 5),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
    );

    expect(find.text('1'), findsOneWidget);

    // El "−" está apagado en 1: comprar cero unidades no es una compra, y
    // dejar bajar hasta 0 obligaría a validar un estado que no significa nada.
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('la cantidad no pasa del stock disponible', (tester) async {
    await _montar(
      tester,
      producto: _producto(stock: 2),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
    );

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    // Tercer toque contra un stock de 2: el backend rechazaría la orden, así
    // que el tope se respeta aquí y el comprador no llega al error.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('sin stock definido la cantidad no tiene techo', (tester) async {
    await _montar(
      tester,
      producto: _producto(stock: null),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
    );

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
    }
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('la cantidad elegida es la que se manda a pagar', (tester) async {
    int? pedida;
    await _montar(
      tester,
      producto: _producto(stock: 5),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
      onPagar: (cantidad) => pedida = cantidad,
    );

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    // Lo que se ve y lo que se cobra tienen que ser el mismo número.
    expect(pedida, 3);
  });

  testWidgets('el total aparece solo al pasar de una unidad', (tester) async {
    await _montar(
      tester,
      producto: _producto(precio: 120, stock: 5),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
    );

    // Con una unidad el total sería el precio de arriba otra vez.
    expect(find.text('Total'), findsNothing);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();

    expect(find.text('Total'), findsOneWidget);
    expect(find.text('\$240'), findsOneWidget);
  });

  testWidgets('con una sola unidad en stock no se dibuja el selector', (
    tester,
  ) async {
    await _montar(
      tester,
      producto: _producto(stock: 1),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
    );

    // Un stepper que no puede moverse ocupa una fila sin ofrecer ninguna
    // decisión.
    expect(find.text('Cantidad'), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.text('Pagar ahora'), findsOneWidget);
  });

  testWidgets('agotado no ofrece selector de cantidad', (tester) async {
    await _montar(
      tester,
      producto: _producto(stock: 0),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
    );

    expect(find.text('Cantidad'), findsNothing);
  });
}

/// Vendedor cerrado ahora mismo, sea cual sea la hora a la que corra el test:
/// se le configura horario solo en un día que no es hoy.
Seller _vendedorCerrado() {
  final hoy = DateTime.now().weekday - 1;
  return Seller(
    id: 'v_1',
    name: 'Tacos UM',
    avatarInitials: 'TU',
    major: '',
    rating: 5,
    reviews: 3,
    verified: true,
    isBusiness: true,
    paymentMethods: const ['tarjeta'],
    businessHours: {
      (hoy + 3) % 7: const BusinessHoursRange(open: '09:00', close: '18:00'),
    },
  );
}
