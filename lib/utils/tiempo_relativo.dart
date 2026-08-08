/// Formatea una fecha como "hace 2 h" / "hace 3 días".
///
/// Escrito a mano en vez de agregar `timeago` al pubspec: la app necesita un
/// solo idioma y una sola forma corta, y una dependencia más es una más que
/// mantener, auditar y cargar en cada build por quince líneas de lógica.
///
/// [ahora] existe solo para los tests; en producción se omite.
String tiempoRelativo(DateTime fecha, {DateTime? ahora}) {
  final delta = (ahora ?? DateTime.now()).difference(fecha);

  // Un delta negativo significa reloj del dispositivo atrasado respecto al
  // servidor. "en 3 minutos" sobre un comentario ya publicado se lee como un
  // bug, así que se trata igual que recién llegado.
  if (delta.isNegative || delta.inSeconds < 60) return 'hace un momento';

  if (delta.inMinutes < 60) {
    return 'hace ${delta.inMinutes} min';
  }
  if (delta.inHours < 24) {
    return 'hace ${delta.inHours} h';
  }
  if (delta.inDays < 7) {
    final dias = delta.inDays;
    return 'hace $dias ${dias == 1 ? 'día' : 'días'}';
  }
  if (delta.inDays < 30) {
    final semanas = delta.inDays ~/ 7;
    return 'hace $semanas ${semanas == 1 ? 'semana' : 'semanas'}';
  }
  if (delta.inDays < 365) {
    // Aproximación con mes de 30 días: para "hace 4 meses" nadie cuenta los
    // días exactos, y evita arrastrar aritmética de calendario.
    final meses = delta.inDays ~/ 30;
    return 'hace $meses ${meses == 1 ? 'mes' : 'meses'}';
  }

  final anios = delta.inDays ~/ 365;
  return 'hace $anios ${anios == 1 ? 'año' : 'años'}';
}
