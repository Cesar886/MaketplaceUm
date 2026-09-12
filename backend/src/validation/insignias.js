// Catálogo de insignias ocultables y validación del ajuste.
//
// Es la lista cerrada de lo que un vendedor puede quitar de su perfil. Vive
// aparte de sellerProfile.js porque no valida un campo del perfil sino un
// catálogo de producto: cada insignia nueva del sistema se añade aquí y en
// ningún otro sitio del backend.
//
// Verificado y Socio Fundador NO están: se pintan también en tarjetas,
// comentarios y chat, así que ocultarlas sería otra feature con otro
// alcance. Si algún día se permite, esto es lo único que hay que ampliar.

/**
 * Clave estable de cada insignia → el campo de `conMetricas` que apaga.
 *
 * Las claves son propias y no los nombres de los campos: los campos pueden
 * renombrarse en una refactorización, y estas viven guardadas en la base de
 * datos de producción, donde un renombrado silencioso dejaría preferencias
 * apuntando a nada.
 */
const INSIGNIAS_OCULTABLES = {
  leyenda: 'leyendaMercadito',
  vendedor_de_oro: 'vendedorDeOro',
  impecable: 'ratingPerfecto',
  centenario: 'cienCincoEstrellas',
  siempre_responde: 'siempreResponde',
  vendedor_confiable: 'vendedorConfiable',
  responde_rapido: 'respondeRapido',
  respuesta_instantanea: 'respuestaInstantanea',
  recien_llegado: 'recienRegistrado',
  recien_verificado: 'recienVerificado',
  novato: 'esVendedorNuevo',
  // Las tres de abajo no son booleanos sino contadores, y su campo se apaga
  // con el valor que el cliente ya interpreta como "no la pintes": 0 para
  // las de conteo, null para la posición del enigma.
  racha: 'rachaSemanas',
  aniversario: 'aniversarioAnios',
  enigma: 'enigmaPosicion',
};

/** Valor que apaga cada campo, según su forma. */
const APAGADO = {
  rachaSemanas: 0,
  aniversarioAnios: 0,
  enigmaPosicion: null,
};

/**
 * Cuándo cuenta como "ganada" cada insignia de contador.
 *
 * No basta con "distinto de cero": la app no pinta una racha de una sola
 * semana (una ventana no es una racha) ni un aniversario de cero años, así
 * que un switch encendible para esos casos ofrecería mostrar algo que nunca
 * se vería. Los umbrales están replicados de los call sites en
 * seller_profile_screen.dart.
 */
const GANADA = {
  rachaSemanas: v => (v ?? 0) > 1,
  aniversarioAnios: v => (v ?? 0) > 0,
  enigmaPosicion: v => v != null,
};

const CLAVES_INSIGNIAS = Object.keys(INSIGNIAS_OCULTABLES);

/**
 * Insignias que, una vez ganadas, no se pierden nunca.
 *
 * Las tres miden acumulado de por vida (ventas confirmadas, dinero
 * facturado, calificaciones de cinco estrellas): números que solo suben, así
 * que su dueño no puede hacer nada para bajarlos. La ÚNICA forma de perder
 * una era que subiéramos el umbral desde aquí, y quitarle a alguien una
 * insignia que ya se ganó por un cambio nuestro de criterio no es una regla
 * del sistema, es un error nuestro. Por eso se registran en
 * `insignias_otorgadas` la primera vez que se cumplen (ver
 * `registrarInsigniaOtorgada`) y a partir de ahí valen aunque el umbral suba.
 *
 * Las demás NO entran, y es deliberado: "Impecable" se pierde con la primera
 * reseña que no sea un cinco, "Responde rápido" con dejar de contestar,
 * "Novato" al envejecer la cuenta. Ésas describen cómo va el vendedor AHORA,
 * y volverlas permanentes las convertiría en una promesa falsa a quien las
 * lee.
 */
