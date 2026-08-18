// Reglas de validación compartidas para el perfil de vendedor —
// usadas tanto en el registro inicial (POST /api/auth/register) como
// en la edición de perfil (PATCH /api/sellers/:id), para que ambos
// flujos acepten/rechacen exactamente los mismos valores.

const MIN_NAME_LENGTH = 2;
const MAX_NAME_LENGTH = 60;
const MAX_DESCRIPTION_LENGTH = 280;
const MIN_PASSWORD_LENGTH = 6;
const PHONE_REGEX = /^[0-9+\-\s()]{6,20}$/;
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function validateEmail(email) {
  if (typeof email !== 'string' || !EMAIL_REGEX.test(email.trim())) {
    return 'Correo electrónico inválido';
  }
  return null;
}

function validatePassword(password) {
  if (typeof password !== 'string' || password.length < MIN_PASSWORD_LENGTH) {
    return `La contraseña debe tener al menos ${MIN_PASSWORD_LENGTH} caracteres`;
  }
  return null;
}

function validateName(name) {
  if (typeof name !== 'string') return 'El nombre es requerido';
  const trimmed = name.trim();
  if (trimmed.length < MIN_NAME_LENGTH) {
    return `El nombre debe tener al menos ${MIN_NAME_LENGTH} caracteres`;
  }
  if (trimmed.length > MAX_NAME_LENGTH) {
    return `El nombre no puede superar ${MAX_NAME_LENGTH} caracteres`;
  }
  return null;
}

// El teléfono es opcional: solo se valida el formato si viene un valor no vacío.
function validatePhone(phone) {
  if (phone === undefined || phone === null || phone === '') return null;
  if (typeof phone !== 'string' || !PHONE_REGEX.test(phone.trim())) {
    return 'Teléfono inválido';
  }
  return null;
}

// Descripción corta del negocio: opcional, con límite de longitud.
function validateBusinessDescription(description) {
  if (description === undefined || description === null || description === '') return null;
  if (typeof description !== 'string' || description.trim().length > MAX_DESCRIPTION_LENGTH) {
    return `La descripción no puede superar ${MAX_DESCRIPTION_LENGTH} caracteres`;
  }
  return null;
}

// Rubro/categoría del negocio: opcional, debe ser uno de los ids de categoría existentes.
function validateBusinessCategory(categoryId, validCategoryIds) {
  if (categoryId === undefined || categoryId === null || categoryId === '') return null;
  if (typeof categoryId !== 'string' || !validCategoryIds.includes(categoryId)) {
    return 'Categoría de negocio inválida';
  }
  return null;
}

const HOURS_REGEX = /^([01]\d|2[0-3]):([0-5]\d)$/;
const VALID_HOURS_DAYS = ['0', '1', '2', '3', '4', '5', '6'];

// Horario de operación del negocio: opcional. Objeto keyed por día
// ('0'=Lunes .. '6'=Domingo), cada valor { open: 'HH:mm', close: 'HH:mm' }
// con open < close. Un día ausente del objeto significa "cerrado" ese día.
// Devuelve { error } si es inválido, o { value } con el objeto normalizado.
function validateBusinessHours(businessHours) {
  if (businessHours === undefined || businessHours === null) return { value: {} };

  let parsed = businessHours;
  if (typeof parsed === 'string') {
    if (parsed.trim() === '') return { value: {} };
    try {
      parsed = JSON.parse(parsed);
    } catch {
      return { error: 'businessHours debe ser un JSON válido' };
    }
  }

  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    return { error: 'businessHours debe ser un objeto' };
  }

  const normalized = {};
  for (const [day, range] of Object.entries(parsed)) {
    if (!VALID_HOURS_DAYS.includes(day)) {
      return { error: `Día inválido en businessHours: ${day}` };
    }
    if (typeof range !== 'object' || range === null) {
      return { error: `Horario inválido para el día ${day}` };
    }
    const { open, close } = range;
    if (typeof open !== 'string' || !HOURS_REGEX.test(open)) {
      return { error: `Hora de apertura inválida para el día ${day}` };
    }
    if (typeof close !== 'string' || !HOURS_REGEX.test(close)) {
      return { error: `Hora de cierre inválida para el día ${day}` };
    }
    if (close <= open) {
      return { error: `La hora de cierre debe ser posterior a la de apertura (día ${day})` };
    }
    normalized[day] = { open, close };
  }

  return { value: normalized };
}

