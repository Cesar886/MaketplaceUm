const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');

const { verificarLink } = require('./linkCheck');

// El servidor de pruebas corre en 127.0.0.1, que la defensa anti-SSRF
// rechaza por diseño. Los tests de comportamiento HTTP inyectan un guardián
// permisivo; los tests de SSRF usan guardianes que sí discriminan, y el
// guardián real tiene sus propios tests en redDestino.test.js.
const permiteTodo = async () => true;

/**
 * Levanta un servidor HTTP real en un puerto libre y lo apaga al terminar.
 * Se prefiere sobre mockear fetch: lo que se está probando es justamente el
 * comportamiento frente a respuestas HTTP reales (status, redirecciones,
 * timeouts), y un mock de fetch solo probaría el mock.
 */
async function conServidor(handler, prueba) {
  const server = http.createServer(handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}/negocio`;
  try {
    await prueba(url);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

test('acepta un link que responde 200', async () => {
  await conServidor(
    (_req, res) => res.writeHead(200).end(),
    async url => {
      assert.deepStrictEqual(await verificarLink(url, { comprobarDestino: permiteTodo }), { ok: true, motivo: null });
    },
  );
});

test('acepta un link que responde 403 por bloqueo antibot', async () => {
  // Instagram y Facebook responden 403 (o 302 a login) a peticiones
  // automáticas aunque el perfil exista: rechazarlos sería rechazar
  // negocios legítimos.
  await conServidor(
    (_req, res) => res.writeHead(403).end(),
    async url => {
      assert.strictEqual((await verificarLink(url, { comprobarDestino: permiteTodo })).ok, true);
    },
  );
});

test('acepta un link que responde 999 como LinkedIn/Instagram al bloquear', async () => {
  await conServidor(
    (_req, res) => res.writeHead(999).end(),
    async url => {
      assert.strictEqual((await verificarLink(url, { comprobarDestino: permiteTodo })).ok, true);
    },
  );
});

test('acepta un link que redirige a login', async () => {
  await conServidor(
    (req, res) => {
      if (req.url === '/negocio') {
        return res.writeHead(302, { Location: '/login' }).end();
      }
      res.writeHead(200).end();
    },
    async url => {
      assert.strictEqual((await verificarLink(url, { comprobarDestino: permiteTodo })).ok, true);
    },
  );
});

test('rechaza un link que responde 404', async () => {
  await conServidor(
    (_req, res) => res.writeHead(404).end(),
    async url => {
      const resultado = await verificarLink(url, { comprobarDestino: permiteTodo });
      assert.strictEqual(resultado.ok, false);
      assert.match(resultado.motivo, /no existe|no encontr/i);
    },
  );
});

test('rechaza un link que responde 500', async () => {
  await conServidor(
    (_req, res) => res.writeHead(500).end(),
    async url => {
      assert.strictEqual((await verificarLink(url, { comprobarDestino: permiteTodo })).ok, false);
    },
  );
});

test('reintenta con GET cuando el servidor no permite HEAD', async () => {
  await conServidor(
    (req, res) => {
      if (req.method === 'HEAD') return res.writeHead(405).end();
      res.writeHead(200).end('ok');
    },
    async url => {
      assert.strictEqual((await verificarLink(url, { comprobarDestino: permiteTodo })).ok, true);
    },
  );
});

test('rechaza un link cuyo host no resuelve', async () => {
  const resultado = await verificarLink(
    'https://este-dominio-no-existe-mercadito-um-12345.com',
    { comprobarDestino: permiteTodo },
  );
  assert.strictEqual(resultado.ok, false);
  assert.ok(resultado.motivo);
});

test('rechaza un link que no responde antes del timeout', async () => {
  await conServidor(
    () => {
      /* nunca responde */
    },
    async url => {
      const resultado = await verificarLink(url, { timeoutMs: 300, comprobarDestino: permiteTodo });
      assert.strictEqual(resultado.ok, false);
      assert.match(resultado.motivo, /no respondi/i);
    },
  );
});

// ─── Defensa contra SSRF ─────────────────────────────────────
//
// La whitelist de dominios no basta: maps.app.goo.gl es un acortador, así
// que un atacante puede registrar un short link que apunte a 127.0.0.1 o al
// endpoint de metadata de la nube (169.254.169.254). El backend seguiría esa
// redirección y su respuesta ok/rechazo revelaría qué servicios internos
// existen. Por eso se comprueba CADA salto, no solo la URL original.

test('rechaza un destino que el guardián marca como no público', async () => {
  await conServidor(
    (_req, res) => res.writeHead(200).end(),
    async url => {
      const resultado = await verificarLink(url, {
        comprobarDestino: async () => false,
      });
      assert.strictEqual(resultado.ok, false);
      assert.match(resultado.motivo, /no se puede abrir|no v[áa]lid/i);
    },
  );
});

test('no sigue una redirección hacia un destino no público', async () => {
  const consultados = [];
  await conServidor(
    (req, res) => {
      if (req.url === '/negocio') {
        // Un acortador legítimo redirigiendo a la red interna.
        return res
          .writeHead(302, { Location: 'http://169.254.169.254/latest/meta-data/' })
          .end();
      }
      res.writeHead(200).end();
    },
    async url => {
      const resultado = await verificarLink(url, {
        comprobarDestino: async host => {
          consultados.push(host);
          return host !== '169.254.169.254';
        },
      });
      assert.strictEqual(resultado.ok, false);
      // El guardián debe haber visto el host de la redirección, no solo el
      // original: si solo se validara la URL inicial, jamás aparecería aquí.
      assert.ok(
        consultados.includes('169.254.169.254'),
        `el guardián solo vio ${JSON.stringify(consultados)}`,
      );
    },
  );
});

test('sigue redirecciones hacia destinos públicos hasta la respuesta final', async () => {
  await conServidor(
    (req, res) => {
      if (req.url === '/negocio') {
        return res.writeHead(302, { Location: '/perfil' }).end();
      }
      if (req.url === '/perfil') {
        return res.writeHead(301, { Location: '/perfil/final' }).end();
      }
      res.writeHead(200).end();
    },
    async url => {
      assert.strictEqual(
        (await verificarLink(url, { comprobarDestino: permiteTodo })).ok,
        true,
      );
    },
  );
});

test('corta una cadena infinita de redirecciones', async () => {
  await conServidor(
    (_req, res) => res.writeHead(302, { Location: '/vuelta' }).end(),
    async url => {
      const resultado = await verificarLink(url, {
        comprobarDestino: permiteTodo,
      });
      assert.strictEqual(resultado.ok, false);
      assert.match(resultado.motivo, /redirecc/i);
    },
  );
});

test('rechaza una redirección hacia un esquema que no es http', async () => {
  await conServidor(
    (_req, res) =>
      res.writeHead(302, { Location: 'file:///etc/passwd' }).end(),
    async url => {
      assert.strictEqual(
        (await verificarLink(url, { comprobarDestino: permiteTodo })).ok,
        false,
      );
    },
  );
});
