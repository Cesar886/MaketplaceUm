// Lista negra de nombres de perfil: insultos y, sobre todo, nombres que
// suplantan a la plataforma (admin, soporte, cuenta oficial de reportes…).
//
// El caso que más duele no es la grosería sino la suplantación: existe una
// cuenta oficial de reportes, y un usuario llamado "Reportes MercaditoUM"
// puede pedirle datos o dinero a cualquiera haciéndose pasar por nosotros.
// Por eso la parte de suplantación filtra por subcadena (agresiva) y la de
// insultos distingue entre palabras inequívocas y palabras cortas que
// aparecen dentro de palabras normales ("cálculo" contiene "culo").
//
// Se usa desde validateName (validation/sellerProfile.js), así que cubre
// los tres flujos que fijan un nombre: registro, registro con Google y
// edición de perfil.

// ─── Normalización ────────────────────────────────────────────────────
//
// El filtro se aplica sobre una versión "desnuda" del nombre para que
// "A d m i n", "Ådmín", "4dm1n" y "𝗔𝗗𝗠𝗜𝗡" caigan en la misma cadena.

// Invisibles: zero-width space/joiner, marcas de dirección, BOM. Sirven
// solo para partir una palabra prohibida por dentro.
const INVISIBLES = /[­​-‏‪-‮⁠-⁤﻿]/g;

// Cirílico y griego que se ven idénticos a letras latinas: "аdmin" con la
// а cirílica pasaría cualquier lista escrita en ASCII.
const CONFUNDIBLES = {
  а: 'a', в: 'b', с: 'c', ԁ: 'd', е: 'e', ѕ: 's', і: 'i', ј: 'j', к: 'k',
  м: 'm', н: 'h', о: 'o', р: 'p', т: 't', у: 'y', х: 'x', г: 'r',
  α: 'a', β: 'b', ε: 'e', ι: 'i', κ: 'k', ο: 'o', ρ: 'p', τ: 't', υ: 'u',
  ν: 'v', χ: 'x', ѵ: 'v', ʟ: 'l', ɪ: 'i', ѐ: 'e',
};

// Sustituciones "leet". Ojo con las ambiguas: `1` y `|` pueden ser i o l,
// así que se prueban las dos variantes (ver variantesNormalizadas).
const LEET_FIJO = {
  '0': 'o', '3': 'e', '4': 'a', '5': 's', '6': 'g', '7': 't', '8': 'b',
  '9': 'g', '@': 'a', '$': 's', '€': 'e', '£': 'l', '+': 't', '¡': 'i',
  'ø': 'o', 'ð': 'o', 'æ': 'a', 'œ': 'o', 'ß': 'b', 'ʼ': '',
};

const LEET_AMBIGUO = { '1': ['i', 'l'], '|': ['i', 'l'], '!': ['i', 'l'], '2': ['z', 'z'] };

/**
 * Baja a minúsculas, quita acentos, resuelve confundibles y leet fijo.
 * Devuelve solo letras y dígitos + separadores colapsados a un espacio.
 */
function base(texto) {
  const sinInvisibles = String(texto).replace(INVISIBLES, '');
  // NFKD además de quitar acentos convierte los alfabetos "matemáticos"
  // (𝗔, 𝒂, ﬁ…) y los círculos/anchos completos a letras normales.
  const plano = sinInvisibles
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();

  let salida = '';
  for (const caracter of plano) {
    if (CONFUNDIBLES[caracter]) salida += CONFUNDIBLES[caracter];
    else if (LEET_FIJO[caracter] !== undefined) salida += LEET_FIJO[caracter];
    else salida += caracter;
  }
  return salida;
}

/**
 * Las dos lecturas posibles de los caracteres ambiguos: "adm1n" se lee
 * "admin" y "admln", y basta con que una de las dos esté prohibida.
 */
function variantesNormalizadas(texto) {
  const crudo = base(texto);
  const variantes = new Set();

  for (const indice of [0, 1]) {
    let variante = '';
    for (const caracter of crudo) {
      const opciones = LEET_AMBIGUO[caracter];
      variante += opciones ? opciones[indice] : caracter;
    }
    // Todo lo que no sea letra/dígito es separador: puntos, guiones bajos,
    // emojis y demás relleno con el que se disfraza una palabra.
    variantes.add(variante.replace(/[^a-z0-9]+/g, ' ').trim());
  }
  return [...variantes];
}

/** Colapsa repeticiones: "aaadmiiin" → "admin", "putooo" → "puto". */
function sinRepeticiones(texto) {
  return texto.replace(/(.)\1+/g, '$1');
}