// Ubicación geográfica opcional (perfil de negocio o publicación puntual).
// Debe venir como par completo (ambos presentes) o ambos ausentes/null —
// no se acepta lat sin lng ni viceversa. Devuelve { error } o
// { value: { lat, lng } } / { value: null } si no se envió ubicación.
function validateLocation(lat, lng) {
  const latMissing = lat === undefined || lat === null || lat === '';
  const lngMissing = lng === undefined || lng === null || lng === '';
  if (latMissing && lngMissing) return { value: null };
  if (latMissing || lngMissing) {
    return { error: 'Debes enviar latitud y longitud juntas' };
  }
  const parsedLat = Number(lat);
  const parsedLng = Number(lng);
  if (Number.isNaN(parsedLat) || parsedLat < -90 || parsedLat > 90) {
    return { error: 'Latitud inválida' };
  }
  if (Number.isNaN(parsedLng) || parsedLng < -180 || parsedLng > 180) {
    return { error: 'Longitud inválida' };
  }
  return { value: { lat: parsedLat, lng: parsedLng } };
}

// Catálogo fijo de métodos de pago — no crece con input de usuario, por eso
// se valida contra esta lista cerrada en vez de contra una tabla externa.
// 'transferencia' salió del catálogo: la app pasó a cobrar tarjeta de verdad
// y una transferencia bancaria manual no es algo que pueda registrar ni
// conciliar. Los vendedores que la tenían guardada se migraron en
// database.js (ver purgarMetodoDePago).
//
// 'tarjeta' es el único método que la app COBRA, no solo anuncia, así que
// tiene un requisito que los demás no: que el vendedor tenga cuenta de pagos
// conectada. Eso no se comprueba aquí — esta función es validación pura de
// catálogo, sin base de datos — sino en payments/methods.js, que es lo que
// aplican las rutas que guardan métodos.
const VALID_PAYMENT_METHODS = ['efectivo', 'tarjeta', 'paypal', 'cripto'];

// Métodos de pago aceptados: array de strings del catálogo fijo.
// - required=true (registro/perfil): al menos 1 método es obligatorio.
// - required=false (producto/wanted): opcional; [] o undefined/null se
//   normaliza a null, que en la app significa "hereda del perfil".
function validatePaymentMethods(paymentMethods, { required = false } = {}) {
  if (paymentMethods === undefined || paymentMethods === null) {
    if (required) return { error: 'Selecciona al menos un método de pago' };
    return { value: null };
  }
  let parsed = paymentMethods;
  if (typeof parsed === 'string') {
    try {
      parsed = JSON.parse(parsed);
    } catch {
      return { error: 'paymentMethods debe ser un JSON válido' };
    }
  }
  if (!Array.isArray(parsed)) {
    return { error: 'paymentMethods debe ser un arreglo' };
  }
  const unique = [...new Set(parsed)];
  for (const method of unique) {
    if (typeof method !== 'string' || !VALID_PAYMENT_METHODS.includes(method)) {
      return { error: `Método de pago inválido: ${method}` };
    }
  }
  if (required && unique.length === 0) {
    return { error: 'Selecciona al menos un método de pago' };
  }
  if (!required && unique.length === 0) {
    return { value: null };
  }
  return { value: unique };
}

// IDs de la paleta de acento. Es una lista cerrada y no un hex libre: el
// cliente resuelve cada ID a cuatro colores (relleno, foreground y la
// variante de línea de cada tema), todos verificados a contraste AA/3:1. Un
// hex arbitrario del cliente se saltaría esa verificación y podría dejar
// texto ilegible sobre el botón del perfil.
//
// Debe coincidir con AccentSwatch.opciones en lib/app_theme.dart.
const VALID_ACCENT_IDS = [
  'azul_niebla',
  'salvia',
  'durazno',
  'lavanda',
  'rosa_polvo',
  'celeste',
  'navy',
  'wine',
];

