const test = require('node:test');
const assert = require('node:assert');

const {
  validarCorreoInstitucional,
  validarNombreNegocio,
  validarLinkRedSocial,
  normalizarTelefono,
  extraerMatriculaDeCorreo,
} = require('./verificacion');

// ─── validarCorreoInstitucional ──────────────────────────────

test('acepta un correo institucional con 7 dígitos y dominio de alumno', () => {
  assert.strictEqual(validarCorreoInstitucional('1220326@alumno.um.edu.mx'), null);
});

test('acepta el correo institucional escrito en mayúsculas', () => {
  assert.strictEqual(validarCorreoInstitucional('1220326@ALUMNO.UM.EDU.MX'), null);
});

test('acepta el correo institucional con espacios alrededor', () => {
  assert.strictEqual(validarCorreoInstitucional('  1220326@alumno.um.edu.mx  '), null);
});

test('rechaza un correo de dominio ajeno a la universidad', () => {
  assert.match(validarCorreoInstitucional('1220326@gmail.com'), /institucional/i);
});

test('rechaza un correo con menos de 7 dígitos antes del arroba', () => {
  assert.ok(validarCorreoInstitucional('122032@alumno.um.edu.mx'));
});

test('rechaza un correo con más de 7 dígitos antes del arroba', () => {
  assert.ok(validarCorreoInstitucional('12203267@alumno.um.edu.mx'));
});

test('rechaza un correo cuya parte local tiene letras', () => {
  assert.ok(validarCorreoInstitucional('daniel@alumno.um.edu.mx'));
});

test('rechaza un dominio que solo termina en el dominio institucional', () => {
  // evil-alumno.um.edu.mx.attacker.com no debe pasar por un endsWith ingenuo
  assert.ok(validarCorreoInstitucional('1220326@alumno.um.edu.mx.attacker.com'));
});

test('rechaza un correo que no es string', () => {
  assert.ok(validarCorreoInstitucional(undefined));
  assert.ok(validarCorreoInstitucional(1220326));
});

// ─── extraerMatriculaDeCorreo ────────────────────────────────

test('extrae la matrícula de los 7 dígitos del correo institucional', () => {
  assert.strictEqual(extraerMatriculaDeCorreo('1220326@alumno.um.edu.mx'), '1220326');
});

test('extrae la matrícula normalizando mayúsculas y espacios', () => {
  assert.strictEqual(
    extraerMatriculaDeCorreo('  1220326@ALUMNO.UM.EDU.MX  '),
    '1220326',
  );
});

test('conserva la matrícula como string, con sus ceros a la izquierda', () => {
  assert.strictEqual(extraerMatriculaDeCorreo('0012345@alumno.um.edu.mx'), '0012345');
});

test('no extrae matrícula de un dominio ajeno ni de uno que solo termina igual', () => {
  assert.strictEqual(extraerMatriculaDeCorreo('1220326@gmail.com'), null);
  assert.strictEqual(
    extraerMatriculaDeCorreo('1220326@alumno.um.edu.mx.attacker.com'),
    null,
  );
});

test('no extrae matrícula si no son exactamente 7 dígitos', () => {
  assert.strictEqual(extraerMatriculaDeCorreo('122032@alumno.um.edu.mx'), null);
  assert.strictEqual(extraerMatriculaDeCorreo('12203267@alumno.um.edu.mx'), null);
  assert.strictEqual(extraerMatriculaDeCorreo('daniel@alumno.um.edu.mx'), null);
});

// ─── validarNombreNegocio ────────────────────────────────────

test('acepta un nombre de negocio de 3 caracteres', () => {
  assert.strictEqual(validarNombreNegocio('Ana'), null);
});

test('rechaza un nombre de negocio de 2 caracteres', () => {
  assert.match(validarNombreNegocio('Ax'), /3 caracteres/);
});

test('rechaza un nombre de negocio que solo tiene espacios', () => {
  assert.ok(validarNombreNegocio('      '));
});

test('rechaza un nombre de negocio de más de 80 caracteres', () => {
  assert.ok(validarNombreNegocio('a'.repeat(81)));
});

// ─── validarLinkRedSocial ────────────────────────────────────