// ─── Suplantación de la plataforma y su staff ─────────────────────────
//
// Se buscan como subcadena sobre el nombre sin espacios, así que
// "MercaditoUM_Oficial", "soporte24h" y "el admin" caen igual. Es
// deliberadamente agresivo: un falso positivo se resuelve eligiendo otro
// nombre, una suplantación se resuelve estafando a alguien.
const SUPLANTACION = [
  // Administración
  'admin', 'adminstrador', 'administrador', 'administradora', 'administracion',
  'administration', 'administrator', 'sysadmin', 'webmaster', 'root',
  'superuser', 'superusuario', 'superadmin', 'moderador', 'moderadora',
  'moderator', 'moderacion', 'staff', 'sistema', 'system', 'systemadmin',
  'operador', 'operator', 'supervisor', 'director', 'gerencia',
  // Soporte y atención
  'soporte', 'support', 'helpdesk', 'mesadeayuda', 'servicioalcliente',
  'servicioclientes', 'atencionalcliente', 'atencioncliente',
  'atencionusuario', 'customerservice', 'customersupport',
  // Reportes y denuncias — hay una cuenta oficial con este rol
  'reporte', 'reportes', 'report', 'reports', 'reporting', 'reportar',
  'denuncia', 'denuncias', 'denunciar', 'abuso', 'abuse', 'antifraude',
  'antiestafa', 'fraude', 'seguridad', 'security', 'trustandsafety',
  'moderaciondecontenido',
  // Identidad de la plataforma
  'mercaditoum', 'mercaditooficial', 'mercaditoapp', 'mercaditosoporte',
  'equipomercadito', 'umoficial', 'oficialum', 'universidadum',
  'umadmin', 'umsoporte',
  // Sellos de autoridad
  'oficial', 'official', 'verificado', 'verificada', 'verified',
  'cuentaoficial', 'perfiloficial', 'paginaoficial', 'certificado',
  'autorizado', 'autorizada',
  // Cuentas de sistema / notificaciones
  'noreply', 'nreply', 'donotreply', 'notificacion', 'notificaciones',
  'notification', 'notifications', 'alerta', 'alertas', 'aviso',
  'avisooficial', 'anuncio', 'anuncios', 'newsletter', 'mailer', 'daemon',
  'postmaster', 'nulo', 'null', 'undefined', 'anonymous',
  // Pagos y verificación: los ganchos clásicos de phishing
  'pagosoficiales', 'pagosum', 'facturacion', 'billing', 'cobranza',
  'verificaciondecuenta', 'verificacioncuenta', 'centrodeayuda',
  'centrodesoporte', 'soporteoficial', 'ayudaoficial',
  // Marcas de pago que se prestan a suplantación en un marketplace
  'mercadopago', 'mercadolibre', 'whatsappsoporte', 'googlesoporte',
  // Bots
  'chatbot', 'botoficial', 'assistant', 'asistenteoficial',
];

// Palabras cortas que solo se prohíben si son el nombre completo o una
// palabra suelta: "mod", "bot" o "ayuda" dentro de otra palabra son ruido
// ("modelo", "botines", "ayudante"), pero solas suplantan igual.
const SUPLANTACION_EXACTA = [
  'mod', 'mods', 'bot', 'bots', 'ayuda', 'help', 'info', 'contacto',
  'contact', 'equipo', 'team', 'staff', 'admins', 'um', 'mercadito',
  'ceo', 'owner', 'dueno', 'legal', 'soporteum', 'api', 'test', 'testing',
];

