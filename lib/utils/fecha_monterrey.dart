/// Conversión de las fechas del backend a hora de Montemorelos/Monterrey.
///
/// El backend guarda todo en UTC (`datetime('now')` de SQLite), pero lo emite
/// como `YYYY-MM-DD HH:MM:SS`: sin la `T` y **sin sufijo de zona**. Dart
/// interpreta una cadena así como hora *local del dispositivo*, así que un
/// `DateTime.parse(...).toLocal()` directo es un no-op que termina pintando el
/// reloj UTC crudo (+6 h de más aquí).
///
/// La hora se fuerza a America/Monterrey y no a la del dispositivo: un usuario
/// con el teléfono en otro huso —o simplemente mal configurado— debe ver la
/// misma hora que el resto de la app.
library;

/// Offset fijo de America/Monterrey.
///
/// México eliminó el horario de verano con la Ley de Husos Horarios del 30 de
/// octubre de 2022. Nuevo León no está en la franja fronteriza exceptuada (esa
/// es Tijuana, Nuevo Laredo, Reynosa...), así que Montemorelos y Monterrey son
/// UTC−6 durante todo el año, sin cambios estacionales.
///
/// Por eso basta un offset constante y no hace falta arrastrar el paquete
/// `timezone` con su base de datos IANA completa: no hay ninguna regla que
/// consultar. Si algún día México reinstaurara el DST, este es el único punto
/// que habría que cambiar (y ahí sí tocaría la dependencia real).
const Duration kOffsetMonterrey = Duration(hours: -6);

/// Interpreta una fecha emitida por el backend y la devuelve como UTC.
///
/// Acepta tanto `2026-08-03 05:48:33` (lo que manda SQLite) como ISO-8601 ya
/// con zona. Cuando no viene designador de zona **se asume UTC**, que es lo
/// que realmente guarda la base, en vez del local que asumiría Dart.
DateTime? parseFechaBackend(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final normalizado = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
  final conZona =
      normalizado.endsWith('Z') ||
          RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(normalizado)
      ? normalizado
      : '${normalizado}Z';
  return DateTime.tryParse(conZona)?.toUtc();
}

/// La misma fecha, desplazada al huso de Monterrey.
///
/// El `DateTime` resultante está marcado como UTC a propósito: sus campos
/// (`hour`, `day`...) ya son los de Monterrey, y dejarlo así evita que un
/// `.toLocal()` posterior vuelva a moverlo. Es un valor para *mostrar*, no
/// para hacer aritmética contra `DateTime.now()`.
DateTime? enHoraMonterrey(String? raw) {
  final utc = parseFechaBackend(raw);
  if (utc == null) return null;
  return utc.add(kOffsetMonterrey);
}

/// Hora `HH:mm` de Monterrey para la burbuja del chat.
///
/// Devuelve cadena vacía si la fecha no se puede interpretar: la burbuja
/// simplemente no muestra hora, que es preferible a mostrar una equivocada.
String horaMonterrey(String? raw) {
  final dt = enHoraMonterrey(raw);
  if (dt == null) return '';
  final hora = dt.hour.toString().padLeft(2, '0');
  final minuto = dt.minute.toString().padLeft(2, '0');
  return '$hora:$minuto';
}