const INSIGNIAS_PERMANENTES = ['leyenda', 'vendedor_de_oro', 'centenario'];

/**
 * La ventana temporal común de las insignias de bienvenida: siete periodos
 * completos de 24 horas desde el instante guardado, nunca fechas futuras.
 * Acepta tanto TIMESTAMPTZ de PostgreSQL como el texto UTC de SQLite.
 */
function diasDesde(fecha, ahoraMs = Date.now()) {
  if (!fecha) return null;
  const texto = String(fecha);
  const normalizada = fecha instanceof Date
    ? fecha
    : new Date(texto.includes('T') ? texto : `${texto.replace(' ', 'T')}Z`);
  const edadMs = ahoraMs - normalizada.getTime();
  return Number.isFinite(edadMs) ? edadMs / 86400000 : null;
}

function estaEnPrimeraSemana(fecha, ahoraMs = Date.now()) {
  const dias = diasDesde(fecha, ahoraMs);
  return dias !== null && dias >= 0 && dias < 7;
}

/**
 * Valida la lista que manda el cliente en PATCH /api/sellers/:id.
 *
 * Los duplicados se rechazan en vez de deduplicarse en silencio: una lista
 * con la misma clave dos veces es señal de un cliente confundido, y guardarla
 * "arreglada" esconde el error hasta que aparece en otra parte.
 *
 * @returns {{error: string}|{value: string[]}}
 */
function validateInsigniasOcultas(insigniasOcultas) {
  if (!Array.isArray(insigniasOcultas)) {
    return { error: 'insigniasOcultas debe ser una lista' };
  }
  if (insigniasOcultas.length > CLAVES_INSIGNIAS.length) {
    return { error: 'insigniasOcultas trae más elementos de los que existen' };
  }
  const vistas = new Set();
  for (const clave of insigniasOcultas) {
    if (typeof clave !== 'string' || !CLAVES_INSIGNIAS.includes(clave)) {
      return { error: `Insignia desconocida: ${clave}` };
    }
    if (vistas.has(clave)) {
      return { error: `Insignia repetida: ${clave}` };
    }
    vistas.add(clave);
  }
  return { value: [...insigniasOcultas] };
}

/**
 * Apaga en `metricas` las insignias que su dueño decidió no mostrar.
 *
 * Devuelve un objeto nuevo: el llamador está armando la respuesta de un
 * endpoint público y mutar la fila del vendedor en memoria haría que la
 * preferencia se "pegara" al resto de respuestas del proceso.
 */
function aplicarInsigniasOcultas(metricas, ocultas) {
  if (!ocultas || ocultas.length === 0) return metricas;
  const resultado = { ...metricas };
  for (const clave of ocultas) {
    const campo = INSIGNIAS_OCULTABLES[clave];
    // Una clave que ya no existe en el catálogo (insignia retirada) se
    // ignora: la preferencia guardada sobrevive a la insignia, y eso no
    // debe romper el perfil.
    if (!campo) continue;
    resultado[campo] = campo in APAGADO ? APAGADO[campo] : false;
  }
  return resultado;
}

/**
 * Qué insignias tiene REALMENTE la cuenta, ocultas incluidas. Solo se manda
 * al propio dueño: es lo que la pantalla de selección necesita para saber
 * qué switches puede encender.
 */
function insigniasGanadas(metricas) {
  const ganadas = {};
  for (const [clave, campo] of Object.entries(INSIGNIAS_OCULTABLES)) {
    const predicado = GANADA[campo];
    ganadas[clave] = predicado ? predicado(metricas[campo]) : !!metricas[campo];
  }
  return ganadas;
}

module.exports = {
  INSIGNIAS_OCULTABLES,
  CLAVES_INSIGNIAS,
  INSIGNIAS_PERMANENTES,
  diasDesde,
  estaEnPrimeraSemana,
  validateInsigniasOcultas,
  aplicarInsigniasOcultas,
  insigniasGanadas,
};
