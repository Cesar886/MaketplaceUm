// Reglas de validación del sistema de verificación de cuentas.
//
// Todo lo de este archivo es PURO: sin acceso a base de datos y sin peticiones
// de red, para poder testearlo aislado (ver verificacion.test.js). La misma
// convención que validation/sellerProfile.js: cada función devuelve `null` si
// el valor es válido, o un string con el mensaje que verá el usuario.

// Dominios de correo institucional aceptados. Configurable por entorno para
// cubrir el caso de que la universidad agregue subdominios nuevos, sin tener
// que redeployar código.
const DOMINIOS_ESTUDIANTE = (
  process.env.VERIFICATION_STUDENT_DOMAINS || 'alumno.um.edu.mx'
)
  .split(',')
  .map(d => d.trim().toLowerCase())
  .filter(Boolean);

// El correo institucional es <matrícula de 7 dígitos>@<dominio>,
// ej. 1220326@alumno.um.edu.mx. Los 7 dígitos SON la matrícula, así que el
// correo prueba ambos datos a la vez.
const LONGITUD_MATRICULA = 7;

const MIN_NOMBRE_NEGOCIO = 3;
const MAX_NOMBRE_NEGOCIO = 80;

// Hosts permitidos para el link de red social del negocio. Se comparan contra
// el `hostname` parseado por `new URL()`, nunca con includes/endsWith sobre el
// string completo: "instagram.com.phishing.net" contiene "instagram.com" pero
// es otro dominio.
//
// Quedan FUERA a propósito los acortadores genéricos (goo.gl, fb.me): un
// acortador redirige a cualquier destino, así que aceptarlo equivale a
// aceptar cualquier URL con apariencia de dominio confiable. goo.gl además
// está descontinuado por Google desde 2019.
//
// maps.app.goo.gl sí se acepta pese a ser un acortador: es el formato que
// genera "Compartir" en la app de Google Maps, o sea el caso de uso
// principal de un negocio, y solo apunta a fichas de Maps. El riesgo de
// redirección lo cubre linkCheck.js, que valida el destino en cada salto.
const HOSTS_RED_SOCIAL = new Set([
  'facebook.com',
  'www.facebook.com',
  'm.facebook.com',
  'web.facebook.com',
  'fb.com',
  'www.fb.com',
  'instagram.com',
  'www.instagram.com',
  'maps.google.com',
  'www.google.com',
  'google.com',
  'maps.app.goo.gl',
]);

// Hosts de Google que sirven para cualquier cosa: solo valen como link de
// negocio si la ruta es /maps.
const HOSTS_GOOGLE_GENERICOS = new Set(['google.com', 'www.google.com']);

/**
 * Separa un correo en { local, dominio } en minúsculas, o null si no tiene
 * exactamente un arroba.
 */
function partirCorreo(correo) {
  const partes = String(correo).trim().toLowerCase().split('@');
  if (partes.length !== 2 || !partes[0] || !partes[1]) return null;
  return { local: partes[0], dominio: partes[1] };
}

function validarCorreoInstitucional(correo) {
  if (typeof correo !== 'string' || !correo.trim()) {
    return 'Ingresa tu correo institucional';
  }
  const partes = partirCorreo(correo);
  if (!partes) return 'Correo electrónico inválido';

  // Comparación exacta de dominio (no endsWith): un dominio que solo termina
  // en el institucional, como alumno.um.edu.mx.attacker.com, no debe pasar.
  if (!DOMINIOS_ESTUDIANTE.includes(partes.dominio)) {
    return `Debes usar tu correo institucional (@${DOMINIOS_ESTUDIANTE[0]})`;
  }
  if (!new RegExp(`^\\d{${LONGITUD_MATRICULA}}$`).test(partes.local)) {
    return `Tu correo institucional debe empezar con tu matrícula de ${LONGITUD_MATRICULA} dígitos`;
  }
  return null;
}

/**
 * Devuelve la matrícula contenida en un correo institucional ya validado,
 * o null si el correo no tiene el formato esperado.
 */
