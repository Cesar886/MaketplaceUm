// Presencia: quién está en línea AHORA.
//
// La verdad vive en memoria, no en SQLite, y eso es deliberado. Una columna
// `is_online` persistida deja a todo el mundo marcado como conectado si el
// proceso muere (nadie llega a escribir el `false`), y el estado solo se
// arregla cuando cada usuario vuelve a entrar y salir. Al reiniciar el
// servidor este Map nace vacío, que es exactamente la verdad: no hay ningún
// socket abierto todavía. Lo único que sí se persiste es `last_active`, y se
// escribe una sola vez —al cerrarse el ÚLTIMO socket del usuario— para no
// castigar a SQLite con una escritura por heartbeat.
//
// El módulo recibe sus dependencias por parámetro (sin `require` de io ni de
// la base) para poder probar el refcount multi-dispositivo en aislamiento.

/**
 * @param {object} deps
 * @param {(userId: string, iso: string) => void} deps.guardarUltimaActividad
 * @param {(evento: {userId: string, online: boolean, lastActive: string|null}) => void} deps.emitirCambio
 * @param {() => Date} [deps.ahora]
 */
function crearRegistroPresencia({
  guardarUltimaActividad,
  emitirCambio,
  ahora = () => new Date(),
}) {
  /** userId → Set de socket.id abiertos. Un usuario con móvil y web tiene dos. */
  const socketsPorUsuario = new Map();
  /** socket.id → userId, para resolver el `disconnect`, que no trae el userId. */
  const usuarioPorSocket = new Map();

  function conectar(userId, socketId) {
    // El mismo socket puede reasignarse a otro usuario sin que el transporte
    // se caiga (cerrar sesión y entrar con otra cuenta manda un segundo
    // register:user). Sin este desalojo el usuario anterior se quedaría
    // colgado en línea para siempre.
    const anterior = usuarioPorSocket.get(socketId);
    if (anterior === userId) return;
    if (anterior) desconectar(socketId);

    usuarioPorSocket.set(socketId, userId);

    let sockets = socketsPorUsuario.get(userId);
    if (!sockets) {
      sockets = new Set();
      socketsPorUsuario.set(userId, sockets);
    }
    sockets.add(socketId);

    // Solo el primer dispositivo cambia el estado; el segundo no es noticia.
    if (sockets.size === 1) {
      emitirCambio({ userId, online: true, lastActive: null });
    }
  }

  function desconectar(socketId) {
    const userId = usuarioPorSocket.get(socketId);
    if (!userId) return;
    usuarioPorSocket.delete(socketId);

    const sockets = socketsPorUsuario.get(userId);
    if (!sockets) return;
    sockets.delete(socketId);
    if (sockets.size > 0) return;

    socketsPorUsuario.delete(userId);
    const lastActive = ahora().toISOString();
    guardarUltimaActividad(userId, lastActive);
    emitirCambio({ userId, online: false, lastActive });
  }

  const estaEnLinea = (userId) => socketsPorUsuario.has(userId);
  const usuariosEnLinea = () => socketsPorUsuario.keys();

  return { conectar, desconectar, estaEnLinea, usuariosEnLinea };
}

/**
 * ¿Puede `visor` ver la presencia de `objetivo`?
 *
 * La regla es recíproca a propósito (igual que WhatsApp): quien apaga su
 * propio estado deja de ver el ajeno. Sin eso el ajuste crea free-riders que
 * se esconden y siguen espiando, y el toggle deja de ser un intercambio justo.
 */
function presenciaVisible({ visorComparte, objetivoComparte }) {
  return Boolean(visorComparte) && Boolean(objetivoComparte);
}

/** Lo que ve alguien que no tiene permiso: exactamente "desconectado". */
const PRESENCIA_OCULTA = { isOnline: false, lastActive: null };

/**
 * Traduce el estado de `objetivoId` a los dos campos que viajan en las
 * respuestas HTTP, aplicando ya la regla de privacidad.
 *
 * Cuando no hay permiso devuelve el mismo objeto que un usuario desconectado
 * y sin `last_active`, en vez de una bandera tipo `hidden: true`: si el
 * ocultamiento fuera distinguible, el propio hecho de esconderse sería una
 * señal observable y el ajuste no serviría de nada.
 *
 * @param {object} args
 * @param {string|null} args.visorId — quién pregunta (null si es anónimo)
 * @param {string} args.objetivoId — de quién se pregunta
 * @param {(userId: string) => boolean} args.estaEnLinea
 * @param {(userId: string) => {lastActive: string|null, comparteEstado: boolean}} args.getPresencia
 * @returns {{isOnline: boolean, lastActive: string|null}}
 */
function describirPresencia({ visorId, objetivoId, estaEnLinea, getPresencia }) {
  if (!visorId || !objetivoId) return { ...PRESENCIA_OCULTA };

  const objetivo = getPresencia(objetivoId);
  const visible = presenciaVisible({
    visorComparte: getPresencia(visorId).comparteEstado,
    objetivoComparte: objetivo.comparteEstado,
  });
  if (!visible) return { ...PRESENCIA_OCULTA };

  if (estaEnLinea(objetivoId)) return { isOnline: true, lastActive: null };
  return { isOnline: false, lastActive: objetivo.lastActive };
}

module.exports = { crearRegistroPresencia, presenciaVisible, describirPresencia };