/// `null` es válido y significa "volver al color de marca".
function validateColorAcento(colorAcento) {
  if (colorAcento === undefined || colorAcento === null) return null;
  if (typeof colorAcento !== 'string' || !VALID_ACCENT_IDS.includes(colorAcento)) {
    return 'Theme inválido';
  }
  return null;
}

const MAX_SOCIAL_URL_LENGTH = 200;
const WHATSAPP_NUMBER_REGEX = /^\d{10,15}$/;

const SOCIAL_PLATFORMS = ['facebook', 'instagram', 'tiktok', 'twitter'];

const SOCIAL_URL_HOSTS = {
  facebook: new Set(['facebook.com', 'www.facebook.com', 'fb.com', 'm.facebook.com']),
  instagram: new Set(['instagram.com', 'www.instagram.com']),
  tiktok: new Set(['tiktok.com', 'www.tiktok.com']),
  twitter: new Set(['twitter.com', 'www.twitter.com', 'x.com', 'www.x.com']),
};

const SOCIAL_URL_LABELS = {
  facebook: 'Facebook',
  instagram: 'Instagram',
  tiktok: 'TikTok',
  twitter: 'X/Twitter',
};

// Link de red social del negocio: opcional. '' limpia el campo (vuelve a
// NULL). El hostname se compara por igualdad exacta contra una lista fija
// (no "contiene"): un "contiene" dejaría pasar
// https://facebook.com.evil.example/ porque la substring "facebook.com"
// aparece en un hostname que en realidad no es de Facebook.
function validateSocialUrl(platform, url) {
  if (url === undefined || url === null || url === '') return { value: null };
  if (typeof url !== 'string') {
    return { error: `El link de ${SOCIAL_URL_LABELS[platform]} no es válido` };
  }
  const trimmed = url.trim();
  if (trimmed.length > MAX_SOCIAL_URL_LENGTH) {
    return { error: `El link de ${SOCIAL_URL_LABELS[platform]} no puede superar ${MAX_SOCIAL_URL_LENGTH} caracteres` };
  }
  let parsed;
  try {
    parsed = new URL(trimmed);
  } catch {
    return { error: `El link de ${SOCIAL_URL_LABELS[platform]} no es una dirección web válida` };
  }
  if (parsed.protocol !== 'https:') {
    return { error: `El link de ${SOCIAL_URL_LABELS[platform]} debe empezar con https://` };
  }
  if (!SOCIAL_URL_HOSTS[platform].has(parsed.hostname.toLowerCase())) {
    return { error: `El link debe ser de ${SOCIAL_URL_LABELS[platform]}` };
  }
  return { value: trimmed };
}

// Número de WhatsApp del negocio: opcional. Solo dígitos con código de país
// incluido (ej. "5215512345678"), sin '+'/espacios/guiones. '' limpia el
// campo. Ver el design doc para por qué no se guarda la URL wa.me completa.
function validateWhatsappNumber(number) {
  if (number === undefined || number === null || number === '') return { value: null };
  if (typeof number !== 'string' || !WHATSAPP_NUMBER_REGEX.test(number.trim())) {
    return { error: 'El número de WhatsApp debe tener solo dígitos con código de país (10 a 15 dígitos)' };
  }
  return { value: number.trim() };
}

module.exports = {
  MIN_NAME_LENGTH,
  MAX_NAME_LENGTH,
  MAX_DESCRIPTION_LENGTH,
  MIN_PASSWORD_LENGTH,
  VALID_PAYMENT_METHODS,
  VALID_ACCENT_IDS,
  validateColorAcento,
  SOCIAL_PLATFORMS,
  validateName,
  validateEmail,
  validatePassword,
  validatePhone,
  validateBusinessDescription,
  validateBusinessCategory,
  validateBusinessHours,
  validateLocation,
  validatePaymentMethods,
  validateSocialUrl,
  validateWhatsappNumber,
};
