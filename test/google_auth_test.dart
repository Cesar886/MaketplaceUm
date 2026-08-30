// Contrato entre la app y POST /api/auth/google.
//
// El endpoint tiene tres desenlaces y cada uno lleva a una pantalla
// distinta: entrar, ir a completar el registro, o mostrar un error. Si la
// app confunde uno con otro, el síntoma no es una excepción sino un usuario
// atrapado — por ejemplo, alguien sin cuenta al que se le dice "falló
// Google" en vez de llevarlo al registro. Estos tests fijan esa traducción
// de respuestas HTTP a resultados.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercadito_um/config/google_auth_config.dart';
import 'package:mercadito_um/services/api_service.dart';
import 'package:mercadito_um/services/google_sign_in_service.dart';
import 'package:mercadito_um/widgets/google_sign_in_button.dart';

import 'helpers/localizacion_de_prueba.dart';

/// Última petición que recibió el backend falso, para poder afirmar sobre lo
/// que la app manda (y sobre lo que NO manda).
Map<String, dynamic>? ultimoCuerpo;

void montarBackend(http.Response Function(http.Request req) responder) {
  ApiService.clienteDePrueba = MockClient((request) async {
    ultimoCuerpo = jsonDecode(request.body) as Map<String, dynamic>;
    return responder(request);
  });
}

http.Response json200(Map<String, dynamic> cuerpo, {int status = 200}) =>
    http.Response(
      jsonEncode(cuerpo),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  setUpAll(inicializarTraducciones);

  tearDown(() {
    ApiService.restaurarCliente();
    GoogleSignInService.restaurar();
    ultimoCuerpo = null;
  });

  group('ApiService.authGoogle', () {
    test('devuelve token y seller cuando la cuenta ya existe', () async {
      montarBackend(
        (_) => json200({
          'token': 'jwt-de-prueba',
          'seller': {'id': 's1', 'email': 'ana@gmail.com', 'name': 'Ana'},
          'created': false,
        }),
      );

      final res = await ApiService.authGoogle(idToken: 'tok', deviceId: 'd1');

      expect(res['token'], 'jwt-de-prueba');
      expect(ultimoCuerpo!['idToken'], 'tok');
      expect(ultimoCuerpo!['deviceId'], 'd1');
      expect(
        ultimoCuerpo!.containsKey('registro'),
        isFalse,
        reason: 'sin datos de registro no se manda la clave vacía',
      );
    });

    test('un 404 GOOGLE_ACCOUNT_NOT_FOUND es "hay que registrarse", no un '
        'error', () async {
      montarBackend(
        (_) => json200({
          'error': 'GOOGLE_ACCOUNT_NOT_FOUND',
          'message': 'No hay ninguna cuenta con ese correo.',
          'google': {
            'email': 'nuevo@gmail.com',
            'name': 'Nuevo Usuario',
            'picture': 'https://foto',
          },
        }, status: 404),
      );

      await expectLater(
        ApiService.authGoogle(idToken: 'tok'),
        throwsA(
          isA<GoogleRegistroRequeridoException>()
              .having((e) => e.email, 'email', 'nuevo@gmail.com')
              .having((e) => e.nombre, 'nombre', 'Nuevo Usuario')
              .having((e) => e.foto, 'foto', 'https://foto'),
        ),
      );
    });

    test('el registro viaja tal cual, y el correo NO', () async {
      montarBackend(
        (_) => json200({
          'token': 'jwt',
          'seller': {'id': 's2', 'email': 'nuevo@gmail.com', 'name': 'Nuevo'},
          'created': true,
        }, status: 201),
      );

      await ApiService.authGoogle(
        idToken: 'tok',
        registro: {
          'name': 'Nuevo',
          'userType': 'estudiante',
          'phone': '8261234567',
          'paymentMethods': ['efectivo'],
        },
      );

      final registro = ultimoCuerpo!['registro'] as Map<String, dynamic>;
      expect(registro['userType'], 'estudiante');
      expect(registro['paymentMethods'], ['efectivo']);
      expect(
        registro.containsKey('email'),
        isFalse,
        reason: 'el correo de la cuenta sale del idToken, no del cliente',
      );
    });

    test('un servidor sin credenciales se distingue por su código', () async {
      montarBackend(
        (_) => json200({
          'error': 'GOOGLE_NO_CONFIGURADO',
          'message': 'El inicio de sesión con Google no está configurado.',
        }, status: 503),
      );

      await expectLater(
        ApiService.authGoogle(idToken: 'tok'),
        throwsA(
          isA<GoogleAuthException>()
              .having((e) => e.faltaConfigurar, 'faltaConfigurar', isTrue)
              .having((e) => e.tokenInvalido, 'tokenInvalido', isFalse),
        ),
      );
    });

    test('un token caducado se marca como reintentable', () async {
      montarBackend(
        (_) => json200({
          'error': 'GOOGLE_TOKEN_INVALIDO',
          'message': 'Token de Google inválido.',
        }, status: 401),
      );

      await expectLater(
        ApiService.authGoogle(idToken: 'viejo'),
        throwsA(
          isA<GoogleAuthException>().having(
            (e) => e.tokenInvalido,
            'tokenInvalido',
            isTrue,
          ),
        ),
      );
    });

    test('una respuesta que no es JSON no revienta con un error de '
        'parseo', () async {
      ApiService.clienteDePrueba = MockClient(
        (_) async => http.Response('<html>502 Bad Gateway</html>', 502),
      );

      await expectLater(
        ApiService.authGoogle(idToken: 'tok'),
        throwsA(
          isA<GoogleAuthException>().having((e) => e.codigo, 'codigo', 'HTTP_502'),
        ),
      );
    });
  });

  group('GoogleSignInService', () {
    test('sin Client ID pegado, no se abre la pantalla de Google', () async {
      // Es lo que evita el error opaco: el SDK de Android devuelve
      // "canceled" cuando la configuración está incompleta, indistinguible
      // de que el usuario cerrara la ventana.
      expect(GoogleAuthConfig.estaConfigurado, isFalse);
      await expectLater(
        GoogleSignInService.obtenerIdToken(),
        throwsA(
          isA<GoogleSignInFallo>().having(
            (e) => e.codigo,
            'codigo',
            'SIN_CONFIGURAR',
          ),
        ),
      );
    });

    test('el doble de pruebas sustituye al SDK', () async {
      GoogleSignInService.obtenerIdTokenDePrueba = () async => 'tok-falso';
      expect(GoogleSignInService.estaConfigurado, isTrue);
      expect(await GoogleSignInService.obtenerIdToken(), 'tok-falso');
    });
  });

  group('GoogleSignInButton', () {
    testWidgets('muestra la etiqueta y responde al toque', (tester) async {
      var pulsado = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoogleSignInButton(onPressed: () => pulsado++),
          ),
        ),
      );

      expect(find.text('Continuar con Google'), findsOneWidget);
      expect(find.byType(GoogleLogo), findsOneWidget);

      await tester.tap(find.byType(GoogleSignInButton));
      expect(pulsado, 1);
    });

    testWidgets('sin onPressed queda deshabilitado', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: GoogleSignInButton(onPressed: null)),
        ),
      );

      final boton = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(boton.onPressed, isNull);
    });

    testWidgets('mientras carga no se puede volver a pulsar', (tester) async {
      var pulsado = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoogleSignInButton(
              cargando: true,
              onPressed: () => pulsado++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GoogleSignInButton));
      expect(pulsado, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
