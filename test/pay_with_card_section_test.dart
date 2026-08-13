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
}) => Product(
  id: 'p_1',
  title: 'Orden de tacos',
  price: precio,
  previousPrice: precioAnterior,
  discountLabel: etiquetaDescuento,
  isOffer: oferta,
  category: _categoria,
  description: 'Ricos',
  publishedAgo: 'hace 1 h',
  seller: _vendedor,
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
  VoidCallback? onPagar,
  bool pagando = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: PayWithCardSection(
          product: producto,
          pagando: pagando,
          onPagar: onPagar ?? () {},
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

    expect(find.text('Pagar con tarjeta'), findsOneWidget);
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
    expect(find.text('Pagar con tarjeta'), findsNothing);
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

      expect(find.text('Pagar con tarjeta'), findsOneWidget);
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

    expect(find.text('Pagar con tarjeta'), findsNothing);
  });

  testWidgets('no dibuja nada si la consulta al backend falla', (tester) async {
    await _montar(
      tester,
      producto: _producto(),
      cargar: (_) async => throw Exception('sin red'),
    );

    expect(find.text('Pagar con tarjeta'), findsNothing);
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
    expect(find.text('Pagar con tarjeta'), findsOneWidget);
  });

  testWidgets('el botón queda inerte mientras se crea la orden', (
    tester,
  ) async {
    var toques = 0;
    await _montar(
      tester,
      producto: _producto(),
      cargar: (_) async => _metodos(tarjetaDisponible: true),
      onPagar: () => toques++,
      pagando: true,
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    // Sin esto, dos toques seguidos crean dos órdenes por el mismo producto.
    expect(toques, 0);
    expect(find.text('Preparando tu pago…'), findsOneWidget);
  });
}
