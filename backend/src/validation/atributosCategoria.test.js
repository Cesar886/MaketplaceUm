// Tests de la validación de las preguntas dinámicas por categoría.
//
// Lo que se protege aquí es el contrato de la columna `atributos_categoria`:
// que solo entren valores que alguna pantalla sepa pintar, y que los datos
// que llegan por multipart (todo como texto) se interpreten igual que los que
// llegan por JSON. Un booleano que se guarda como la cadena 'false' es
// verdadero para cualquier lector posterior, y ese bug no da la cara hasta
// que alguien ve "Sí acepta devoluciones" en un producto que dijo que no.

const test = require('node:test');
const assert = require('node:assert');

const {
  validarAtributosCategoria,
  atributosDestacados,
  MAX_LARGO_TEXTO,
} = require('./atributosCategoria');
const {
  ATRIBUTOS_GENERALES,
  ATRIBUTOS_POR_CATEGORIA,
  ATRIBUTOS_DESTACADOS,
  MAX_ATRIBUTOS_DESTACADOS,
  MAX_OPCIONES_CUSTOM,
  MAX_LARGO_OPCION_CUSTOM,
  GENERALES_EXCLUIDAS,
  preguntasDeCategoria,
} = require('../config/atributosCategoria');

// ─── Forma del catálogo ──────────────────────────────────────

const TIPOS_VALIDOS = ['boolean', 'select', 'multiselect', 'text', 'number'];

test('cada pregunta del catálogo está bien formada', () => {
  const todas = [
    ...ATRIBUTOS_GENERALES,
    ...Object.values(ATRIBUTOS_POR_CATEGORIA).flat(),
  ];
  for (const p of todas) {
    assert.ok(p.key, 'toda pregunta necesita key');
    assert.ok(p.label, `${p.key} necesita label`);
    assert.ok(TIPOS_VALIDOS.includes(p.type), `${p.key} tiene un tipo inválido: ${p.type}`);
    assert.strictEqual(typeof p.required, 'boolean', `${p.key} necesita required`);
    if (p.type === 'select' || p.type === 'multiselect') {
      assert.ok(Array.isArray(p.options) && p.options.length > 0, `${p.key} necesita options`);
    }
  }
});

test('las keys no se repiten dentro de una misma categoría', () => {
  for (const categoria of Object.keys(ATRIBUTOS_POR_CATEGORIA)) {
    const keys = preguntasDeCategoria(categoria).map(p => p.key);
    assert.strictEqual(
      new Set(keys).size,
      keys.length,
      `${categoria} tiene keys duplicadas — una pisaría a la otra al guardar`,
    );
  }
});

test('el padre de un condicional se declara antes que el hijo', () => {
  // La normalización resuelve las preguntas en orden y consulta el valor ya
  // aceptado del padre. Si el hijo fuera primero, su showIf leería undefined
  // y el campo condicional se descartaría siempre, en silencio.
  for (const categoria of Object.keys(ATRIBUTOS_POR_CATEGORIA)) {
    const preguntas = preguntasDeCategoria(categoria);
    preguntas.forEach((pregunta, i) => {
      if (!pregunta.showIf) return;
      const posPadre = preguntas.findIndex(p => p.key === pregunta.showIf.key);
      assert.ok(posPadre !== -1, `${pregunta.key} depende de una key inexistente`);
      assert.ok(posPadre < i, `${pregunta.key} se declara antes que su padre`);
    });
  }
});

// ─── Exclusiones de preguntas generales ──────────────────────

test('las keys excluidas existen entre las generales', () => {
  const generales = ATRIBUTOS_GENERALES.map(p => p.key);
  for (const [categoria, keys] of Object.entries(GENERALES_EXCLUIDAS)) {
    for (const key of keys) {
      assert.ok(
        generales.includes(key),
        `${categoria} excluye ${key}, que no es una pregunta general — probablemente se renombró`,
      );
    }
  }
});

test('cada categoría deja de ver las preguntas que no le aplican', () => {
  const keysDe = (c) => preguntasDeCategoria(c).map(p => p.key);

  // Hospedaje: no se entrega en un punto de encuentro.
  assert.ok(!keysDe('housing').includes('lugar_entrega'));

  // Comida: ni devoluciones, ni negociación, ni entrega genérica, ni garantía.
  for (const key of ['acepta_devoluciones', 'precio_negociable', 'lugar_entrega', 'tiene_garantia']) {
    assert.ok(!keysDe('food').includes(key), `food no debería preguntar ${key}`);
  }

  // Apuntes: solo se va la garantía; lo demás sigue igual.
  assert.ok(!keysDe('notes').includes('tiene_garantia'));
  assert.ok(keysDe('notes').includes('precio_negociable'));
  assert.ok(keysDe('notes').includes('lugar_entrega'));

  // Servicios: ni devoluciones ni lugar de entrega.
  assert.ok(!keysDe('services').includes('acepta_devoluciones'));
  assert.ok(!keysDe('services').includes('lugar_entrega'));
  assert.ok(keysDe('services').includes('precio_negociable'));

  // Una categoría sin exclusiones conserva las cuatro generales.
  assert.ok(keysDe('clothes').includes('lugar_entrega'));
});

