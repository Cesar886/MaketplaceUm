import 'dart:async';

import 'helpers/localizacion_de_prueba.dart';

/// Configuración que `flutter test` aplica a TODOS los archivos de `test/`.
///
/// Existe por el i18n: casi cualquier widget de la app llama a `.tr()`, y sin
/// un diccionario cargado eso devuelve la clave cruda ('status.sold_out' en
/// vez de 'Agotado'), rompiendo cualquier `expect` sobre texto.
///
/// Cargarlo aquí en vez de en cada archivo evita que un test nuevo falle por
/// haber olvidado un `setUpAll`, que es un fallo confuso: el widget se pinta,
/// pero con textos que nadie escribió.
///
/// Los tests que además necesiten `context.locale` (o probar el cambio de
/// idioma) tienen que envolver su árbol con `appDePrueba` de
/// `helpers/localizacion_de_prueba.dart`; para el resto, esto basta.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await inicializarTraducciones();
  await testMain();
}
