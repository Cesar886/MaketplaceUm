// Tests de la política de Google Sign-In: qué audiencias se aceptan y qué
// dominios de correo se dejan pasar.
//
// No se prueba aquí la criptografía de `verifyIdToken` (eso lo hace
// google-auth-library, y firmar un JWT con las claves de Google desde un
// test no es posible): se prueba TODO lo que decide este proyecto alrededor
// de ella, que es donde pueden estar nuestros errores.

const test = require('node:test');
const assert = require('node:assert');

const googleAuth = require('./googleAuth');

function conEntorno(vars, fn) {
  const previo = {};
  for (const [k, v] of Object.entries(vars)) {
    previo[k] = process.env[k];
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  try {
    return fn();
  } finally {
    for (const [k, v] of Object.entries(previo)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  }
}

test('sin GOOGLE_CLIENT_IDS el login con Google se reporta como no configurado', () => {
  conEntorno({ GOOGLE_CLIENT_IDS: undefined }, () => {
    assert.equal(googleAuth.estaConfigurado(), false);
  });
});

test('GOOGLE_CLIENT_IDS acepta varias audiencias separadas por coma', () => {
  conEntorno({ GOOGLE_CLIENT_IDS: ' a.apps.googleusercontent.com , b.apps.googleusercontent.com ' }, () => {
    assert.equal(googleAuth.estaConfigurado(), true);
    assert.deepEqual(googleAuth.audiencias(), [
      'a.apps.googleusercontent.com',
      'b.apps.googleusercontent.com',
    ]);
  });
});

test('verificarIdToken falla con 503 mientras falten las credenciales', async () => {
  await conEntorno({ GOOGLE_CLIENT_IDS: undefined }, async () => {
    await assert.rejects(
      () => googleAuth.verificarIdToken('lo-que-sea'),
      (err) => err.codigo === 'GOOGLE_NO_CONFIGURADO' && err.status === 503,
    );
  });
});

// ─── Filtro de dominio (apagado por defecto) ─────────────────

test('sin GOOGLE_ALLOWED_DOMAINS se acepta cualquier dominio', () => {
  conEntorno({ GOOGLE_ALLOWED_DOMAINS: undefined }, () => {
    assert.equal(googleAuth.dominioPermitido('quien.sea@gmail.com'), true);
  });
});

test('GOOGLE_ALLOWED_DOMAINS vacío tampoco restringe', () => {
  conEntorno({ GOOGLE_ALLOWED_DOMAINS: '   ' }, () => {
    assert.equal(googleAuth.dominioPermitido('quien.sea@gmail.com'), true);
  });
});

test('con la lista puesta, un correo de fuera queda fuera', () => {
  conEntorno({ GOOGLE_ALLOWED_DOMAINS: 'alumno.um.edu.mx,um.edu.mx' }, () => {
    assert.equal(googleAuth.dominioPermitido('1220326@alumno.um.edu.mx'), true);
    assert.equal(googleAuth.dominioPermitido('juan.perez@um.edu.mx'), true);
    assert.equal(googleAuth.dominioPermitido('otro@gmail.com'), false);
  });
});

test('el dominio se compara sin importar mayúsculas', () => {
  conEntorno({ GOOGLE_ALLOWED_DOMAINS: 'Alumno.UM.edu.MX' }, () => {
    assert.equal(googleAuth.dominioPermitido('1220326@ALUMNO.um.edu.mx'), true);
  });
});

// Un subdominio no es el dominio: 'um.edu.mx.attacker.com' termina en
// 'attacker.com', y compararlo con endsWith lo dejaría pasar.
test('un dominio que solo TERMINA parecido no pasa el filtro', () => {
  conEntorno({ GOOGLE_ALLOWED_DOMAINS: 'um.edu.mx' }, () => {
    assert.equal(googleAuth.dominioPermitido('yo@evil-um.edu.mx'), false);
    assert.equal(googleAuth.dominioPermitido('yo@um.edu.mx.evil.com'), false);
  });
});

test('un correo sin arroba nunca pasa el filtro', () => {
  conEntorno({ GOOGLE_ALLOWED_DOMAINS: 'um.edu.mx' }, () => {
    assert.equal(googleAuth.dominioPermitido('sinarroba'), false);
    assert.equal(googleAuth.dominioPermitido(''), false);
    assert.equal(googleAuth.dominioPermitido(null), false);
  });
});
