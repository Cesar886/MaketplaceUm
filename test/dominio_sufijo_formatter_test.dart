import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/constants/dominios_um.dart';

/// Simula lo que hace el campo de texto: pasa del valor anterior al nuevo
/// tecleando/borrando, y devuelve lo que queda tras el formatter.
TextEditingValue _teclear(TextEditingValue anterior, TextEditingValue nuevo) =>
    const DominioSufijoFormatter().formatEditUpdate(anterior, nuevo);

TextEditingValue _valor(String texto, [int? cursor]) => TextEditingValue(
  text: texto,
  selection: TextSelection.collapsed(offset: cursor ?? texto.length),
);

void main() {
  group('DominioSufijoFormatter', () {
    test('no autocompleta nada mientras la parte local es ambigua', () {
      final r = _teclear(_valor('12'), _valor('12'));
      expect(r.text, '12');
    });

    test('autocompleta el dominio de alumno en el 3er carácter', () {
      final r = _teclear(_valor('12'), _valor('122'));
      expect(r.text, '122@alumno.um.edu.mx');
      expect(r.selection.baseOffset, 3, reason: 'el cursor queda antes del @');
    });

    test('autocompleta el dominio de personal si el 3er carácter es letra', () {
      final r = _teclear(_valor('ce'), _valor('ces'));
      expect(r.text, 'ces@um.edu.mx');
      expect(r.selection.baseOffset, 3);
    });

    test('seguir escribiendo crece solo la parte local', () {
      final r = _teclear(
        _valor('122@alumno.um.edu.mx', 3),
        _valor('1220@alumno.um.edu.mx', 4),
      );
      expect(r.text, '1220@alumno.um.edu.mx');
      expect(r.selection.baseOffset, 4);
    });

    test('la matrícula completa queda como el correo esperado', () {
      var v = _valor('');
      for (final c in '1220326'.split('')) {
        final local = DominioSufijoFormatter.parteLocal(v.text);
        v = _teclear(v, _valor('$local$c${v.text.substring(local.length)}',
            local.length + 1));
      }
      expect(v.text, '1220326@alumno.um.edu.mx');
    });

    test('borrar hasta ser ambiguo quita el dominio', () {
      final r = _teclear(
        _valor('122@alumno.um.edu.mx', 3),
        _valor('12@alumno.um.edu.mx', 2),
      );
      expect(r.text, '12');
      expect(r.selection.baseOffset, 2);
    });

    test('borrar toda la parte local deja el campo vacío', () {
      final r = _teclear(_valor('122@alumno.um.edu.mx', 3), _valor('', 0));
      expect(r.text, '');
    });

    test('Supr sobre el arroba no duplica ni rompe el dominio', () {
      // Borrado hacia adelante: desaparece el '@' y el dominio queda pegado.
      final r = _teclear(
        _valor('1220326@alumno.um.edu.mx', 7),
        _valor('1220326alumno.um.edu.mx', 7),
      );
      expect(r.text, '1220326@alumno.um.edu.mx');
      expect(r.selection.baseOffset, 7);
    });

    test('un arroba tecleado por el usuario no crea un segundo dominio', () {
      final r = _teclear(
        _valor('1220326@alumno.um.edu.mx', 7),
        _valor('1220326@@alumno.um.edu.mx', 8),
      );
      expect(r.text, '1220326@alumno.um.edu.mx');
      expect(r.selection.baseOffset, 7, reason: 'el cursor no entra al dominio');
    });

    test('cambiar de numérico a alfabético cambia el dominio', () {
      final r = _teclear(
        _valor('12a@um.edu.mx', 3),
        _valor('12a4@um.edu.mx', 4),
      );
      // El primer carácter decisivo sigue siendo la letra: no cambia.
      expect(r.text, '12a4@um.edu.mx');
    });

    test('pegar un correo completo respeta el dominio detectado', () {
      final r = _teclear(_valor(''), _valor('1220326@alumno.um.edu.mx'));
      expect(r.text, '1220326@alumno.um.edu.mx');
      expect(r.selection.baseOffset, 7);
    });

    test('la selección nunca abarca el dominio', () {
      final r = const DominioSufijoFormatter().formatEditUpdate(
        _valor('1220326@alumno.um.edu.mx', 7),
        const TextEditingValue(
          text: '1220326@alumno.um.edu.mx',
          selection: TextSelection(baseOffset: 0, extentOffset: 24),
        ),
      );
      expect(r.selection.extentOffset, 7);
    });

    test('parteLocal corta en el primer arroba', () {
      expect(DominioSufijoFormatter.parteLocal('a.b@um.edu.mx'), 'a.b');
      expect(DominioSufijoFormatter.parteLocal('12'), '12');
      expect(DominioSufijoFormatter.parteLocal(''), '');
    });
  });
}