test('excluir una pregunta se lleva sus campos condicionales', () => {
  // `duracion_garantia` no está listada en las exclusiones: cuelga de
  // `tiene_garantia` y tiene que caerse con ella, o quedaría una pregunta
  // suelta cuyo showIf ya nadie puede cumplir.
  for (const categoria of ['food', 'notes']) {
    assert.ok(
      !preguntasDeCategoria(categoria).some(p => p.key === 'duracion_garantia'),
      `${categoria} quedó con el campo condicional de la garantía`,
    );
  }
});

test('una respuesta a una pregunta excluida no se guarda', () => {
  // El caso real: un cliente viejo publicando comida sigue mandando las
  // cuatro generales. No es un error —se descarta en silencio— pero no puede
  // terminar en la base, o el detalle mostraría "No acepta devoluciones" en
  // unos tacos.
  const { value, error } = validarAtributosCategoria(
    {
      acepta_devoluciones: false,
      precio_negociable: true,
      lugar_entrega: 'Campus',
      tiene_garantia: true,
      duracion_garantia: '3 meses',
      opciones_veg: true,
    },
    'food',
  );
  assert.strictEqual(error, undefined);
  assert.deepStrictEqual(value, { opciones_veg: true });
});

test('los atributos destacados existen y no pasan del tope de la tarjeta', () => {
  for (const [categoria, keys] of Object.entries(ATRIBUTOS_DESTACADOS)) {
    assert.ok(keys.length <= MAX_ATRIBUTOS_DESTACADOS, `${categoria} destaca demasiados`);
    const disponibles = preguntasDeCategoria(categoria).map(p => p.key);
    for (const key of keys) {
      assert.ok(disponibles.includes(key), `${categoria} destaca una key que no tiene: ${key}`);
    }
  }
});

test('todo booleano destacado trae badgeLabel', () => {
  // Sin badgeLabel el badge diría "¿Aceptas mascotas?" dentro de la tarjeta.
  for (const [categoria, keys] of Object.entries(ATRIBUTOS_DESTACADOS)) {
    const preguntas = preguntasDeCategoria(categoria);
    for (const key of keys) {
      const pregunta = preguntas.find(p => p.key === key);
      if (pregunta.type !== 'boolean') continue;
      assert.ok(pregunta.badgeLabel, `${categoria}.${key} es booleano destacado y no tiene badgeLabel`);
    }
  }
});

// ─── Normalización ───────────────────────────────────────────

test('sin respuestas devuelve null, no un objeto vacío', () => {
  assert.strictEqual(validarAtributosCategoria(undefined, 'books').value, null);
  assert.strictEqual(validarAtributosCategoria(null, 'books').value, null);
  assert.strictEqual(validarAtributosCategoria('', 'books').value, null);
  assert.strictEqual(validarAtributosCategoria({}, 'books').value, null);
});

test('acepta el objeto stringificado que manda multipart/form-data', () => {
  const { value } = validarAtributosCategoria(
    JSON.stringify({ edicion: 'Original', precio_negociable: true }),
    'books',
  );
  assert.deepStrictEqual(value, { precio_negociable: true, edicion: 'Original' });
});

test('un JSON inválido se rechaza en vez de guardarse como texto', () => {
  const { error } = validarAtributosCategoria('{no soy json', 'books');
  assert.match(error, /JSON válido/);
});

test('un arreglo no pasa por objeto de respuestas', () => {
  const { error } = validarAtributosCategoria(['Original'], 'books');
  assert.match(error, /objeto de respuestas/);
});

test("la cadena 'false' se guarda como false, no como true", () => {
  // El bug clásico de multipart: 'false' es una cadena no vacía.
  const { value } = validarAtributosCategoria({ precio_negociable: 'false' }, 'books');
  assert.strictEqual(value.precio_negociable, false);
});

test("la cadena 'true' se guarda como booleano", () => {
  const { value } = validarAtributosCategoria({ precio_negociable: 'true' }, 'books');
  assert.strictEqual(value.precio_negociable, true);
});

