import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final archivos = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((archivo) => archivo.path.endsWith('.dart'))
      .toList();

  test('las pestañas principales solo se montan dentro de MainShell', () {
    const pantallas = {
      'HomeScreen': 'lib/screens/home_screen.dart',
      'OffersScreen': 'lib/screens/offers_screen.dart',
      'CartScreen': 'lib/screens/cart_screen.dart',
      'ChatListScreen': 'lib/screens/chat_list_screen.dart',
      'ProfileScreen': 'lib/screens/profile_screen.dart',
    };

    for (final entrada in pantallas.entries) {
      final constructor = RegExp('\\b${entrada.key}\\s*\\(');
      for (final archivo in archivos) {
        if (archivo.path == entrada.value ||
            archivo.path == 'lib/screens/main_shell.dart') {
          continue;
        }
        expect(
          constructor.hasMatch(archivo.readAsStringSync()),
          isFalse,
          reason:
              '${entrada.key} es una pestaña interna: debe abrirse mediante '
              'MainShell, no montarse directamente desde ${archivo.path}.',
        );
      }
    }
  });

  test('solo main.dart puede vaciar por completo la pila de navegación', () {
    for (final archivo in archivos) {
      if (archivo.path == 'lib/main.dart') continue;
      expect(
        archivo.readAsStringSync().contains('pushAndRemoveUntil'),
        isFalse,
        reason:
            '${archivo.path} debe usar abrirInicio/abrirLogin; centralizar la '
            'limpieza evita dejar una pantalla interna como ruta raíz.',
      );
    }
  });
}
