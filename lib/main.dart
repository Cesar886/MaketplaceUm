import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'providers/accent_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/push_service.dart';

/// Llaves globales: el cierre de sesión por token inválido se dispara desde
/// la capa de red, que no tiene un BuildContext a mano.
final navigatorKey = GlobalKey<NavigatorState>();
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// El backend respondió `SESSION_INVALIDATED` en algún endpoint: el JWT
/// guardado se firmó con un secreto que ya no es el vigente y no hay forma de
/// recuperarlo. Se cierra sesión y se manda al login con un mensaje humano,
/// nunca con el error técnico.
Future<void> _cerrarSesionExpirada() async {
  final contexto = navigatorKey.currentContext;
  if (contexto == null) return;

  await contexto.read<AuthProvider>().logout();

  scaffoldMessengerKey.currentState?.showSnackBar(
    const SnackBar(content: Text('Tu sesión expiró, inicia sesión de nuevo')),
  );

  // Se vacía la pila entera: cualquier pantalla que quedara abajo pertenece a
  // la sesión que acaba de morir y volvería a fallar con 401.
  navigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ApiService.onSesionInvalidada = _cerrarSesionExpirada;

  // Inicializar Firebase (necesario antes de usar cualquier servicio Firebase)
  await Firebase.initializeApp();

  // Registrar handler de mensajes en background (top-level)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Inicializar Push Service (FCM)
  await PushService.instance.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AccentProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    // El swatch entra en el ThemeData completo, no en un provider que cada
    // widget tenga que mirar: al cambiarlo, MaterialApp reconstruye el tema y
    // la app entera se repinta por el mismo camino que el modo oscuro.
    final swatch = context.watch<AccentProvider>().swatch;
    return MaterialApp(
      title: 'Mercadito UM',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(swatch),
      darkTheme: AppTheme.dark(swatch),
      themeMode: theme.themeMode,
      // Los layouts de la app (tiles de tamaño fijo, chips, etc.) no están
      // diseñados para una escala de fuente del sistema sin límite: un ajuste
      // de accesibilidad de Android en "texto grande" puede desbordar texto
      // en widgets angostos. Se limita el escalado a un rango razonable en
      // vez de dejarlo sin tope.
      builder: (context, child) {
        final clampedScaler = MediaQuery.textScalerOf(
          context,
        ).clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: clampedScaler),
          child: child!,
        );
      },
      home: const SplashScreen(),
    );
  }
}