test('acepta un perfil de Instagram', () => {
  assert.strictEqual(validarLinkRedSocial('https://www.instagram.com/tacos_um/'), null);
});

test('acepta una página de Facebook', () => {
  assert.strictEqual(validarLinkRedSocial('https://facebook.com/tacosum'), null);
});

test('acepta un link corto de Google Maps', () => {
  assert.strictEqual(validarLinkRedSocial('https://maps.app.goo.gl/aBcDeF123'), null);
});

test('acepta un lugar de Google Maps en google.com', () => {
  assert.strictEqual(
    validarLinkRedSocial('https://www.google.com/maps/place/Tacos+UM/@19.7,-101.1,17z'),
    null,
  );
});

test('rechaza un link de google.com que no es de Maps', () => {
  assert.ok(validarLinkRedSocial('https://www.google.com/search?q=tacos'));
});

test('rechaza un dominio que solo contiene el nombre de la red social', () => {
  assert.ok(validarLinkRedSocial('https://instagram.com.phishing.net/tacos'));
});

test('rechaza un dominio fuera de la whitelist', () => {
  assert.match(validarLinkRedSocial('https://mi-negocio.com'), /Facebook|Instagram|Maps/i);
});

test('rechaza un esquema que no es https', () => {
  assert.ok(validarLinkRedSocial('javascript:alert(1)'));
  assert.ok(validarLinkRedSocial('file:///etc/passwd'));
});

test('rechaza http sin cifrar aunque el dominio sea correcto', () => {
  // Un link http:// viaja en claro y además abre la puerta a que un atacante
  // en la red lo reescriba; las tres plataformas permitidas sirven https.
  assert.match(validarLinkRedSocial('http://www.instagram.com/tacos_um/'), /https/i);
});

test('rechaza el acortador genérico goo.gl', () => {
  // goo.gl redirige a CUALQUIER destino (Google lo descontinuó en 2019), así
  // que aceptarlo equivale a aceptar cualquier URL disfrazada de Google.
  assert.ok(validarLinkRedSocial('https://goo.gl/abc123'));
});

test('rechaza el acortador fb.me', () => {
  assert.ok(validarLinkRedSocial('https://fb.me/abc123'));
});

test('sigue aceptando el link corto que genera la app de Google Maps', () => {
  // maps.app.goo.gl es el formato que produce "Compartir" en Maps: quitarlo
  // rompería el caso de uso principal de los negocios. Es seguro porque cada
  // salto de la redirección se valida contra destinos privados en linkCheck.
  assert.strictEqual(validarLinkRedSocial('https://maps.app.goo.gl/aBcDeF123'), null);
});

test('rechaza una URL mal formada', () => {
  assert.ok(validarLinkRedSocial('no es una url'));
});

test('rechaza un link vacío porque es obligatorio', () => {
  assert.ok(validarLinkRedSocial(''));
  assert.ok(validarLinkRedSocial(undefined));
});

// ─── normalizarTelefono ──────────────────────────────────────

test('normaliza un teléfono mexicano de 10 dígitos a E.164', () => {
  assert.deepStrictEqual(normalizarTelefono('4431234567'), {
    error: null,
    valor: '+524431234567',
  });
});

test('normaliza un teléfono con guiones, espacios y paréntesis', () => {
  assert.deepStrictEqual(normalizarTelefono('(443) 123-4567'), {
    error: null,
    valor: '+524431234567',
  });
});

test('conserva un teléfono que ya viene en formato E.164', () => {
  assert.deepStrictEqual(normalizarTelefono('+524431234567'), {
    error: null,
    valor: '+524431234567',
  });
});

test('normaliza un teléfono con lada 52 sin el signo de más', () => {
  assert.deepStrictEqual(normalizarTelefono('524431234567'), {
    error: null,
    valor: '+524431234567',
  });
});

test('rechaza un teléfono de menos de 10 dígitos', () => {
  assert.ok(normalizarTelefono('44312345').error);
});

test('rechaza un teléfono con letras', () => {
  assert.ok(normalizarTelefono('443ABC4567').error);
});

test('rechaza un teléfono vacío', () => {
  assert.ok(normalizarTelefono('').error);
  assert.ok(normalizarTelefono(undefined).error);
});
