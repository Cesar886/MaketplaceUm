import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/screens/seller_profile_screen.dart';
import 'package:mercadito_um/widgets/badges.dart';

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
      });

      expect(seller.colorAcento, 'salvia');
      expect(seller.productoFijadoId, 'p9');
      expect(seller.respondeRapido, isTrue);
      expect(seller.rachaSemanas, 4);
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
}
