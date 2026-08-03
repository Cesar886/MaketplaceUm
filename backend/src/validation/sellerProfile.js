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

module.exports = {
  MIN_NAME_LENGTH,
  MAX_NAME_LENGTH,
  MAX_DESCRIPTION_LENGTH,
  MIN_PASSWORD_LENGTH,
  validateName,
  validateEmail,
  validatePassword,
  validatePhone,
  validateBusinessDescription,
  validateBusinessCategory,
};
