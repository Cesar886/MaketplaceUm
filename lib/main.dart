import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'services/push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    return MaterialApp(
      title: 'Mercadito UM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: theme.themeMode,
      home: const SplashScreen(),
    );
  }
}
