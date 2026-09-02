// El checklist de verificación y el bloqueo del botón que lo acompaña.
//
// Lo que más vale proteger aquí es la relación entre las dos cosas: el
// contador puede quedar bien y el botón seguir habilitado (o al revés), y en
// ese caso el usuario avanza a pedir un código que el backend va a rechazar
// —o se queda encallado sin entender por qué—. Por eso hay tests del widget
// suelto (contador, ✓/✗, navegación) y del formulario entero montado sobre un
// AuthProvider falso con requisitos a medias.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/constants/dominios_um.dart';
import 'package:mercadito_um/models/verification_requirement.dart';
import 'package:mercadito_um/providers/auth_provider.dart';
import 'package:mercadito_um/screens/auth/verification_screen.dart';
import 'package:mercadito_um/widgets/verification_checklist.dart';
import 'package:provider/provider.dart';

void main() {
  VerificationRequirement req(
    String id, {
    required bool cumplido,
    String accion = 'editar_perfil',
  }) {
    return VerificationRequirement(
      id: id,
      titulo: 'Requisito $id',
      detalle: 'Detalle de $id',
      cumplido: cumplido,
      accion: accion,
    );
  }

  Widget envolver(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  // ─── Contador ──────────────────────────────────────────────

  group('VerificationChecklist · contador', () {
    testWidgets('con un solo pendiente el contador va en singular', (
      tester,
    ) async {
      await tester.pumpWidget(
        envolver(
          VerificationChecklist(
            requisitos: [
              req('horario', cumplido: true),
              req('metodos_pago', cumplido: true),
              req('stock_productos', cumplido: false),
            ],
            onAccion: (_) {},
          ),
        ),
      );

      expect(find.text('Te falta 1 requisito'), findsOneWidget);
    });

    testWidgets('el contador cuenta los pendientes, no está fijo en 1', (
      tester,
    ) async {
      await tester.pumpWidget(
        envolver(
          VerificationChecklist(
            requisitos: [
              req('horario', cumplido: false),
              req('metodos_pago', cumplido: false),
              req('stock_productos', cumplido: false),
            ],
            onAccion: (_) {},
          ),
        ),
      );

      expect(find.text('Te faltan 3 requisitos'), findsOneWidget);
    });

    testWidgets('sin pendientes anuncia que está todo listo', (tester) async {
      await tester.pumpWidget(
        envolver(
          VerificationChecklist(
            requisitos: [
              req('horario', cumplido: true),
              req('metodos_pago', cumplido: true),
            ],
            onAccion: (_) {},
          ),
        ),
      );

      expect(find.text('Todo listo para verificarte'), findsOneWidget);
      final palomita = find.byIcon(Icons.verified_rounded);
      expect(palomita, findsOneWidget);
      expect(tester.widget<Icon>(palomita).color, AppColors.verifiedBlue);
      expect(
        tester.getCenter(palomita).dx,
        greaterThan(
          tester.getCenter(find.text('Todo listo para verificarte')).dx,
        ),
      );
      expect(find.textContaining('Te falta'), findsNothing);
    });

    testWidgets('una lista vacía no pinta nada', (tester) async {
      // Sin requisitos cargados (arranque sin conexión) el hueco de la caja
      // vacía se leería como "no falta nada", que es justo lo contrario.
      await tester.pumpWidget(
        envolver(VerificationChecklist(requisitos: const [], onAccion: (_) {})),
      );

      expect(find.byType(Container), findsNothing);
    });
  });

  // ─── ✓ / ✗ y navegación ────────────────────────────────────

  group('VerificationChecklist · filas', () {
    testWidgets('cada requisito lleva su ✓ o su ✗ según el estado real', (
      tester,
    ) async {
      await tester.pumpWidget(
        envolver(
          VerificationChecklist(
            requisitos: [
              req('horario', cumplido: true),
              req('metodos_pago', cumplido: false),
              req('stock_productos', cumplido: false),
            ],
            onAccion: (_) {},
          ),
        ),
      );

      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cancel_rounded), findsNWidgets(2));
    });

    testWidgets('el chevron y el detalle solo aparecen en los pendientes', (
      tester,
    ) async {
      await tester.pumpWidget(
        envolver(
          VerificationChecklist(
            requisitos: [
              req('horario', cumplido: true),
              req('metodos_pago', cumplido: false),
            ],
            onAccion: (_) {},
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.text('Detalle de metodos_pago'), findsOneWidget);
      expect(find.text('Detalle de horario'), findsNothing);
    });

    testWidgets('tocar un pendiente pide resolver ESE requisito', (
      tester,
    ) async {
      final tocados = <String>[];
      await tester.pumpWidget(
        envolver(
          VerificationChecklist(
            requisitos: [
              req('horario', cumplido: false),
              req(
                'stock_productos',
                cumplido: false,
                accion: 'revisar_productos',
              ),
            ],
            onAccion: (r) => tocados.add('${r.id}:${r.accion}'),
          ),
        ),
      );

      await tester.tap(find.text('Requisito stock_productos'));
      await tester.pump();

      expect(tocados, ['stock_productos:revisar_productos']);
    });

    testWidgets('un requisito cumplido no navega a ninguna parte', (
      tester,
    ) async {
      var tocado = false;
      await tester.pumpWidget(
        envolver(
          VerificationChecklist(
            requisitos: [req('horario', cumplido: true)],
            onAccion: (_) => tocado = true,
          ),
        ),
      );

      await tester.tap(find.text('Requisito horario'));
      await tester.pump();

      expect(tocado, isFalse, reason: 'no hay nada que arreglar ahí');
    });
  });

  // ─── Bloqueo del botón ─────────────────────────────────────

  group('VerificationScreen · bloqueo de "Enviar código"', () {
    Widget pantalla(
      AuthProvider auth, {
      AccountType tipo = AccountType.estudiante,
    }) {
      return ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: VerificationScreen(tipo: tipo),
        ),
      );
    }

    ElevatedButton botonPrincipal(WidgetTester tester, String etiqueta) {
      return tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text(etiqueta),
          matching: find.byType(ElevatedButton),
        ),
      );
    }

    testWidgets('con un requisito pendiente el botón queda deshabilitado', (
      tester,
    ) async {
      final auth = _AuthDePrueba([
        req('horario', cumplido: true),
        req('metodos_pago', cumplido: true),
        req('stock_productos', cumplido: false),
      ]);

      await tester.pumpWidget(pantalla(auth));
      await tester.pumpAndSettle();

      expect(botonPrincipal(tester, 'Enviar código').onPressed, isNull);
      // El botón apagado por sí solo no explica nada: el aviso de debajo es
      // lo que conecta "no puedo pulsar esto" con "porque me falta esto".
      expect(
        find.text('Completa los requisitos de arriba para poder verificarte.'),
        findsOneWidget,
      );
    });

    testWidgets('con los requisitos cumplidos el botón se habilita', (
      tester,
    ) async {
      final auth = _AuthDePrueba([
        req('horario', cumplido: true),
        req('metodos_pago', cumplido: true),
        req('stock_productos', cumplido: true),
      ]);

      await tester.pumpWidget(pantalla(auth));
      await tester.pumpAndSettle();

      expect(botonPrincipal(tester, 'Enviar código').onPressed, isNotNull);
      expect(find.text('Todo listo para verificarte'), findsOneWidget);
      expect(
        find.text('Completa los requisitos de arriba para poder verificarte.'),
        findsNothing,
      );
    });

    testWidgets('una cuenta externa no entra al flujo de verificación', (
      tester,
    ) async {
      final auth = _AuthDePrueba([
        req('metodos_pago', cumplido: false),
      ], tipo: AccountType.particular);

      await tester.pumpWidget(pantalla(auth, tipo: AccountType.particular));
      await tester.pumpAndSettle();

      expect(find.text('¡Cuenta creada!'), findsOneWidget);
      expect(find.text('Enviar código por SMS'), findsNothing);
    });

    testWidgets('la cuenta de cobros no se lista mientras MP esté apagado', (
      tester,
    ) async {
      // Con Mercado Pago deshabilitado el backend la da por cumplida; pintarle
      // un ✓ a algo que la persona nunca hizo confunde cuando MP vuelva.
      final auth = _AuthDePrueba([
        req('mercadopago', cumplido: true, accion: 'conectar_mercadopago'),
        req('metodos_pago', cumplido: true),
      ]);

      await tester.pumpWidget(pantalla(auth));
      await tester.pumpAndSettle();

      expect(find.text('Requisito mercadopago'), findsNothing);
      expect(find.text('Requisito metodos_pago'), findsOneWidget);
    });

    testWidgets('un negocio con solicitud enviada ve la pantalla pendiente', (
      tester,
    ) async {
      final auth = _AuthDePrueba(
        const [],
        tipo: AccountType.negocio,
        manualPending: true,
      );

      await tester.pumpWidget(pantalla(auth, tipo: AccountType.negocio));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      expect(find.text('Enviar solicitud de verificación'), findsNothing);
      expect(find.byType(VerificationChecklist), findsNothing);
    });
  });

  // ─── Detección de dominio (alumno / personal) ───────────────

  group('DominioUM.detectarDesde', () {
    test('los dos primeros caracteres no deciden nada', () {
      expect(DominioUM.detectarDesde(''), isNull);
      expect(DominioUM.detectarDesde('1'), isNull);
      expect(DominioUM.detectarDesde('a1'), isNull);
      expect(DominioUM.detectarDesde('12'), isNull);
    });

    test('un dígito a partir del tercer carácter es cuenta de alumno', () {
      expect(DominioUM.detectarDesde('155'), DominioUM.alumno);
      expect(DominioUM.detectarDesde('1550001'), DominioUM.alumno);
      // Las dos primeras posiciones se ignoran aunque sean letras.
      expect(DominioUM.detectarDesde('ab5'), DominioUM.alumno);
    });

    test('una letra a partir del tercer carácter es cuenta de empleado', () {
      expect(DominioUM.detectarDesde('jua'), DominioUM.personal);
      expect(DominioUM.detectarDesde('juan.perez'), DominioUM.personal);
      // Y aunque las dos primeras sean números.
      expect(DominioUM.detectarDesde('15a'), DominioUM.personal);
    });

    test('decide el PRIMER carácter decisivo, no el último', () {
      // En 'jua4' el que manda es la 'a' de la posición 2, no el 4 final.
      expect(DominioUM.detectarDesde('jua4'), DominioUM.personal);
      expect(DominioUM.detectarDesde('1554n'), DominioUM.alumno);
    });

    test('un carácter que no es letra ni dígito no decide: sigue buscando', () {
      // Un punto en tercera posición deja la cuenta ambigua hasta el
      // siguiente carácter, que es el que manda.
      expect(DominioUM.detectarDesde('ju.'), isNull);
      expect(DominioUM.detectarDesde('ju.n'), DominioUM.personal);
      expect(DominioUM.detectarDesde('15.7'), DominioUM.alumno);
    });

    test('el dominio detectado decide si se pide carrera', () {
      expect(DominioUM.detectarDesde('1550001')!.pideCarrera, isTrue);
      expect(DominioUM.detectarDesde('juan.perez')!.pideCarrera, isFalse);
    });
  });
}

/// AuthProvider con los requisitos ya resueltos, para montar la pantalla sin
/// backend: refrescar es un no-op y la lista es la que pide cada test.
class _AuthDePrueba extends AuthProvider {
  _AuthDePrueba(
    this._requisitosDePrueba, {
    this.tipo = AccountType.estudiante,
    this.manualPending = false,
  });

  final List<VerificationRequirement> _requisitosDePrueba;
  final AccountType tipo;
  final bool manualPending;

  @override
  Map<String, dynamic>? get currentUser => const {
    'id': 1,
    'name': 'Prueba',
    'user_type': 'negocio',
  };

  @override
  AccountType get accountType => tipo;

  @override
  List<VerificationRequirement> get requisitos => _requisitosDePrueba;

  @override
  bool get solicitudManualPendiente => manualPending;

  @override
  String get estadoVerificacion => 'pendiente';

  @override
  Future<Map<String, dynamic>?> getBusinessProfileLocal() async => const {
    'business_name': 'Negocio de prueba',
    'business_type': 'Comida',
    'responsible_name': 'Responsable de prueba',
  };

  @override
  Future<void> refrescarEstadoVerificacion() async {}
}