test('un booleano con texto arbitrario se rechaza', () => {
  const { error } = validarAtributosCategoria({ precio_negociable: 'quizás' }, 'books');
  assert.match(error, /sí o no/);
});

test('un select fuera de sus options se rechaza', () => {
  const { error } = validarAtributosCategoria({ edicion: 'Pirata' }, 'books');
  assert.match(error, /Opción inválida/);
});

test('un select válido se conserva tal cual', () => {
  const { value } = validarAtributosCategoria({ estado_libro: 'Como nuevo' }, 'books');
  assert.strictEqual(value.estado_libro, 'Como nuevo');
});

test('las preguntas de otra categoría se descartan en silencio', () => {
  // Un cliente viejo puede mandar keys que ya no aplican; eso no debe
  // impedir publicar, solo no guardarse.
  const { value } = validarAtributosCategoria(
    { edicion: 'Original', talla: 'M', inventada: 'x' },
    'books',
  );
  assert.deepStrictEqual(value, { edicion: 'Original' });
});

test('el multiselect deduplica y respeta el orden del catálogo', () => {
  const { value } = validarAtributosCategoria(
    { incluye_renta: ['Internet', 'Luz', 'Internet'] },
    'housing',
  );
  assert.deepStrictEqual(value.incluye_renta, ['Luz', 'Internet']);
});

test('el multiselect acepta la lista stringificada', () => {
  const { value } = validarAtributosCategoria(
    { requisitos: JSON.stringify(['Contrato', 'Aval']) },
    'housing',
  );
  assert.deepStrictEqual(value.requisitos, ['Aval', 'Contrato']);
});

test('un multiselect sin allowCustom rechaza una opción inventada', (t) => {
  // Hoy las dos únicas preguntas de selección múltiple del catálogo aceptan
  // valores propios, así que la guarda se prueba con una pregunta postiza: es
  // el comportamiento por omisión y el que va a regir a la siguiente que se
  // agregue sin pensarlo.
  ATRIBUTOS_POR_CATEGORIA.other.push({
    key: 'multi_cerrado_de_prueba',
    label: 'Pregunta de prueba',
    type: 'multiselect',
    options: ['Uno', 'Dos'],
    required: false,
  });
  t.after(() => { ATRIBUTOS_POR_CATEGORIA.other.pop(); });

  const { error } = validarAtributosCategoria(
    { multi_cerrado_de_prueba: ['Tres'] },
    'other',
  );
  assert.match(error, /Opción inválida/);
});

test('un multiselect con allowCustom acepta valores escritos por el usuario', () => {
  const { value } = validarAtributosCategoria(
    { incluye_renta: ['Wifi 300mb', 'Luz'] },
    'housing',
  );
  // Las del catálogo primero y en el orden de la config; las propias después,
  // como se escribieron.
  assert.deepStrictEqual(value.incluye_renta, ['Luz', 'Wifi 300mb']);
});

test('los valores propios se recortan y deduplican', () => {
  const { value } = validarAtributosCategoria(
    { requisitos: ['  Sin fiadores  ', 'Sin fiadores', '   '] },
    'housing',
  );
  assert.deepStrictEqual(value.requisitos, ['Sin fiadores']);
});

test('un valor propio larguísimo se rechaza', () => {
  const { error } = validarAtributosCategoria(
    { incluye_renta: ['x'.repeat(MAX_LARGO_OPCION_CUSTOM + 1)] },
    'housing',
  );
  assert.match(error, new RegExp(`${MAX_LARGO_OPCION_CUSTOM} caracteres`));
});

test('el tope del valor propio se mide como lo cuenta quien escribe', () => {
  // El formulario corta por grafemas y el servidor tiene que coincidir, o
  // rechazaría al publicar un chip que dejó teclear entero. '🇲🇽 incluido'
  // son 11 caracteres para el usuario y 13 para String.length.
  const { value, error } = validarAtributosCategoria(
    { incluye_renta: ['🇲🇽 incluido'] },
    'housing',
  );
  assert.strictEqual(error, undefined);
  assert.deepStrictEqual(value.incluye_renta, ['🇲🇽 incluido']);
});

test('pasarse del tope de valores propios se rechaza', () => {
  const custom = Array.from({ length: MAX_OPCIONES_CUSTOM + 1 }, (_, i) => `Extra ${i}`);
  const { error } = validarAtributosCategoria(
    { incluye_renta: ['Luz', ...custom] },
    'housing',
  );
  assert.match(error, new RegExp(`hasta ${MAX_OPCIONES_CUSTOM} opciones propias`));
});

test('un multiselect vacío cuenta como sin responder', () => {
  const { value } = validarAtributosCategoria({ incluye_renta: [] }, 'housing');
  assert.strictEqual(value, null);
});

