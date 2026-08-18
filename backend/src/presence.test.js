// Registro de presencia en memoria: quién está en línea AHORA.
//
// Es puro a propósito (recibe sus dependencias por parámetro) para poder
// probar el refcount multi-dispositivo sin levantar Socket.IO ni SQLite.

const test = require('node:test');
const assert = require('node:assert');

const {
  crearRegistroPresencia,
  presenciaVisible,
  describirPresencia,
} = require('./presence');

/** Registro con los efectos capturados en arrays, para poder afirmarlos. */
function registroDePrueba({ ahora = () => new Date('2026-08-17T10:00:00.000Z') } = {}) {
  const guardados = [];
  const emitidos = [];
  const presencia = crearRegistroPresencia({
    guardarUltimaActividad: (userId, iso) => guardados.push({ userId, iso }),
    emitirCambio: (evento) => emitidos.push(evento),
    ahora,
  });
  return { presencia, guardados, emitidos };
}

test('conectar marca al usuario en línea y emite el cambio', () => {
  const { presencia, emitidos } = registroDePrueba();

  presencia.conectar('u1', 'socket-a');

  assert.equal(presencia.estaEnLinea('u1'), true);
  assert.deepEqual(emitidos, [{ userId: 'u1', online: true, lastActive: null }]);
});

test('un segundo dispositivo del mismo usuario no vuelve a emitir', () => {
  const { presencia, emitidos } = registroDePrueba();

  presencia.conectar('u1', 'socket-a');
  presencia.conectar('u1', 'socket-b');

  assert.equal(emitidos.length, 1);
});

test('reconectar el MISMO socket no infla el contador', () => {
  const { presencia, emitidos } = registroDePrueba();

  presencia.conectar('u1', 'socket-a');
  presencia.conectar('u1', 'socket-a');
  presencia.desconectar('socket-a');

  assert.equal(presencia.estaEnLinea('u1'), false);
  assert.equal(emitidos.at(-1).online, false);
});

test('cerrar un dispositivo mientras otro sigue abierto NO marca offline', () => {
  const { presencia, emitidos, guardados } = registroDePrueba();

  presencia.conectar('u1', 'socket-movil');
  presencia.conectar('u1', 'socket-web');
  presencia.desconectar('socket-movil');

  assert.equal(presencia.estaEnLinea('u1'), true);
  assert.equal(emitidos.length, 1, 'solo el evento inicial de online');
  assert.deepEqual(guardados, [], 'last_active se escribe solo al cerrar el último');
});

test('cerrar el último dispositivo guarda last_active y emite offline', () => {
  const { presencia, emitidos, guardados } = registroDePrueba();

  presencia.conectar('u1', 'socket-a');
  presencia.desconectar('socket-a');

  assert.equal(presencia.estaEnLinea('u1'), false);
  assert.deepEqual(guardados, [
    { userId: 'u1', iso: '2026-08-17T10:00:00.000Z' },
  ]);
  assert.deepEqual(emitidos.at(-1), {
    userId: 'u1',
    online: false,
    lastActive: '2026-08-17T10:00:00.000Z',
  });
});

test('desconectar un socket que nunca se registró no hace nada', () => {
  const { presencia, emitidos, guardados } = registroDePrueba();

  presencia.desconectar('socket-fantasma');

  assert.deepEqual(emitidos, []);
  assert.deepEqual(guardados, []);
});

test('un socket puede reasignarse a otro usuario sin dejar al anterior colgado', () => {
  // Pasa de verdad: el usuario cierra sesión y entra con otra cuenta sin que
  // el transporte se caiga, así que llega un segundo register:user por el
  // mismo socket.id.
  const { presencia } = registroDePrueba();

  presencia.conectar('u1', 'socket-a');
  presencia.conectar('u2', 'socket-a');

  assert.equal(presencia.estaEnLinea('u1'), false);
  assert.equal(presencia.estaEnLinea('u2'), true);
});

test('usuariosEnLinea devuelve solo a los conectados', () => {
  const { presencia } = registroDePrueba();

  presencia.conectar('u1', 'socket-a');
  presencia.conectar('u2', 'socket-b');
  presencia.desconectar('socket-b');

  assert.deepEqual([...presencia.usuariosEnLinea()], ['u1']);
});

// ─── Reciprocidad de privacidad ──────────────────────────────

test('la presencia es visible cuando ambos la comparten', () => {
  assert.equal(presenciaVisible({ visorComparte: true, objetivoComparte: true }), true);
});

test('quien oculta su estado tampoco ve el de los demás', () => {
  // Sin esta regla habría free-riders: te escondes y espías igual.
  assert.equal(presenciaVisible({ visorComparte: false, objetivoComparte: true }), false);
});

test('no se ve el estado de quien lo tiene oculto', () => {
  assert.equal(presenciaVisible({ visorComparte: true, objetivoComparte: false }), false);
});

// ─── describirPresencia: lo que sale en las respuestas HTTP ───

/** Preferencias por usuario, con todos compartiendo salvo que se diga. */
function lectorDePreferencias(preferencias) {
  return (userId) =>
    preferencias[userId] || { lastActive: null, comparteEstado: true };
}

test('describirPresencia reporta en línea a quien tiene un socket abierto', () => {
  const estado = describirPresencia({
    visorId: 'yo',
    objetivoId: 'tu',
    estaEnLinea: (id) => id === 'tu',
    getPresencia: lectorDePreferencias({}),
  });

  assert.deepEqual(estado, { isOnline: true, lastActive: null });
});

test('describirPresencia reporta la última actividad de quien está desconectado', () => {
  const estado = describirPresencia({
    visorId: 'yo',
    objetivoId: 'tu',
    estaEnLinea: () => false,
    getPresencia: lectorDePreferencias({
      tu: { lastActive: '2026-08-17T09:00:00.000Z', comparteEstado: true },
    }),
  });

  assert.deepEqual(estado, { isOnline: false, lastActive: '2026-08-17T09:00:00.000Z' });
});

test('quien oculta su estado se ve igual que alguien desconectado, sin last_active', () => {
  // Importa que sea indistinguible de "offline": si la API respondiera algo
  // como `hidden: true`, el propio ocultamiento sería una señal observable.
  const estado = describirPresencia({
    visorId: 'yo',
    objetivoId: 'tu',
    estaEnLinea: () => true,
    getPresencia: lectorDePreferencias({
      tu: { lastActive: '2026-08-17T09:00:00.000Z', comparteEstado: false },
    }),
  });

  assert.deepEqual(estado, { isOnline: false, lastActive: null });
});

test('quien apagó su propio estado no ve el de los demás', () => {
  const estado = describirPresencia({
    visorId: 'yo',
    objetivoId: 'tu',
    estaEnLinea: () => true,
    getPresencia: lectorDePreferencias({
      yo: { lastActive: null, comparteEstado: false },
    }),
  });

  assert.deepEqual(estado, { isOnline: false, lastActive: null });
});

test('un visitante anónimo no ve presencia', () => {
  const estado = describirPresencia({
    visorId: null,
    objetivoId: 'tu',
    estaEnLinea: () => true,
    getPresencia: lectorDePreferencias({}),
  });

  assert.deepEqual(estado, { isOnline: false, lastActive: null });
});
