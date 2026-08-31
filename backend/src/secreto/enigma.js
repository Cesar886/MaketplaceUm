// El enigma escondido de Mercadito.
//
// Nada de esto aparece en ningún menú, ninguna pantalla y ninguna respuesta
// de la API que un usuario normal llegue a ver. La única puerta es escribir
// una frase exacta en el campo de comentarios de cualquier publicación: el
// comentario NO se guarda ni se le muestra a nadie, y en su lugar la app
// abre la pantalla del acertijo.
//
// Ni la frase ni la respuesta viven aquí en claro: se guardan sus SHA-256.
// El repositorio es público, así que un hash es lo único que puede estar en
// el código sin regalar el juego a quien simplemente lee el archivo. Quien
// quiera entrar tiene que encontrar y descifrar la pista que hay sembrada en
// el cliente, no leer esta constante.
//
// Sobre la fuerza del hash: no protege un secreto de seguridad, protege el
// final de un juego. Da igual que una frase corta en español sea atacable por
// diccionario — quien monte ese ataque para colarse ya se ganó el premio.

const crypto = require('node:crypto');

/**
 * Frase que abre el enigma, escrita en un comentario de producto.
 * SHA-256 de la forma normalizada por [normalizar].
 */
const HASH_FRASE = '6d028ccae1cfaf9c1b8b87ba3fb05e26d9bd3692a34fe962cd378749e4ba469c';

/**
 * Respuesta del acertijo.
 *
 * Se valida en el servidor y nunca viaja al cliente, ni siquiera hasheada:
 * en el APK, un hash es un objetivo de fuerza bruta con el diccionario
 * español entero; aquí, cada intento cuesta una petición y pasa por
 * [SEGUNDOS_ENTRE_INTENTOS].
 */
const HASH_RESPUESTA = '386be7196ffddb162a13e3c1cafc7c32f866c369d3601d847b29368456c07792';

/** Espera mínima entre dos intentos de respuesta del MISMO usuario. */
const SEGUNDOS_ENTRE_INTENTOS = 3;

/**
 * Deja un texto libre en la forma que se compara contra los hashes.
 *
 * Se es deliberadamente generoso: minúsculas, sin acentos, sin signos y con
 * los espacios colapsados. Que alguien pierda el enigma por haber escrito
 * "El Primero, en llegar." sería un mal chiste, no dificultad — la dificultad
 * está en descubrir la frase, no en teclearla con precisión de notario.
 *
 * @param {unknown} entrada
 * @returns {string} forma normalizada, o '' si la entrada no es texto
 */
function normalizar(entrada) {
  if (typeof entrada !== 'string') return '';
  return entrada
    .normalize('NFD')
    // Diacríticos ya separados por NFD: acentos, diéresis, tilde de la ñ.
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    // Todo lo que no sea letra o número pasa a ser separador, y de ahí a un
    // solo espacio: puntuación, emojis y guiones no cambian lo que se dijo.
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function hash(texto) {
  return crypto.createHash('sha256').update(texto).digest('hex');
}

/**
 * Comparación en tiempo constante entre el hash del texto normalizado y
 * [esperado].
 *
 * `timingSafeEqual` sobre dos hashes del mismo largo, no sobre los textos:
 * el largo del hash es fijo y público, así que la comparación no filtra
 * cuánto se acertó del principio de la frase.
 */
function coincide(entrada, esperado) {
  const calculado = hash(normalizar(entrada));
  return crypto.timingSafeEqual(Buffer.from(calculado), Buffer.from(esperado));
}

/** ¿Este texto de comentario es la frase que abre el enigma? */
function esFraseDeEntrada(texto) {
  return coincide(texto, HASH_FRASE);
}

/** ¿Esta es la respuesta del acertijo? */
function esRespuestaCorrecta(texto) {
  return coincide(texto, HASH_RESPUESTA);
}

module.exports = {
  normalizar,
  esFraseDeEntrada,
  esRespuestaCorrecta,
  SEGUNDOS_ENTRE_INTENTOS,
};
