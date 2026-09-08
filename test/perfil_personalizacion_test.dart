import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/screens/seller_profile_screen.dart';
import 'package:mercadito_um/utils/estado_conexion.dart';
import 'package:mercadito_um/widgets/badges.dart';
import 'package:mercadito_um/widgets/seller_profile_header.dart';

Product _producto(String id) => Product(
  id: id,
  title: 'Producto $id',
  price: 100,
  category: const MarketplaceCategory(
    id: 'c_1',
    name: 'Libros',
    emoji: '📚',
    icon: Icons.menu_book_rounded,
    color: Color(0xFF3F51B5),
  ),
  description: '',
  publishedAgo: 'hace 1 día',
  seller: const Seller(
    id: 's_1',
    name: 'Vendedor',
    avatarInitials: 'V',
    major: 'Estudiante',
    rating: 0,
    reviews: 0,
    verified: false,
  ),
  imageIcon: Icons.menu_book_rounded,
  imageColor: const Color(0xFF3F51B5),
);

List<String> _ids(List<Product> ps) => ps.map((p) => p.id).toList();

/// Envuelve un widget con el tema real de la app para que `context.colors`
/// resuelva contra el brillo correcto.
Widget _app(Widget child, {Brightness brillo = Brightness.light}) {
  return MaterialApp(
    theme: brillo == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('Seller.fromJson — personalización', () {
    test('lee color, producto fijado y métricas del perfil', () {
      final seller = Seller.fromJson({
        'id': 's1',
        'name': 'Tienda',
        'rating': 4.5,
        'reviews': 10,
        'verified': true,
        'colorAcento': 'salvia',
        'productoFijadoId': 'p9',
        'respondeRapido': true,
        'rachaSemanas': 4,
        'productViews': 321,
        'profileViews': 45,
      });

      expect(seller.colorAcento, 'salvia');
      expect(seller.productoFijadoId, 'p9');
      expect(seller.respondeRapido, isTrue);
      expect(seller.rachaSemanas, 4);
      expect(seller.productViews, 321);
      expect(seller.profileViews, 45);
    });

    test('un perfil sin personalizar cae a los defaults, no a null', () {
      // El listado de vendedores no manda estos campos: construir un Seller
      // desde esa respuesta no debe reventar ni mostrar badges falsos.
      final seller = Seller.fromJson({
        'id': 's2',
        'name': 'Sin personalizar',
        'rating': 0,
        'reviews': 0,
        'verified': false,
      });

      expect(seller.colorAcento, isNull);
      expect(seller.productoFijadoId, isNull);
      expect(seller.respondeRapido, isFalse);
      expect(seller.rachaSemanas, 0);
      // Un colorAcento null resuelve al swatch de marca.
      expect(AccentSwatch.porId(seller.colorAcento), AccentSwatch.defecto);
    });

    test('un id de color retirado no rompe el perfil', () {
      final seller = Seller.fromJson({
        'id': 's3',
        'name': 'Color viejo',
        'rating': 0,
        'reviews': 0,
        'verified': false,
        'colorAcento': 'turquesa_que_ya_no_existe',
      });

      expect(AccentSwatch.porId(seller.colorAcento), AccentSwatch.defecto);
    });
  });

  testWidgets('el encabezado público muestra productos, no visitas privadas', (
    tester,
  ) async {
    const seller = Seller(
      id: 's_vistas',
      name: 'Tienda con vistas',
      avatarInitials: 'TV',
      major: '',
      rating: 0,
      reviews: 0,
      productViews: 321,
      profileViews: 45,
      verified: false,
    );

    await tester.pumpWidget(
      _app(
        const SellerProfileHeader(
          seller: seller,
          estadoConexion: EstadoConexion.desconocido,
          colorBanner: Color(0xFF7B2D3B),
        ),
      ),
    );

    expect(find.text('321'), findsOneWidget);
    expect(find.text('45'), findsNothing);
  });

  group('ordenarConFijadoPrimero', () {
    final lista = [_producto('a'), _producto('b'), _producto('c')];

    test('mueve el fijado al frente conservando el orden del resto', () {
      expect(_ids(ordenarConFijadoPrimero(lista, 'c')), ['c', 'a', 'b']);
    });

    test('sin fijado devuelve la lista tal cual', () {
      expect(_ids(ordenarConFijadoPrimero(lista, null)), ['a', 'b', 'c']);
    });

    test('si el fijado ya es el primero no reordena', () {
      expect(_ids(ordenarConFijadoPrimero(lista, 'a')), ['a', 'b', 'c']);
    });

    test('un fijado que no está en la lista no la altera', () {
      // Pasa cuando la publicación fijada dejó de estar disponible: se
      // filtró antes de llegar aquí y fijarla no debe resucitarla.
      expect(_ids(ordenarConFijadoPrimero(lista, 'agotado')), ['a', 'b', 'c']);
    });

    test('no muta la lista original', () {
      final original = [_producto('x'), _producto('y')];
      ordenarConFijadoPrimero(original, 'y');
      expect(_ids(original), ['x', 'y']);
    });

    test('una lista vacía no revienta', () {
      expect(ordenarConFijadoPrimero(<Product>[], 'a'), isEmpty);
    });
  });

  group('colorDeBannerDeVendedor', () {
    test('usa el acento del VENDEDOR, sin importar el tema ambiente', () {
      // No recibe BuildContext ni lee ningún ThemeData ambiente — eso es
      // justo lo que impide que "sangre" el acento de quien mira hacia el
      // perfil de otra persona, que es el bug que este helper existe para
      // prevenir (el mismo error que tuvo el anillo y el indicador antes
      // de corregirse).
      final vendedor = Seller(
        id: 's_wine',
        name: 'Tienda Wine',
        avatarInitials: 'TW',
        major: '',
        rating: 0,
        reviews: 0,
        verified: false,
        colorAcento: 'wine',
      );

      expect(
        colorDeBannerDeVendedor(vendedor, Brightness.light),
        AccentSwatch.wine.fill,
      );
      expect(
        colorDeBannerDeVendedor(vendedor, Brightness.dark),
        AccentSwatch.wine.darkFill,
      );
    });

    test('un vendedor sin color elegido cae al de marca', () {
      final sinColor = Seller(
        id: 's_sin_color',
        name: 'Sin personalizar',
        avatarInitials: 'SC',
        major: '',
        rating: 0,
        reviews: 0,
        verified: false,
      );

      expect(
        colorDeBannerDeVendedor(sinColor, Brightness.light),
        AccentSwatch.defecto.fill,
      );
    });
  });

  group('temaDeVendedor', () {
    Seller conColor(String? color) => Seller(
      id: 's_tema',
      name: 'Tienda',
      avatarInitials: 'T',
      major: '',
      rating: 0,
      reviews: 0,
      verified: false,
      colorAcento: color,
    );

    // testWidgets y no test: armar el ThemeData pasa por google_fonts,
    // que en un test pelado deja una carga de red huérfana que revienta el
    // zone. El binding de widgets es lo que la absorbe.
    testWidgets('toda la pantalla toma el acento del vendedor', (tester) async {
      // No solo el banner: es el ThemeData que envuelve AppBar, botón de
      // contactar y pestañas, así que lo que se comprueba es el acento del
      // tema entero.
      final tema = temaDeVendedor(conColor('wine'), Brightness.light);

      expect(tema.extension<AppColorSet>()!.swatch, AccentSwatch.wine);
      expect(tema.extension<AppColorSet>()!.primary, AccentSwatch.wine.fill);
    });

    testWidgets('el claro/oscuro sigue siendo el de quien mira', (
      tester,
    ) async {
      // El acento es del vendedor; el brillo NO se hereda del perfil ajeno.
      // Un visitante en modo oscuro no debe recibir un fondo claro por abrir
      // la tienda de alguien.
      final claro = temaDeVendedor(conColor('wine'), Brightness.light);
      final oscuro = temaDeVendedor(conColor('wine'), Brightness.dark);

      expect(claro.brightness, Brightness.light);
      expect(oscuro.brightness, Brightness.dark);
      expect(oscuro.extension<AppColorSet>()!.swatch, AccentSwatch.wine);
    });

    testWidgets('sin perfil cargado todavía usa el color de marca', (
      tester,
    ) async {
      // Mientras carga no hay vendedor: el esqueleto se pinta con el acento
      // de la app y no con el del visitante, que sería adelantar un color
      // que a lo mejor no es el que llega.
      final tema = temaDeVendedor(null, Brightness.light);

      expect(tema.extension<AppColorSet>()!.swatch, AccentSwatch.defecto);
    });
  });

  group('Badges de perfil', () {
    testWidgets('RespondeRapidoBadge se pinta con el verde de disponible', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const RespondeRapidoBadge()));

      expect(find.text('Responde rápido'), findsOneWidget);
      // Verde semántico, no el color elegido: "responde rápido" significa lo
      // mismo sin importar qué swatch tenga puesto quien mira.
      final icono = tester.widget<Icon>(find.byIcon(Icons.bolt_rounded));
      expect(icono.color, AppColors.success);
    });

    // El globo al tocar una insignia repetía su nombre, que ya está a la
    // vista: ahora dice cómo se consigue, que es lo que el nombre no explica.
    testWidgets('el globo dice cómo se consigue la insignia', (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InsigniaLeyenda(),
              RespondeRapidoBadge(),
              RachaBadge(semanas: 5),
            ],
          ),
        ),
      );

      final globos = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(globos, contains('100 ventas confirmadas'));
      expect(globos, contains('Contesta en menos de 1 hora'));
      expect(globos, contains('Semanas seguidas publicando'));
      // Y ninguno se limita a repetir la etiqueta de al lado.
      expect(globos, isNot(contains('Leyenda')));
      expect(globos, isNot(contains('Responde rápido')));
    });

    // La excepción: el enigma no se explica en ninguna parte de la app, así
    // que su globo tampoco puede delatarlo.
    testWidgets('el enigma solo dice que está oculto', (tester) async {
      await tester.pumpWidget(_app(const InsigniaEnigma(posicion: 3)));

      final globo = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(globo.message, 'Oculto');
      expect(find.text('Enigma #3'), findsOneWidget);
    });

    testWidgets('RachaBadge dice cuántas semanas', (tester) async {
      await tester.pumpWidget(_app(const RachaBadge(semanas: 5)));

      expect(find.text('5 semanas activo'), findsOneWidget);
    });

    testWidgets('los badges sobreviven al modo oscuro', (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [RespondeRapidoBadge(), RachaBadge(semanas: 3)],
          ),
          brillo: Brightness.dark,
        ),
      );

      expect(find.text('Responde rápido'), findsOneWidget);
      expect(find.text('3 semanas activo'), findsOneWidget);
      // En oscuro el verde se aclara: si siguiera siendo el de tema claro,
      // quedaría por debajo del contraste sobre la superficie oscura.
      final icono = tester.widget<Icon>(find.byIcon(Icons.bolt_rounded));
      expect(icono.color, AppColors.successOnDark);
    });
  });

  // La banda de marca ya no termina donde empieza la AppBar: la pantalla la
  // dibuja por detrás de ella para que el degradado y su brillo arranquen
  // desde arriba del todo y no se vea la costura entre las dos. Eso solo
  // funciona si la banda le reserva el hueco a lo que lleva encima.
  group('espacioSuperior de la banda', () {
    Seller vendedor() => const Seller(
      id: 's_banda',
      name: 'Tienda',
      avatarInitials: 'T',
      major: '',
      rating: 0,
      reviews: 0,
      verified: false,
    );

    Future<Rect> montar(WidgetTester tester, double espacio) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SellerProfileHeader(
              seller: vendedor(),
              estadoConexion: EstadoConexion.desconocido,
              colorBanner: const Color(0xFF7B2D3B),
              espacioSuperior: espacio,
            ),
          ),
        ),
      );
      return tester.getRect(find.text('Tienda'));
    }

    testWidgets('empuja el contenido hacia abajo sin recortarlo', (
      tester,
    ) async {
      final sinEspacio = await montar(tester, 0);
      final conEspacio = await montar(tester, 56);
      // El nombre baja exactamente lo que se reservó: si bajara de menos, el
      // avatar quedaría por debajo del título de la AppBar.
      expect(conEspacio.top - sinEspacio.top, 56);
      expect(tester.takeException(), isNull);
    });

    testWidgets('montado suelto no reserva nada', (tester) async {
      // El valor por defecto es 0 para que el header se pueda montar fuera de
      // la pantalla (pruebas, capturas) sin un hueco de color arriba.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SellerProfileHeader(
              seller: vendedor(),
              estadoConexion: EstadoConexion.desconocido,
              colorBanner: const Color(0xFF7B2D3B),
            ),
          ),
        ),
      );
      final header = tester.widget<SellerProfileHeader>(
        find.byType(SellerProfileHeader),
      );
      expect(header.espacioSuperior, 0);
    });
  });
}
