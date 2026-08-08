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

// Dominios del personal de la universidad (empleados/docentes). Se validan
// aparte de los de alumno y son DISJUNTOS: 'alumno.um.edu.mx' nunca es igual
// a 'um.edu.mx', y la comparación es por igualdad exacta, así que un correo
// no puede pasar por los dos tipos a la vez.
const DOMINIOS_EMPLEADO = (
  process.env.VERIFICATION_STAFF_DOMAINS || 'um.edu.mx'
)
  .split(',')
  .map(d => d.trim().toLowerCase())
  .filter(Boolean);

// Los dos flujos que comparten el endpoint de OTP por correo. El cliente lo
// manda EXPLÍCITO (no se deduce del dominio) y el servidor comprueba que el
// correo corresponda al tipo declarado, para que nadie declare un tipo y
// mande el correo del otro.
const TIPOS_VERIFICACION = ['estudiante', 'empleado'];

// El correo institucional es <matrícula de 7 dígitos>@<dominio>,
// ej. 1220326@alumno.um.edu.mx. Los 7 dígitos SON la matrícula, así que el
// correo prueba ambos datos a la vez.
const LONGITUD_MATRICULA = 7;

// Usuario del personal: nombre.apellido, nombre.apellido.segundo, y variantes
// con dígitos (nombre.apellido2). Deliberadamente más tolerante que
// "exactamente dos partes": el formato real de la UM no está confirmado, y de
// equivocarse es preferible dejar pasar un correo raro (que igual tiene que
// recibir el OTP en ese buzón) que bloquear a un empleado legítimo.
const RE_USUARIO_EMPLEADO = /^[a-zA-Z]+(\.[a-zA-Z0-9]+)*$/;

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
 * Devuelve la matrícula contenida en un correo institucional, o null si el
 * correo no tiene el formato exacto <7 dígitos>@<dominio institucional>.
 *
 * Se devuelve como STRING, nunca como número: la matrícula puede empezar con
 * cero y `Number('0123456')` lo perdería.
 *
 * Repite la comprobación de dominio en lugar de confiar en que quien llama ya
 * validó: es la única fuente de la matrícula que se guarda en la base.
 */
function extraerMatriculaDeCorreo(correo) {
  const partes = partirCorreo(correo);
  if (!partes) return null;
  if (!DOMINIOS_ESTUDIANTE.includes(partes.dominio)) return null;
  return new RegExp(`^\\d{${LONGITUD_MATRICULA}}$`).test(partes.local)
    ? partes.local
    : null;
}

/** Valida el correo del personal (<usuario>@um.edu.mx). */
function validarCorreoEmpleado(correo) {
  if (typeof correo !== 'string' || !correo.trim()) {
    return 'Ingresa tu correo institucional';
  }
  const partes = partirCorreo(correo);
  if (!partes) return 'Correo electrónico inválido';

  if (!DOMINIOS_EMPLEADO.includes(partes.dominio)) {
    return `Debes usar tu correo institucional (@${DOMINIOS_EMPLEADO[0]})`;
  }
  if (!RE_USUARIO_EMPLEADO.test(partes.local)) {
    return 'Tu usuario institucional va como nombre.apellido';
  }
  return null;
}

/**
 * Valida el correo contra las reglas del tipo DECLARADO por el cliente.
 *
 * Es la comprobación que impide declarar `tipo: 'empleado'` mandando un
 * correo de alumno (o al revés) para saltarse la validación del otro flujo:
 * cada tipo solo acepta su propio dominio y su propio formato de usuario.
 */
function validarCorreoPorTipo(correo, tipo) {
  return tipo === 'empleado'
    ? validarCorreoEmpleado(correo)
    : validarCorreoInstitucional(correo);
}

/** Devuelve null si el tipo es uno de los dos soportados, o un mensaje. */
function validarTipoVerificacion(tipo) {
  return TIPOS_VERIFICACION.includes(tipo)
    ? null
    : 'Selecciona tu dominio institucional';
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
  validarCorreoEmpleado,
  validarCorreoPorTipo,
  validarTipoVerificacion,
  extraerMatriculaDeCorreo,
  validarNombreNegocio,
  validarLinkRedSocial,
  normalizarTelefono,
  DOMINIOS_ESTUDIANTE,
  DOMINIOS_EMPLEADO,
  TIPOS_VERIFICACION,
  HOSTS_RED_SOCIAL,
};
