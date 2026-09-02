import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/providers/accent_provider.dart';
import 'package:mercadito_um/providers/auth_provider.dart';
import 'package:mercadito_um/screens/profile_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'Mi perfil muestra Pendiente cuando la solicitud sigue en revisión',
    (tester) async {
      final auth = _AuthPerfilPendiente();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider(create: (_) => AccentProvider()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ProfileScreen()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Pendiente'), findsOneWidget);
      expect(
        find.text('Tu solicitud fue enviada y está en revisión.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      expect(find.text('Verifica tu cuenta'), findsNothing);
    },
  );
}

class _AuthPerfilPendiente extends AuthProvider {
  @override
  bool get isLoggedIn => true;

  @override
  Map<String, dynamic>? get currentUser => const {
    'id': 1,
    'name': 'Negocio de prueba',
    'user_type': 'negocio',
  };

  @override
  AccountType get accountType => AccountType.negocio;

  @override
  bool get puedeVerificarse => true;

  @override
  bool get isVerified => false;

  @override
  bool get solicitudManualPendiente => true;

  @override
  String get estadoVerificacion => 'pendiente';
}