// ─── Insultos y contenido sexual explícito ────────────────────────────
//
// INSULTOS_CONTENIDOS se busca como subcadena: son palabras largas y sin
// colisiones reales en español, así que "elputoamo" o "xxhijodeputaxx"
// caen sin necesidad de espacios.
const INSULTOS_CONTENIDOS = [
  // Español
  'hijodeputa', 'hijadeputa', 'hijosdeputa', 'hijueputa', 'hijeputa',
  'malparido', 'malparida', 'malnacido', 'malnacida', 'chupapija',
  'chupaverga', 'chupapollas', 'lameculos', 'comemierda', 'comepija',
  'pajero', 'pajera', 'pajeros', 'mierda', 'mierdas', 'pendejo', 'pendeja',
  'pendejos', 'gilipollas', 'cabron', 'cabrona', 'cabrones', 'joputa',
  'putamadre', 'tuputamadre', 'lacagada', 'cagada', 'cagon', 'meada',
  'verga', 'vergas', 'vergon', 'pinche', 'chingada', 'chingar', 'chingate',
  'chingon', 'culiado', 'culiao', 'culeado', 'culero', 'conchatumadre',
  'conchasumadre', 'concheto', 'reconcha', 'forro', 'boludo', 'boluda',
  'pelotudo', 'pelotuda', 'gonorrea', 'huevon', 'guevon', 'weon',
  'imbecil', 'estupido', 'estupida', 'idiota', 'retrasado', 'retrasada',
  'mongolico', 'mongolica', 'subnormal', 'zorra', 'zorras', 'perra',
  'putita', 'putito', 'putiza', 'putero', 'prostituta', 'prostituto',
  'meretriz', 'trolo', 'travuca', 'maricon', 'marica', 'maricas',
  'mariconazo', 'joto', 'puñal', 'punal', 'sidoso', 'negrodemierda',
  'sudaca', 'panchito', 'indiodemierda', 'cerdaza',
  // Sexual explícito
  'follar', 'follame', 'follada', 'cojer', 'cogerte', 'cogeme',
  'masturba', 'masturbacion', 'semen', 'esperma',
  'eyacula', 'orgasmo', 'porno', 'pornografia', 'xxx', 'hentai',
  'zoofilia', 'pedofilo', 'pedofila', 'pedofilia', 'pederasta',
  'incesto', 'violador', 'violadora', 'violacion', 'pornhub', 'onlyfans',
  'nopor', 'nudes', 'sexo', 'sexoanal', 'analsex', 'blowjob', 'handjob',
  'creampie', 'cumshot', 'gangbang', 'deepthroat', 'penetracion',
  // Inglés
  'fuck', 'fucker', 'fucking', 'motherfucker', 'bitch', 'bitches',
  'asshole', 'bastard', 'dickhead', 'cocksucker', 'wanker', 'twat',
  'slut', 'whore', 'pussy', 'nigger', 'nigga', 'faggot', 'retard',
  'shithead', 'bullshit', 'jerkoff',
  // Odio / violencia
  'hitler', 'nazi', 'nazis', 'heilhitler', 'holocausto', 'kukluxklan',
  'genocidio', 'terrorista', 'alqaeda', 'matate', 'suicidate',
  'muerete', 'ojalatemueras', 'violarte', 'matarte',
  // Drogas y armas: no son insultos pero tampoco nombres de perfil
  'cocaina', 'marihuana', 'metanfetamina', 'vendodroga', 'narcotrafico',
  'sicario',
];

// Palabras cortas o ambiguas: solo se prohíben como palabra suelta, porque
// aparecen dentro de palabras perfectamente normales — "culo" en cálculo o
// artículo, "teta" en camiseta, "puta" en diputado, "polla" en ampolla,
// "pene" en Penélope, "ano" en mano/piano, "concha" en un apellido.
const INSULTOS_EXACTOS = [
  'puta', 'puto', 'putas', 'putos', 'culo', 'culos', 'culito', 'ojete',
  'teta', 'tetas', 'tetona', 'chichis', 'polla', 'pollas', 'pija', 'pijas',
  'pito', 'pene', 'penes', 'falo', 'huevos', 'bolas', 'cojones', 'coño',
  'cono', 'concha', 'conchuda', 'chocho', 'raja', 'vagina', 'clitoris',
  'ano', 'anos', 'culiar', 'coger', 'mamada', 'mamadas', 'chupada',
  'chupame', 'lameme', 'tragame', 'zorro', 'perro', 'burro', 'tarado',
  'tarada', 'menso', 'baboso', 'babosa', 'asqueroso', 'nefasto',
  'caca', 'popo', 'pedo', 'pis', 'meo', 'orina', 'semental',
  'paja', 'pajas', 'wea', 'cum', 'dick', 'cock', 'tits', 'boobs', 'anal', 'porn', 'sex', 'shit',
  'damn', 'crap', 'hoe', 'milf', 'rape', 'kill', 'die',
];

// Palabras normales que contienen una prohibida y que NO deben bloquearse.
// Se comprueban antes que las subcadenas, palabra por palabra.
const EXCEPCIONES = new Set([
  'calculo', 'calculos', 'calculadora', 'articulo', 'articulos',
  'ridiculo', 'ridicula', 'masculino', 'minusculo', 'circulo', 'vehiculo',
  'curriculo', 'oculto', 'musculo', 'particula', 'peliculas', 'pelicula',
  'camiseta', 'camisetas', 'chaqueta', 'maleta', 'paleta', 'raqueta',
  'diputado', 'diputada', 'computadora', 'computacion', 'reputacion',
  'disputa', 'amputado', 'ampolla', 'pollada', 'pollo', 'pollos',
  'pollera', 'repollo', 'penelope', 'pendiente', 'peninsula', 'penal',
  'mano', 'manos', 'piano', 'plano', 'llano', 'verano', 'hermano',
  'anillo', 'analisis', 'analista', 'analitica', 'canal', 'banal',
  'sexto', 'sexta', 'sextante', 'essex', 'middlesex', 'sussex',
  'cocina', 'cocinero', 'cocinera', 'bocina', 'vecina', 'vacuna',
  'escoger', 'recoger', 'acoger', 'protege', 'cogedor',
  'marico', 'maricultura', 'mariposa', 'mariana', 'maria', 'mario',
  'zorrilla', 'perrera', 'perruno', 'cacao', 'cacahuate', 'cacerola',
  'vergara', 'pajarito', 'pajaro', 'pajarera', 'pajarera',
  'wear', 'sweater', 'streetwear', 'swear', 'weather',
  'pedroso', 'pedrito', 'pedro', 'espedito', 'pisco', 'pistola',
  'sexologo', 'sexualidad', 'homosexual', 'asexual', 'intersexual',
  'kills', 'skill', 'skills', 'diesel', 'dieta', 'dientes',
  'shitake', 'shiitake', 'analogo', 'analogico', 'canalizar',
]);

