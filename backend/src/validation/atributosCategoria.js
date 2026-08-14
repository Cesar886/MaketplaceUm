const {
  preguntasDeCategoria,
  ATRIBUTOS_DESTACADOS,
  MAX_ATRIBUTOS_DESTACADOS,
} = require('../config/atributosCategoria');

/** Tope de caracteres de una respuesta de texto libre. */
const MAX_LARGO_TEXTO = 200;

/**
 * Normaliza y valida las respuestas a las preguntas dinámicas de una
 * categoría.
 *
 * Devuelve `{ value }` con un objeto listo para guardar, o `{ error }` con un
 * mensaje en español para el usuario. `value` es `null` cuando no quedó
 * ninguna respuesta: null y `{}` significan lo mismo para el cliente, y null
 * ahorra guardar una cadena `'{}'` en cada producto que no contestó nada.
 *
 * El criterio general es **descartar en silencio, rechazar solo lo que
 * miente**. Una key desconocida se ignora (un cliente viejo mandando un
 * atributo que ya se quitó no debe impedir publicar), pero un valor fuera de
 * las `options` declaradas sí es un error: significa que el cliente y el
 * servidor no coinciden en el catálogo, y guardarlo dejaría un producto con
 * un dato que la UI no sabe pintar.
 */
function validarAtributosCategoria(atributos, categoryId) {
  if (atributos === undefined || atributos === null || atributos === '') {
    return { value: null };
  }

  let parsed = atributos;
  if (typeof parsed === 'string') {
    // multipart/form-data manda todo como texto, así que el objeto llega
    // stringificado en las publicaciones con fotos.
    try {
      parsed = JSON.parse(parsed);
    } catch {
      return { error: 'atributos debe ser un JSON válido' };
    }
  }
  if (parsed === null) return { value: null };
  if (typeof parsed !== 'object' || Array.isArray(parsed)) {
    return { error: 'atributos debe ser un objeto de respuestas' };
  }

  const preguntas = preguntasDeCategoria(categoryId);
  const limpio = {};

  for (const pregunta of preguntas) {
    // El padre de un condicional siempre se resuelve antes que el hijo
    // porque en la config va declarado antes; así `limpio` ya tiene su valor
    // cuando toca evaluar el `showIf`.
    if (pregunta.showIf && limpio[pregunta.showIf.key] !== pregunta.showIf.equals) {
      continue;
    }

    const crudo = parsed[pregunta.key];
    const resultado = normalizarRespuesta(crudo, pregunta);
    if (resultado.error) return resultado;

    if (resultado.value === null) {
      if (pregunta.required) {
        return {
          error: `Responde "${pregunta.label}" para publicar.`,
          campo: pregunta.key,
        };
      }
      continue;
    }
    limpio[pregunta.key] = resultado.value;
  }

  return { value: Object.keys(limpio).length > 0 ? limpio : null };
}

/**
 * Normaliza UNA respuesta según el tipo de su pregunta. `{ value: null }`
 * significa "sin responder" (no es un error por sí solo; quien decide es el
 * `required` de la pregunta).
 */
function normalizarRespuesta(crudo, pregunta) {
  if (crudo === undefined || crudo === null || crudo === '') {
    return { value: null };
  }

  switch (pregunta.type) {
    case 'boolean': {
      // Los booleanos llegan como texto por multipart; 'false' es una cadena
      // no vacía y sería `true` con una conversión ingenua.
      if (typeof crudo === 'boolean') return { value: crudo };
      if (crudo === 'true') return { value: true };
      if (crudo === 'false') return { value: false };
      return { error: `"${pregunta.label}" debe responderse con sí o no.` };
    }

    case 'number': {
      const n = Number(crudo);
      if (!Number.isFinite(n)) {
        return { error: `"${pregunta.label}" debe ser un número.` };
      }
      return { value: n };
    }

    case 'select': {
      if (typeof crudo !== 'string' || !pregunta.options.includes(crudo)) {
        return { error: `Opción inválida en "${pregunta.label}": ${crudo}` };
      }
      return { value: crudo };
    }

    case 'multiselect': {
      let lista = crudo;
      if (typeof lista === 'string') {
        try {
          lista = JSON.parse(lista);
        } catch {
          return { error: `"${pregunta.label}" debe ser una lista.` };
        }
      }
      if (!Array.isArray(lista)) {
        return { error: `"${pregunta.label}" debe ser una lista.` };
      }
      const unicos = [...new Set(lista)];
      for (const opcion of unicos) {
        if (typeof opcion !== 'string' || !pregunta.options.includes(opcion)) {
          return { error: `Opción inválida en "${pregunta.label}": ${opcion}` };
        }
      }
      // Se reordenan según la config y no según lo que mandó el cliente, para
      // que dos productos con lo mismo incluido se lean igual en el detalle.
      const ordenados = pregunta.options.filter(o => unicos.includes(o));
      return { value: ordenados.length > 0 ? ordenados : null };
    }

    case 'text':
    default: {
      const texto = String(crudo).trim();
      if (!texto) return { value: null };
      if (texto.length > MAX_LARGO_TEXTO) {
        return {
          error: `"${pregunta.label}" no puede pasar de ${MAX_LARGO_TEXTO} caracteres.`,
        };
      }
      return { value: texto };
    }
  }
}

/**
 * Los 1-2 atributos que la tarjeta del listado muestra como badge, ya
 * resueltos a `{ key, label, value }` para que el cliente no tenga que
 * consultar el catálogo de preguntas al pintar una cuadrícula.
 *
 * Se calcula en el servidor y no en Flutter porque la tarjeta se pinta en
 * cuatro pantallas distintas (home, búsqueda, perfil de vendedor, carruseles
 * del detalle) y ninguna debería tener su propia opinión sobre cuál es el
 * dato importante de un producto de ropa.
 *
 * Los booleanos solo aparecen si son `true`: un badge "No acepta mascotas" en
 * una cuadrícula es ruido, y su ausencia no afirma lo contrario — para eso
 * está el detalle.
 */
function atributosDestacados(atributos, categoryId) {
  if (!atributos || typeof atributos !== 'object') return [];

  const keys = ATRIBUTOS_DESTACADOS[categoryId] || [];
  if (keys.length === 0) return [];

  const preguntas = preguntasDeCategoria(categoryId);
  const destacados = [];

  for (const key of keys) {
    if (destacados.length >= MAX_ATRIBUTOS_DESTACADOS) break;

    const pregunta = preguntas.find(p => p.key === key);
    const valor = atributos[key];
    if (!pregunta || valor === undefined || valor === null || valor === '') continue;

    if (pregunta.type === 'boolean') {
      if (valor !== true) continue;
      destacados.push({
        key,
        label: pregunta.label,
        value: pregunta.badgeLabel || pregunta.label,
      });
      continue;
    }
    if (Array.isArray(valor)) {
      if (valor.length === 0) continue;
      destacados.push({ key, label: pregunta.label, value: valor.join(' · ') });
      continue;
    }
    destacados.push({ key, label: pregunta.label, value: String(valor) });
  }

  return destacados;
}

module.exports = {
  validarAtributosCategoria,
  atributosDestacados,
  MAX_LARGO_TEXTO,
};
