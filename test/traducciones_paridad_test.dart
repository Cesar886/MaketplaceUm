import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guarda de paridad entre `es.json` y `en.json`.
///
/// easy_localization resuelve las claves en runtime: una clave que existe en
/// español pero no en inglés no rompe la compilación, solo cae al fallback y
/// muestra texto en español dentro de la app en inglés. Este test convierte
/// ese olvido en un test rojo, que es la única red que tenemos.
void main() {
  Map<String, dynamic> cargar(String idioma) {
    final archivo = File('assets/translations/$idioma.json');
    expect(archivo.existsSync(), isTrue, reason: 'falta $idioma.json');
    return jsonDecode(archivo.readAsStringSync()) as Map<String, dynamic>;
  }

  /// Aplana `{"a": {"b": "x"}}` a `{"a.b": "x"}` para poder comparar los dos
  /// archivos como conjuntos de claves, sin recorrer el árbol a mano.
  Map<String, String> aplanar(
    Map<String, dynamic> mapa, [
    String prefijo = '',
  ]) {
    final salida = <String, String>{};
    mapa.forEach((clave, valor) {
      final ruta = prefijo.isEmpty ? clave : '$prefijo.$clave';
      if (valor is Map<String, dynamic>) {
        salida.addAll(aplanar(valor, ruta));
      } else {
        salida[ruta] = '$valor';
      }
    });
    return salida;
  }

  late Map<String, String> es;
  late Map<String, String> en;

  setUpAll(() {
    es = aplanar(cargar('es'));
    en = aplanar(cargar('en'));
  });

  test('en.json tiene todas las claves de es.json', () {
    final faltantes = es.keys.where((k) => !en.containsKey(k)).toList()..sort();
    expect(
      faltantes,
      isEmpty,
      reason: 'Claves sin traducir al inglés:\n${faltantes.join('\n')}',
    );
  });

  test('es.json tiene todas las claves de en.json', () {
    final sobrantes = en.keys.where((k) => !es.containsKey(k)).toList()..sort();
    expect(
      sobrantes,
      isEmpty,
      reason:
          'Claves en inglés que ya no existen en español:\n'
          '${sobrantes.join('\n')}',
    );
  });

  test('ninguna traducción quedó vacía', () {
    for (final mapa in {'es': es, 'en': en}.entries) {
      final vacias = mapa.value.entries
          .where((e) => e.value.trim().isEmpty)
          .map((e) => e.key)
          .toList();
      expect(vacias, isEmpty, reason: 'Claves vacías en ${mapa.key}.json');
    }
  });

  test('los parámetros de interpolación coinciden entre idiomas', () {
    // Un `{count}` que se pierde en la traducción no falla: simplemente el
    // número nunca aparece en pantalla. Comparar los placeholders de cada
    // par de textos lo detecta.
    final patron = RegExp(r'\{(\w*)\}');
    final desalineadas = <String>[];

    for (final clave in es.keys) {
      if (!en.containsKey(clave)) continue;
      final pEs = patron.allMatches(es[clave]!).map((m) => m[1]).toSet();
      final pEn = patron.allMatches(en[clave]!).map((m) => m[1]).toSet();
      if (pEs.length != pEn.length || !pEs.containsAll(pEn)) {
        desalineadas.add('$clave — es:$pEs en:$pEn');
      }
    }

    expect(desalineadas, isEmpty, reason: desalineadas.join('\n'));
  });
}
