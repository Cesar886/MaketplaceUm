// La config de preguntas dinámicas vive dos veces: aquí (autoridad, valida
// lo que entra) y en lib/constants/atributos_categoria.dart (decide lo que se
// pinta). Está duplicada a propósito — el formulario no puede esperar a la
// red para aparecer— pero una copia que se desincroniza produce el peor bug
// posible de este sistema: el usuario responde algo en la app y el servidor
// lo rechaza con "Opción inválida", o peor, la app deja de pintar una
// pregunta que el servidor sigue esperando.
//
// Este test lee el archivo Dart como texto y compara ambos catálogos.
// Parsear Dart con expresiones regulares es frágil en general; aquí funciona
// porque el archivo es una lista de constructores `const` con un formato
// fijo, y si alguien lo reescribe de otra forma este test falla ruidosamente
// en vez de aprobar en silencio (ver el chequeo de "se parsearon N
// categorías").

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const {
  ATRIBUTOS_GENERALES,
  ATRIBUTOS_POR_CATEGORIA,
} = require('./atributosCategoria');

const RUTA_DART = path.join(
  __dirname,
  '..', '..', '..',
  'lib', 'constants', 'atributos_categoria.dart',
);

const TIPOS_DART_A_JS = {
  'AtributoTipo.booleano': 'boolean',
  'AtributoTipo.seleccion': 'select',
  'AtributoTipo.seleccionMultiple': 'multiselect',
  'AtributoTipo.texto': 'text',
  'AtributoTipo.numero': 'number',
};

const fuenteDart = fs.readFileSync(RUTA_DART, 'utf8');

/** Extrae el contenido entre corchetes balanceados a partir de un índice. */
function bloqueDesde(texto, inicio) {
  let profundidad = 0;
  for (let i = inicio; i < texto.length; i++) {
    if (texto[i] === '[') profundidad++;
    else if (texto[i] === ']') {
      profundidad--;
      if (profundidad === 0) return texto.slice(inicio + 1, i);
    }
  }
  throw new Error('corchetes sin cerrar en el archivo Dart');
}

/** Lee un literal de string de Dart, deshaciendo el escape de \$. */
function literal(valor) {
  return valor.slice(1, -1).replace(/\\\$/g, '$');
}

/** Convierte un bloque de constructores AtributoPregunta a objetos planos. */
function parsearPreguntas(bloque) {
  const preguntas = [];
  const regex = /AtributoPregunta\(/g;
  let match;
  while ((match = regex.exec(bloque)) !== null) {
    // Los constructores no anidan otros AtributoPregunta, así que el paréntesis
    // que cierra es el primero que deja la profundidad en cero.
    let profundidad = 0;
    let fin = -1;
    for (let i = match.index + 'AtributoPregunta'.length; i < bloque.length; i++) {
      if (bloque[i] === '(') profundidad++;
      else if (bloque[i] === ')') {
        profundidad--;
        if (profundidad === 0) { fin = i; break; }
      }
    }
    assert.notStrictEqual(fin, -1, 'constructor Dart sin cerrar');
    const cuerpo = bloque.slice(match.index, fin);

    const leer = (campo) => {
      const m = cuerpo.match(new RegExp(`${campo}:\\s*('(?:[^'\\\\]|\\\\.)*')`));
      return m ? literal(m[1]) : undefined;
    };

    const tipoRaw = cuerpo.match(/tipo:\s*(AtributoTipo\.\w+)/);
    assert.ok(tipoRaw, `pregunta Dart sin tipo: ${cuerpo.slice(0, 60)}`);

    const optionsRaw = cuerpo.match(/options:\s*\[([\s\S]*?)\]/);
    const options = optionsRaw
      ? [...optionsRaw[1].matchAll(/'((?:[^'\\]|\\.)*)'/g)].map(m => literal(`'${m[1]}'`))
      : [];

    const showIfKey = leer('showIfKey');

    preguntas.push({
      key: leer('key'),
      label: leer('label'),
      type: TIPOS_DART_A_JS[tipoRaw[1]],
      options,
      required: /obligatoria:\s*true/.test(cuerpo),
      placeholder: leer('placeholder'),
      badgeLabel: leer('badgeLabel'),
      ...(showIfKey
        ? { showIf: { key: showIfKey, equals: /showIfEquals:\s*true/.test(cuerpo) } }
        : {}),
    });
  }
  return preguntas;
}

/** Normaliza una pregunta del catálogo JS a la misma forma que la parseada. */
function normalizarJs(p) {
  return {
    key: p.key,
    label: p.label,
    type: p.type,
    options: p.options || [],
    required: p.required,
    placeholder: p.placeholder,
    badgeLabel: p.badgeLabel,
    ...(p.showIf ? { showIf: { key: p.showIf.key, equals: p.showIf.equals } } : {}),
  };
}

// ─── Extracción del archivo Dart ─────────────────────────────

const generalesDart = parsearPreguntas(
  bloqueDesde(
    fuenteDart,
    fuenteDart.indexOf('[', fuenteDart.indexOf('atributosGenerales')),
  ),
);

const porCategoriaDart = {};
{
  const inicioMapa = fuenteDart.indexOf('atributosPorCategoria');
  const bloqueMapa = fuenteDart.slice(inicioMapa);
  const regexCategoria = /^ {2}'(\w+)': \[/gm;
  let match;
  while ((match = regexCategoria.exec(bloqueMapa)) !== null) {
    const inicioLista = bloqueMapa.indexOf('[', match.index);
    porCategoriaDart[match[1]] = parsearPreguntas(bloqueDesde(bloqueMapa, inicioLista));
  }
}

// ─── Comparación ─────────────────────────────────────────────

test('el parser sí encontró el catálogo Dart', () => {
  // Guarda contra el modo de fallo silencioso: si alguien reformatea el
  // archivo Dart y el parser deja de encontrar nada, sin esto los demás
  // tests compararían vacío contra vacío y pasarían.
  assert.ok(generalesDart.length > 0, 'no se parseó ninguna pregunta general');
  assert.ok(
    Object.keys(porCategoriaDart).length > 0,
    'no se parseó ninguna categoría',
  );
});

test('las preguntas generales son idénticas en Dart y en el servidor', () => {
  assert.deepStrictEqual(generalesDart, ATRIBUTOS_GENERALES.map(normalizarJs));
});

test('las categorías del catálogo son las mismas en ambos lados', () => {
  assert.deepStrictEqual(
    Object.keys(porCategoriaDart).sort(),
    Object.keys(ATRIBUTOS_POR_CATEGORIA).sort(),
  );
});

for (const categoria of Object.keys(ATRIBUTOS_POR_CATEGORIA)) {
  test(`las preguntas de ${categoria} son idénticas en Dart y en el servidor`, () => {
    assert.deepStrictEqual(
      porCategoriaDart[categoria],
      ATRIBUTOS_POR_CATEGORIA[categoria].map(normalizarJs),
      `la copia Dart de ${categoria} se desincronizó del servidor`,
    );
  });
}
