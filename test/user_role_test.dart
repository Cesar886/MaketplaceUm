import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/user_role.dart';

void main() {
  Seller construir({
    required String tipoCuenta,
    required bool verified,
    String major = '',
    String? carrera,
    String? tipoVerificacion,
    bool isGuest = false,
  }) {
    return Seller(
      name: 'Ana',
      avatarInitials: 'AN',
      major: major,
      rating: 0,
      reviews: 0,
      verified: verified,
      tipoCuenta: tipoCuenta,
      carrera: carrera,
      tipoVerificacion: tipoVerificacion,
      isGuest: isGuest,
    );
  }

  test('un alumno verificado muestra su carrera', () {
    final seller = construir(
      tipoCuenta: 'estudiante',
      verified: true,
      major: 'Estudiante',
      carrera: 'Ingeniería en Sistemas Computacionales',
      tipoVerificacion: 'estudiante',
    );
    expect(subtituloRol(seller), 'Ingeniería en Sistemas Computacionales');
  });

  test('el personal verificado muestra "Personal UM", no su carrera', () {
    final seller = construir(
      tipoCuenta: 'estudiante',
      verified: true,
      major: 'Estudiante',
      tipoVerificacion: 'empleado',
    );
    expect(subtituloRol(seller), 'Personal UM');
  });

  test('una cuenta de estudiante sin verificar omite la línea', () {
    final seller = construir(
      tipoCuenta: 'estudiante',
      verified: false,
      major: 'Estudiante',
    );
    expect(subtituloRol(seller), isNull);
  });

  test('un alumno verificado sin carrera guardada omite la línea', () {
    // Cuentas que se verificaron antes de que existiera el campo: se omite en
    // vez de caer al genérico 'Estudiante', que no distinguía nada.
    final seller = construir(
      tipoCuenta: 'estudiante',
      verified: true,
      major: 'Estudiante',
      tipoVerificacion: 'estudiante',
    );
    expect(subtituloRol(seller), isNull);
  });

  test('negocio y particular conservan su etiqueta de registro', () {
    expect(
      subtituloRol(
        construir(
          tipoCuenta: 'negocio',
          verified: true,
          major: 'Negocio • Establecimiento',
        ),
      ),
      'Negocio • Establecimiento',
    );
    // Sin verificar tampoco cambia: `major` no depende de la verificación.
    expect(
      subtituloRol(
        construir(
          tipoCuenta: 'particular',
          verified: false,
          major: 'Particular',
        ),
      ),
      'Particular',
    );
  });

  test('un major vacío omite la línea en vez de dejar un hueco', () {
    final seller = construir(tipoCuenta: 'particular', verified: false);
    expect(subtituloRol(seller), isNull);
  });

  test('un invitado se identifica como usuario sin cuenta', () {
    final seller = construir(
      tipoCuenta: 'particular',
      verified: false,
      major: 'Invitado',
      isGuest: true,
    );
    expect(subtituloRol(seller), 'Usuario sin cuenta');
  });
}
