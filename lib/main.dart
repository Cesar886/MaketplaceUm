import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'config/locales.dart';
import 'providers/accent_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/deep_link_service.dart';
import 'services/presence_service.dart';
import 'services/push_service.dart';

/// Llaves globales: el cierre de sesión por token inválido se dispara desde
/// la capa de red, que no tiene un BuildContext a mano.
final navigatorKey = GlobalKey<NavigatorState>();
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// [MainShell] se abre siempre como ruta propia (nunca embebido en otro
/// widget), así que las pantallas empujadas ENCIMA de él —como
/// `MyListingsScreen`— son rutas hermanas en el mismo Navigator, no
/// descendientes en el árbol de widgets: `findAncestorStateOfType` no puede
/// alcanzar su State desde ahí. Esta llave sí, sin importar desde qué ruta se
/// pida.
final mainShellKey = GlobalKey<MainShellState>();

/// La renovación persistente fue rechazada: la sesión fue revocada o ya no
/// existe. Un JWT vencido o firmado con una clave anterior se renueva antes
/// de llegar aquí; solo este rechazo definitivo manda de nuevo al login.
Future<void> _cerrarSesionExpirada() async {
  final contexto = navigatorKey.currentContext;
  if (contexto == null) return;

  await contexto.read<AuthProvider>().logout();

  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(content: Text('errors.session_expired'.tr())),
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

  // easy_localization guarda el idioma elegido en su propio almacenamiento
  // local y lo restaura aquí, antes de que se pinte nada: sin esto la app
  // arrancaría en español y saltaría al idioma guardado a media carga.
  await EasyLocalization.ensureInitialized();

  ApiService.onSesionInvalidada = _cerrarSesionExpirada;

  // Inicializar Firebase (necesario antes de usar cualquier servicio Firebase)
  await Firebase.initializeApp();

  // Registrar handler de mensajes en background (top-level)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Inicializar Push Service (FCM)
  await PushService.instance.initialize();

  // Escuchar los links de mercaditoum.site ANTES de runApp: en un arranque en
  // frío, el link con el que se abrió la app ya está esperando, y suscribirse
  // después podría perderlo. El servicio lo guarda hasta que SplashScreen
  // avise que ya hay dónde navegar.
  DeepLinkService.instance.iniciar();

  runApp(
    // EasyLocalization envuelve a los providers, no al revés: al cambiar de
    // idioma reconstruye a sus hijos, y si quedara por dentro se perdería el
    // estado de sesión en cada cambio.
    EasyLocalization(
      supportedLocales: AppLocales.localesSoportados,
      path: AppLocales.rutaTraducciones,
      fallbackLocale: AppLocales.fallback,
      startLocale: AppLocales.es,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AccentProvider()),
          // Vive arriba del todo porque el mismo estado se pinta en la lista
          // de chats y en el perfil del vendedor: con una instancia por
          // pantalla las dos se contradirían.
          ChangeNotifierProvider(create: (_) => PresenceService()),
        ],
        child: const MyApp(),
      ),
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
      title: 'Marketplace UM',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      // Idioma: lo resuelve EasyLocalization a partir del guardado en disco.
      // `localizationsDelegates` también trae las traducciones de los widgets
      // de Material (el "OK"/"Cancel" de los date pickers, etc.).
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
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
