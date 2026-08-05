const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');

const { verificarLink } = require('./linkCheck');

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
      assert.deepStrictEqual(await verificarLink(url), { ok: true, motivo: null });
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
      assert.strictEqual((await verificarLink(url)).ok, true);
    },
  );
});

test('acepta un link que responde 999 como LinkedIn/Instagram al bloquear', async () => {
  await conServidor(
    (_req, res) => res.writeHead(999).end(),
    async url => {
      assert.strictEqual((await verificarLink(url)).ok, true);
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
      assert.strictEqual((await verificarLink(url)).ok, true);
    },
  );
});

test('rechaza un link que responde 404', async () => {
  await conServidor(
    (_req, res) => res.writeHead(404).end(),
    async url => {
      const resultado = await verificarLink(url);
      assert.strictEqual(resultado.ok, false);
      assert.match(resultado.motivo, /no existe|no encontr/i);
    },
  );
});

test('rechaza un link que responde 500', async () => {
  await conServidor(
    (_req, res) => res.writeHead(500).end(),
    async url => {
      assert.strictEqual((await verificarLink(url)).ok, false);
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
      assert.strictEqual((await verificarLink(url)).ok, true);
    },
  );
});

test('rechaza un link cuyo host no resuelve', async () => {
  const resultado = await verificarLink(
    'https://este-dominio-no-existe-mercadito-um-12345.com',
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
      const resultado = await verificarLink(url, { timeoutMs: 300 });
      assert.strictEqual(resultado.ok, false);
      assert.match(resultado.motivo, /no respondi/i);
    },
  );
});