function extraerMatriculaDeCorreo(correo) {
  const partes = partirCorreo(correo);
  if (!partes) return null;
  return new RegExp(`^\\d{${LONGITUD_MATRICULA}}$`).test(partes.local)
    ? partes.local
    : null;
}

/**
 * La matrícula no se valida contra ningún sistema externo, pero SÍ contra el
 * correo institucional: los 7 dígitos del correo ya son la matrícula, así que
 * una discrepancia solo puede ser un error de captura o un intento de
 * registrar la matrícula de alguien más.
 */
function validarMatricula(matricula, correoInstitucional) {
  if (typeof matricula !== 'string' || !matricula.trim()) {
    return 'Ingresa tu matrícula';
  }
  const esperada = extraerMatriculaDeCorreo(correoInstitucional);
  if (!esperada) return 'Correo institucional inválido';
  if (matricula.trim() !== esperada) {
    return 'La matrícula no coincide con tu correo institucional';
  }
  return null;
}

function validarNombreNegocio(nombre) {
  if (typeof nombre !== 'string') return 'Ingresa el nombre del negocio';
  const limpio = nombre.trim();
  if (limpio.length < MIN_NOMBRE_NEGOCIO) {
    return `El nombre del negocio debe tener al menos ${MIN_NOMBRE_NEGOCIO} caracteres`;
  }
  if (limpio.length > MAX_NOMBRE_NEGOCIO) {
    return `El nombre del negocio no puede superar ${MAX_NOMBRE_NEGOCIO} caracteres`;
  }
  return null;
}

function validarLinkRedSocial(link) {
  if (typeof link !== 'string' || !link.trim()) {
    return 'Agrega el link de tu página de Facebook, Instagram o Google Maps';
  }

  let url;
  try {
    url = new URL(link.trim());
  } catch {
    return 'El link no es una dirección web válida';
  }

  // Solo https: las tres plataformas permitidas lo sirven, y un link http
  // viaja en claro y puede ser reescrito por un atacante en la red.
  if (url.protocol !== 'https:') {
    return 'El link debe empezar con https://';
  }
  const host = url.hostname.toLowerCase();
  if (!HOSTS_RED_SOCIAL.has(host)) {
    return 'El link debe ser de Facebook, Instagram o Google Maps';
  }
  // google.com sirve para todo (búsqueda, correo, docs): solo cuenta como
  // link de negocio si apunta a Maps. Los hosts dedicados (maps.google.com,
  // maps.app.goo.gl) no necesitan este filtro.
  if (HOSTS_GOOGLE_GENERICOS.has(host) && !url.pathname.startsWith('/maps')) {
    return 'El link de Google debe ser la ficha de tu negocio en Maps';
  }
  return null;
}

/**
 * Normaliza un teléfono a E.164 asumiendo México cuando viene sin lada.
 * Devuelve { error, valor }: `error` es el mensaje para el usuario o null.
 */
function normalizarTelefono(telefono) {
  if (typeof telefono !== 'string' || !telefono.trim()) {
    return { error: 'Ingresa tu número de teléfono', valor: null };
  }

  const original = telefono.trim();
  // Se conservan solo dígitos y un "+" inicial; los separadores de captura
  // (espacios, guiones, paréntesis) se descartan.
  const soloValidos = original.replace(/[\s\-().]/g, '');
  if (!/^\+?\d+$/.test(soloValidos)) {
    return { error: 'El teléfono solo puede contener números', valor: null };
  }

  const digitos = soloValidos.replace(/^\+/, '');

  if (digitos.length === 10) {
    return { error: null, valor: `+52${digitos}` };
  }
  if (digitos.length === 12 && digitos.startsWith('52')) {
    return { error: null, valor: `+${digitos}` };
  }
  return {
    error: 'El teléfono debe tener 10 dígitos (ej. 4431234567)',
    valor: null,
  };
}

module.exports = {
  validarCorreoInstitucional,
  extraerMatriculaDeCorreo,
  validarMatricula,
  validarNombreNegocio,
  validarLinkRedSocial,
  normalizarTelefono,
  DOMINIOS_ESTUDIANTE,
  HOSTS_RED_SOCIAL,
};
