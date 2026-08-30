import 'package:easy_localization/easy_localization.dart';

/// Nombres de los días de la semana, YA TRADUCIDOS, indexados 0=lunes..6=domingo
/// (el mismo orden que usan `businessHours` y los chips de "días disponibles",
/// que es `DateTime.weekday - 1`).
///
/// Vive en funciones y no en una lista `const` de textos porque el idioma puede
/// cambiar con la pantalla ya montada: una lista const se quedaría congelada en
/// el idioma de arranque. Y vive aquí, en un solo sitio, porque la versión
/// anterior —cada widget con su propia lista de claves— dejó que un widget
/// pintara la clave cruda ('weekday_full.wed') sin que nadie lo notara: si la
/// traducción es parte de la función, no se puede olvidar el `.tr()`.
const _clavesDia = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// Abreviatura para espacios estrechos: 'Mié' / 'Wed'.
///
/// Es una traducción propia (`weekday.*`), no un recorte del nombre largo:
/// cortar a 3 caracteres da 'mié' en español pero 'Wed'/'Sat' en inglés solo
/// por casualidad, y en cuanto se añade otro idioma deja de funcionar.
String nombreCortoDia(int dia) => 'weekday.${_clavesDia[dia]}'.tr();

/// Nombre completo para usarlo solo, como etiqueta: 'Miércoles' / 'Wednesday'.
///
/// La traducción se guarda en minúscula (ver [nombreDiaEnFrase]) porque así es
/// como se escribe en español dentro de una frase; aquí se le pone la mayúscula
/// inicial, que en inglés no cambia nada porque ya viene capitalizada.
String nombreLargoDia(int dia) {
  final nombre = nombreDiaEnFrase(dia);
  if (nombre.isEmpty) return nombre;
  return nombre[0].toUpperCase() + nombre.substring(1);
}

/// Nombre completo tal cual está traducido, para incrustarlo dentro de una
/// frase ("Disponible el miércoles"): en español va en minúscula.
String nombreDiaEnFrase(int dia) => 'weekday_full.${_clavesDia[dia]}'.tr();