test('el texto se recorta y el que queda vacío no se guarda', () => {
  const { value } = validarAtributosCategoria({ talla: '  M  ', marca: '   ' }, 'clothes');
  assert.deepStrictEqual(value, { talla: 'M' });
});

test('un texto larguísimo se rechaza', () => {
  const { error } = validarAtributosCategoria(
    { talla: 'x'.repeat(MAX_LARGO_TEXTO + 1) },
    'clothes',
  );
  assert.match(error, /caracteres/);
});

test('el campo condicional se guarda si su padre está en true', () => {
  const { value } = validarAtributosCategoria(
    { tiene_garantia: true, duracion_garantia: '6 meses' },
    'books',
  );
  assert.deepStrictEqual(value, { tiene_garantia: true, duracion_garantia: '6 meses' });
});

test('el campo condicional se descarta si su padre está en false', () => {
  // El caso real: el usuario prendió el switch, escribió, y lo volvió a
  // apagar. El texto no puede sobrevivir a eso o el detalle mostraría una
  // garantía en un producto que dice no tenerla.
  const { value } = validarAtributosCategoria(
    { tiene_garantia: false, duracion_garantia: '6 meses' },
    'books',
  );
  assert.deepStrictEqual(value, { tiene_garantia: false });
});

test('el campo condicional se descarta si el padre no se respondió', () => {
  const { value } = validarAtributosCategoria({ duracion_garantia: '6 meses' }, 'books');
  assert.strictEqual(value, null);
});

test('los condicionales de electrónicos cuelgan de su propio padre', () => {
  const { value } = validarAtributosCategoria(
    {
      garantia_vigente: true,
      con_quien_garantia: 'Apple',
      tiene_desperfecto: false,
      descripcion_desperfecto: 'rayón',
    },
    'electronics',
  );
  assert.strictEqual(value.con_quien_garantia, 'Apple');
  assert.ok(!('descripcion_desperfecto' in value));
});

test('una categoría desconocida solo admite las preguntas generales', () => {
  // Un producto viejo con una categoría retirada del catálogo tiene que
  // seguir pudiendo guardarse.
  const { value } = validarAtributosCategoria(
    { precio_negociable: true, edicion: 'Original' },
    'categoria_que_ya_no_existe',
  );
  assert.deepStrictEqual(value, { precio_negociable: true });
});

test('una pregunta required sin responder se rechaza con su campo', () => {
  // Hoy no hay ninguna required en el catálogo; esto prueba la maquinaria
  // para poder activarlas sin descubrir después que nunca funcionó.
  const original = ATRIBUTOS_POR_CATEGORIA.books[0].required;
  ATRIBUTOS_POR_CATEGORIA.books[0].required = true;
  try {
    const { error, campo } = validarAtributosCategoria({}, 'books');
    assert.match(error, /Responde/);
    assert.strictEqual(campo, 'edicion');
  } finally {
    ATRIBUTOS_POR_CATEGORIA.books[0].required = original;
  }
});

// ─── Destacados para la tarjeta ──────────────────────────────

test('los destacados salen resueltos y en el orden de la config', () => {
  const destacados = atributosDestacados(
    { estado_ropa: 'Poco uso', talla: 'M', marca: 'Nike' },
    'clothes',
  );
  assert.deepStrictEqual(destacados.map(d => d.value), ['M', 'Poco uso']);
});

test('los destacados nunca pasan de dos', () => {
  const destacados = atributosDestacados(
    { talla: 'M', estado_ropa: 'Nueva', marca: 'Nike', cambio_talla: true },
    'clothes',
  );
  assert.strictEqual(destacados.length, MAX_ATRIBUTOS_DESTACADOS);
});

test('un booleano destacado en false no genera badge', () => {
  // "No acepta mascotas" en una cuadrícula es ruido; su ausencia tampoco
  // afirma lo contrario, para eso está el detalle.
  assert.deepStrictEqual(atributosDestacados({ acepta_mascotas: false }, 'housing'), []);
});

test('un booleano destacado en true usa su badgeLabel, no la pregunta', () => {
  const [badge] = atributosDestacados({ opciones_veg: true }, 'food');
  assert.strictEqual(badge.value, 'Opción veggie');
});

test('sin atributos no hay destacados', () => {
  assert.deepStrictEqual(atributosDestacados({}, 'clothes'), []);
  assert.deepStrictEqual(atributosDestacados(null, 'clothes'), []);
});

test('una categoría sin destacados configurados devuelve vacío', () => {
  assert.deepStrictEqual(atributosDestacados({ estado_general: 'Bien' }, 'other'), []);
});
