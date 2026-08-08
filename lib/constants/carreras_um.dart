/// Lista fija y oficial de carreras de la Universidad de Montemorelos.
///
/// Es SOLO declarativa: el usuario elige una de esta lista al verificar su
/// cuenta de estudiante, sin que exista ninguna verificación cruzada contra
/// un padrón oficial (esa relación no es derivable desde la matrícula ni el
/// correo). Debe coincidir EXACTAMENTE con `backend/src/validation/carreras.js`
/// — el backend nunca confía en que el frontend ya validó y revalida contra
/// su propia copia de esta misma lista.
const List<String> carrerasUM = [
  // Artes y Comunicación
  'Licenciatura en Arquitectura',
  'Licenciatura en Artes Visuales',
  'Licenciatura en Comunicación y Medios',
  'Licenciatura en Diseño de Comunicación Visual',
  'Maestría en Dirección de Comunicación',
  // Ciencias de la Salud
  'Licenciatura en Cirujano Dentista',
  'Licenciatura en Enfermería',
  'Licenciatura en Médico Cirujano',
  'Licenciatura en Nutrición',
  'Licenciatura en Químico Clínico Biólogo',
  'Licenciatura en Terapia Física y Rehabilitación',
  'Técnico en Tecnología Dental',
  'Especialidad en Odontología',
  'Especialidad en Oftalmología',
  'Maestría en Salud Pública',
  // Educación
  'Licenciatura en Educación Preescolar',
  'Licenciatura en Educación Primaria',
  'Licenciatura en Enseñanza del Lenguaje y la Comunicación',
  'Licenciatura en Enseñanza de las Matemáticas',
  'Licenciatura en Enseñanza de las Ciencias Naturales',
  'Licenciatura en Enseñanza de las Ciencias Sociales',
  'Licenciatura en Enseñanza del Inglés',
  'Especialidad en Docencia',
  'Especialidad en Diseño e Innovación Curricular',
  'Especialidad en Educación en Línea',
  'Especialidad en Aplicación de Recursos Tecnológicos en el Proceso Educativo',
  'Maestría en Educación, Acentuación en Gestión Docente',
  'Maestría en Educación, Acentuación en Gestión Curricular',
  'Maestría en Educación, Acentuación en Tecnología Educativa',
  'Doctorado en Educación',
  // Empresariales y Jurídicas
  'Licenciatura en Administración y Negocios Internacionales',
  'Licenciatura en Contaduría Pública',
  'Licenciatura en Derecho',
  'Especialidad en Finanzas',
  'Especialidad en Mercadotecnia',
  'Maestría en Mercadotecnia',
  'Doctorado en Administración de Negocios',
  // Ingeniería y Tecnología
  'Ingeniería en Electrónica y Telecomunicaciones',
  'Ingeniería en Gestión de Tecnologías de la Información',
  'Ingeniería en Sistemas Computacionales',
  'Ingeniería Industrial y de Sistemas',
  'Maestría en Redes y Seguridad',
  // Música
  'Licenciatura en Música',
  // Psicología
  'Licenciatura en Psicología Educativa',
  'Licenciatura en Psicología Clínica',
  // Teología
  'Licenciatura en Teología',
];

const Map<String, String> _acentosCarrera = {
  'á': 'a',
  'é': 'e',
  'í': 'i',
  'ó': 'o',
  'ú': 'u',
  'ñ': 'n',
  'ü': 'u',
};

/// Quita acentos y pasa a minúsculas para que la búsqueda del autocomplete
/// no distinga mayúsculas/acentos (p. ej. "ing sistemas" encuentra
/// "Ingeniería en Sistemas Computacionales").
String normalizarBusquedaCarrera(String texto) {
  final buffer = StringBuffer();
  for (final char in texto.toLowerCase().split('')) {
    buffer.write(_acentosCarrera[char] ?? char);
  }
  return buffer.toString();
}