// Un nombre debe tener alguna letra: "123", "***" o solo emojis no son
// nombres, y son la vía obvia para saltarse cualquier lista de palabras.
// Se mira el texto original (no la versión leet, donde "12345" se
// convertiría en "izeas") y se aceptan letras de cualquier alfabeto.
const TIENE_LETRA = /\p{L}/u;

/** Primera lista prohibida que aparezca como subcadena de `texto`. */
function buscarSubcadena(texto) {
  for (const termino of SUPLANTACION) {
    if (texto.includes(termino)) return { motivo: 'suplantacion', termino };
  }
  for (const termino of INSULTOS_CONTENIDOS) {
    if (texto.includes(termino)) return { motivo: 'ofensivo', termino };
  }
  return null;
}

/**
 * ¿Este nombre está prohibido?
 *
 * @param {string} nombre nombre tal cual lo escribió el usuario
 * @returns {{motivo: 'suplantacion'|'ofensivo'|'sin_letras', termino?: string} | null}
 *   null si el nombre es aceptable.
 */
function revisarNombre(nombre) {
  if (typeof nombre !== 'string') return null;

  if (!TIENE_LETRA.test(nombre.normalize('NFKD').replace(INVISIBLES, ''))) {
    return { motivo: 'sin_letras' };
  }

  const variantes = variantesNormalizadas(nombre);

  for (const variante of variantes) {
    // Se prueba con y sin repeticiones para atrapar "aadmiiin" sin romper
    // palabras legítimas con dobles ("llano", "carro") en la vuelta normal.
    for (const texto of new Set([variante, sinRepeticiones(variante)])) {
      const palabras = texto.split(' ').filter(Boolean);
      const pegado = palabras.join('');

      for (const palabra of palabras) {
        if (SUPLANTACION_EXACTA.includes(palabra)) {
          return { motivo: 'suplantacion', termino: palabra };
        }
        if (INSULTOS_EXACTOS.includes(palabra)) {
          return { motivo: 'ofensivo', termino: palabra };
        }
      }

      // Subcadenas, palabra por palabra: así "Cálculo" no arrastra al resto
      // del nombre a la lista de excepciones, y "elputoamo" sí cae.
      for (const palabra of palabras) {
        if (EXCEPCIONES.has(palabra)) continue;
        const encontrado = buscarSubcadena(palabra);
        if (encontrado) return encontrado;
      }

      // Y una pasada sobre el nombre pegado, para que los separadores no
      // sirvan de disfraz ("a d m i n", "S.O.P.O.R.T.E"). Se salta si hay
      // alguna palabra legítima de por medio, porque pegar palabras crea
      // coincidencias falsas entre los bordes ("Marco Ncha" → "concha").
      if (palabras.length > 1 && !palabras.some((p) => EXCEPCIONES.has(p))) {
        const encontrado = buscarSubcadena(pegado);
        if (encontrado) return encontrado;
      }
    }
  }

  return null;
}

const MENSAJES = {
  suplantacion:
    'Ese nombre no está disponible: no puede parecerse al de una cuenta ' +
    'oficial de MercaditoUM (administración, soporte o reportes).',
  ofensivo: 'Ese nombre contiene lenguaje ofensivo. Elige otro.',
  sin_letras: 'El nombre debe contener al menos una letra.',
};

/**
 * Mensaje de error listo para la UI, o null si el nombre se puede usar.
 * @param {string} nombre
 * @returns {string|null}
 */
function validarNombreProhibido(nombre) {
  const resultado = revisarNombre(nombre);
  return resultado ? MENSAJES[resultado.motivo] : null;
}

module.exports = {
  revisarNombre,
  validarNombreProhibido,
  variantesNormalizadas,
  SUPLANTACION,
  SUPLANTACION_EXACTA,
  INSULTOS_CONTENIDOS,
  INSULTOS_EXACTOS,
  EXCEPCIONES,
};
