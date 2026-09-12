// Endpoint sin auth que recibe texto libre de cualquiera que sepa la IP del
// servidor. Lo que se prueba aquí es exactamente lo que motivó el
// endurecimiento: que no se pueda inyectar líneas de log falsas, que un
// payload enorme no se vuelque completo al archivo de log, y que alguien
// mandando ráfagas no pueda escribir sin límite.

const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');

const express = require('express');
const { register, sanear } = require('./clientErrors');

let baseUrl;
let servidor;
let logs;
let originalConsoleError;

test.before(async () => {
  const app = express();
  app.use(express.json());
  register(app);
  servidor = http.createServer(app);
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  await new Promise(r => servidor.close(r));
});

test.beforeEach(() => {
  logs = [];
  originalConsoleError = console.error;
  console.error = (...args) => logs.push(args.join(' '));
});

test.afterEach(() => {
  console.error = originalConsoleError;
});

async function postError(body, { installationId = 'installation-test-default' } = {}) {
  return fetch(`${baseUrl}/api/client-errors`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ installationId, ...body }),
  });
}

test('sanear() quita \\r y caracteres de control salvo cuando se permiten saltos', () => {
  assert.strictEqual(sanear('a\rb\tc', 100), 'a b c');
});

test('sanear() con permitirSaltos conserva \\n pero sigue quitando \\r', () => {
  assert.strictEqual(
    sanear('línea 1\r\nlínea 2', 100, { permitirSaltos: true }),
    'línea 1 \nlínea 2',
  );
});

test('sanear() quita escapes ANSI', () => {
  const conAnsi = '\x1b[31mrojo\x1b[0m';
  assert.strictEqual(sanear(conAnsi, 100), 'rojo');
});

test('sanear() recorta y avisa cuánto se cortó', () => {
  const r = sanear('a'.repeat(50), 10);
  assert.match(r, /^a{10}… \(\+40 caracteres recortados\)$/);
});

test('sanear() de un valor vacío tras limpiar vuelve null, no cadena vacía', () => {
  assert.strictEqual(sanear('   ', 100), null);
  assert.strictEqual(sanear('\x1b[0m', 100), null);
});

test('sanear() de un valor que no es string vuelve null', () => {
  assert.strictEqual(sanear(42, 100), null);
  assert.strictEqual(sanear(null, 100), null);
  assert.strictEqual(sanear(undefined, 100), null);
});

test('responde 204 con un body normal y lo loguea saneado', async () => {
  const res = await postError({
    plataforma: 'android',
    contexto: 'Fallo de red',
    error: 'SocketException: Connection refused',
  });
  assert.strictEqual(res.status, 204);
  assert.ok(logs.some(l => l.includes('android') && l.includes('SocketException')));
});

// El escenario de inyección: sin sanear, un error con \n podría escribir una
// línea que en el log se lea como si viniera de otra parte del sistema (p.
// ej. simulando otro nivel de log o un stack ajeno).
test('un error con \\n no crea entradas de log adicionales', async () => {
  const antes = logs.length;
  await postError({
    plataforma: 'android',
    contexto: 'x',
    error: 'línea falsa 1\n🔥 Firebase Admin SDK inicializado\nlínea falsa 2',
  });
  // Una sola llamada a console.error para el mensaje principal: los \n del
  // campo `error` no lograron partirlo en múltiples líneas de log.
  assert.strictEqual(logs.length - antes, 1);
  assert.ok(!logs[antes].includes('\n'));
});

test('una plataforma fuera de la lista blanca cae a "?"', async () => {
  await postError({ plataforma: 'plataforma-inventada', error: 'x' });
  assert.ok(logs.some(l => l.includes('[client-error] ? —')));
});

test('un stack larguísimo se trunca y no se vuelca completo', async () => {
  await postError({
    plataforma: 'android',
    error: 'x',
    stack: 'frame\n'.repeat(2000), // ~12000 caracteres
  });
  const lineaStack = logs.find(l => l.includes('frame'));
  assert.ok(lineaStack);
  assert.ok(lineaStack.length < 2200, `quedó sin truncar: ${lineaStack.length} chars`);
  assert.match(lineaStack, /caracteres recortados\)$/);
});

test('un body vacío o incompleto no revienta', async () => {
  const res1 = await postError({});
  assert.strictEqual(res1.status, 204);

  const res2 = await fetch(`${baseUrl}/api/client-errors`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '',
  });
  assert.strictEqual(res2.status, 204);
});

test('el rate limit corta una ráfaga de la misma instalación', async () => {
  // La ráfaga real que motivó esto: ~14 POSTs distintos en minuto y medio.
  // El límite de la ruta es 20/min, así que 25 seguidos deben ver algunos
  // 204 "silenciosos" del rate limiter una vez agotado el cupo.
  const respuestas = await Promise.all(
    Array.from({ length: 25 }, (_, i) =>
      postError({ plataforma: 'android', error: `intento ${i}` }),
    ),
  );
  // Todas responden 204 (el limiter también responde 204 para no darle a
  // quien abusa una señal distinta de "esto funcionó") — lo que cambia es
  // que no las 25 quedan logueadas.
  assert.ok(respuestas.every(r => r.status === 204));
  const logueados = logs.filter(l => l.includes('[client-error]')).length;
  assert.ok(
    logueados <= 20,
    `se logueó de más pese al límite: ${logueados} entradas`,
  );
  assert.ok(logueados > 0, 'el límite no debería bloquear TODO el tráfico normal');
});

test('instalaciones distintas en la misma IP nunca comparten límite', async () => {
  const respuestas = [];
  for (let i = 0; i < 25; i += 1) {
    respuestas.push(await postError(
      { plataforma: 'android', error: `instalación ${i}` },
      { installationId: `installation-campus-${i}` },
    ));
  }
  assert.ok(respuestas.every(r => r.status === 204));
  assert.equal(logs.filter(l => l.includes('[client-error]')).length, 25);
});
