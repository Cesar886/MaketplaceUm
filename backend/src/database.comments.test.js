// Tests de la capa de datos de comentarios.
//
// Los dos puntos que de verdad se pueden romper en silencio:
//
//  1. La paginación por keyset. Se eligió sobre OFFSET porque el hilo recibe
//     inserciones en el tope por Socket.IO mientras el usuario pagina; si el
//     cursor estuviera mal, el síntoma sería una fila repetida o una fila
//     saltada, no un error. Por eso hay un test que inserta EN MEDIO de la
//     paginación.
//  2. El feed del perfil, que filtra por dueño del producto y no por autor
//     del comentario. Invertir esos dos ids compila, corre, y muestra los
//     comentarios equivocados como si fueran prueba social.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Debe fijarse antes de requerir database.js: la ruta se resuelve al importar.
const tmpDb = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-comments-')),
  'test.db',
);
process.env.MERCADITO_DB_PATH = tmpDb;

const db = require('./database');
db.initDatabase();
const raw = db.getDb();

function sembrarVendedor(id, extra = {}) {
  raw.prepare(`
    INSERT OR REPLACE INTO sellers
      (id, name, avatarInitials, major, tipo_cuenta, carrera, tipo_verificacion, verified, phone, email)
    VALUES (@id, @name, @avatarInitials, @major, @tipo_cuenta, @carrera, @tipo_verificacion, @verified, @phone, @email)
  `).run({
    id,
    name: `Vendedor ${id}`,
    avatarInitials: 'VV',
    major: 'Estudiante',
    tipo_cuenta: 'estudiante',
    carrera: 'Ingeniería en Sistemas',
    tipo_verificacion: 'estudiante',
    verified: 1,
    phone: '+528112345678',
    email: `${id}@um.edu.mx`,
    ...extra,
  });
}

function sembrarProducto(id, sellerId, titulo = 'Producto', imagenes = '[]') {
  raw.prepare(
    "INSERT OR REPLACE INTO products (id, title, price, seller, images) VALUES (?, ?, '0', ?, ?)",
  ).run(id, titulo, sellerId, imagenes);
}

/**
 * Inserta un comentario con un created_at explícito. Necesario porque
 * datetime('now') tiene resolución de un segundo: varios comentarios
 * seguidos caerían en el mismo instante y el orden dependería del desempate
 * por id, que es justo lo que estos tests quieren controlar.
 */
function sembrarComentario(id, productId, userId, texto, createdAt) {
  raw.prepare(
    'INSERT INTO product_comments (id, product_id, user_id, texto, created_at) VALUES (?, ?, ?, ?, ?)',
  ).run(id, productId, userId, texto, createdAt);
}

test('createProductComment devuelve el comentario con su autor resuelto', () => {
  sembrarVendedor('u_autor');
  sembrarVendedor('u_dueno');
  sembrarProducto('p_basico', 'u_dueno');

  const c = db.createProductComment('cmt_1', 'p_basico', 'u_autor', 'Me interesa');

  assert.strictEqual(c.texto, 'Me interesa');
  assert.strictEqual(c.productId, 'p_basico');
  assert.strictEqual(c.author.id, 'u_autor');
  assert.strictEqual(c.author.carrera, 'Ingeniería en Sistemas');
  assert.strictEqual(c.author.tipoVerificacion, 'estudiante');
});

test('el autor NO incluye teléfono ni correo', () => {
  // Un hilo de comentarios es contenido público; si arrastrara el contacto
  // del autor, cada publicación sería un directorio de teléfonos.
  const { comments } = db.getProductComments('p_basico');
  const serializado = JSON.stringify(comments);

  assert.ok(!serializado.includes('+528112345678'), 'se filtró el teléfono');
  assert.ok(!serializado.includes('@um.edu.mx'), 'se filtró el correo');
  assert.strictEqual(comments[0].author.phone, undefined);
  assert.strictEqual(comments[0].author.email, undefined);
});

test('createdAt sale como ISO-8601 con Z explícita', () => {
  // Sin la Z, DateTime.parse de Dart lee el valor UTC como hora local y el
  // "hace 2 h" queda corrido por el offset del dispositivo.
  const { comments } = db.getProductComments('p_basico');
  assert.match(comments[0].createdAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
});

test('el hilo viene del más reciente al más antiguo', () => {
  sembrarVendedor('u_hilo');
  sembrarProducto('p_orden', 'u_dueno');
  sembrarComentario('cmt_o1', 'p_orden', 'u_hilo', 'primero', '2026-01-01 10:00:00');
  sembrarComentario('cmt_o2', 'p_orden', 'u_hilo', 'segundo', '2026-01-01 11:00:00');
  sembrarComentario('cmt_o3', 'p_orden', 'u_hilo', 'tercero', '2026-01-01 12:00:00');

  const { comments } = db.getProductComments('p_orden');
  assert.deepStrictEqual(
    comments.map(c => c.texto),
    ['tercero', 'segundo', 'primero'],
  );
});

test('los borrados no aparecen ni cuentan en el total', () => {
  db.softDeleteProductComment('cmt_o2', 'u_hilo');

  const { comments } = db.getProductComments('p_orden');
  assert.deepStrictEqual(comments.map(c => c.texto), ['tercero', 'primero']);
  assert.strictEqual(db.countProductComments('p_orden'), 2);

  // La fila sigue ahí: el borrado es lógico, no físico.
  const fila = db.getProductCommentRow('cmt_o2');
  assert.ok(fila, 'la fila se borró físicamente');
  assert.ok(fila.deleted_at);
  assert.strictEqual(fila.deleted_by, 'u_hilo');
});

test('borrar dos veces devuelve false la segunda', () => {
  // La ruta se apoya en esto para no emitir el evento de Socket.IO dos veces
  // ante un doble tap.
  assert.strictEqual(db.softDeleteProductComment('cmt_o2', 'u_hilo'), false);
});

test('la paginación por keyset recorre todo sin repetir ni saltar', () => {
  sembrarVendedor('u_pag');
  sembrarProducto('p_pag', 'u_dueno');
  for (let i = 1; i <= 25; i++) {
    const minuto = String(i).padStart(2, '0');
    sembrarComentario(`cmt_p${minuto}`, 'p_pag', 'u_pag', `c${i}`, `2026-02-01 10:${minuto}:00`);
  }

  const vistos = [];
  let cursor = null;
  let paginas = 0;
  do {
    const r = db.getProductComments('p_pag', { limit: 10, cursor });
    vistos.push(...r.comments.map(c => c.texto));
    cursor = r.nextCursor;
    paginas++;
    assert.ok(paginas < 10, 'la paginación no terminó');
  } while (cursor);

  assert.strictEqual(vistos.length, 25);
  assert.strictEqual(new Set(vistos).size, 25, 'hubo filas repetidas');
  assert.strictEqual(vistos[0], 'c25');
  assert.strictEqual(vistos[24], 'c1');
});

test('un comentario nuevo en el tope no descoloca la paginación en curso', () => {
  // Este es el motivo de usar keyset y no OFFSET: con OFFSET, insertar en el
  // tope entre página y página recorre la ventana y repite la última fila.
  const primera = db.getProductComments('p_pag', { limit: 10 });
  assert.strictEqual(primera.comments[0].texto, 'c25');

  sembrarComentario('cmt_intruso', 'p_pag', 'u_pag', 'recien llegado', '2026-02-01 23:59:00');

  const segunda = db.getProductComments('p_pag', { limit: 10, cursor: primera.nextCursor });
  const textos = segunda.comments.map(c => c.texto);

  assert.ok(!textos.includes('recien llegado'), 'el comentario nuevo se coló en la página vieja');
  assert.ok(!textos.includes('c16'), 'se repitió la última fila de la página anterior');
  assert.strictEqual(textos[0], 'c15');
});

test('empatar en created_at no rompe el orden ni repite filas', () => {
  // datetime('now') tiene resolución de un segundo, así que dos comentarios
  // simultáneos con el mismo timestamp son un caso real, no teórico. El
  // desempate por id es lo único que evita el bucle infinito.
  sembrarVendedor('u_empate');
  sembrarProducto('p_empate', 'u_dueno');
  sembrarComentario('cmt_e1', 'p_empate', 'u_empate', 'a', '2026-03-01 10:00:00');
  sembrarComentario('cmt_e2', 'p_empate', 'u_empate', 'b', '2026-03-01 10:00:00');
  sembrarComentario('cmt_e3', 'p_empate', 'u_empate', 'c', '2026-03-01 10:00:00');

  const vistos = [];
  let cursor = null;
  let vueltas = 0;
  do {
    const r = db.getProductComments('p_empate', { limit: 2, cursor });
    vistos.push(...r.comments.map(c => c.texto));
    cursor = r.nextCursor;
    assert.ok(++vueltas < 6, 'la paginación entró en bucle con timestamps iguales');
  } while (cursor);

  assert.strictEqual(new Set(vistos).size, 3);
});

test('el límite de página tiene tope duro', () => {
  const r = db.getProductComments('p_pag', { limit: 9999 });
  assert.ok(r.comments.length <= db.COMENTARIOS_MAX_POR_PAGINA);
});

test('un limit inválido cae al default en vez de reventar', () => {
  for (const limite of ['abc', '', '0', '-5', null, undefined]) {
    const r = db.getProductComments('p_pag', { limit: limite });
    assert.strictEqual(r.comments.length, db.COMENTARIOS_POR_PAGINA);
  }
});

test('un cursor corrupto se ignora y devuelve la primera página', () => {
  const r = db.getProductComments('p_pag', { cursor: 'basura-sin-separador' });
  assert.strictEqual(r.comments[0].texto, 'recien llegado');
});

test('el perfil trae lo que OTROS comentaron en MIS publicaciones', () => {
  sembrarVendedor('u_tienda');
  sembrarVendedor('u_cliente');
  sembrarProducto('p_mio', 'u_tienda', 'Audífonos Sony', '["/uploads/sony.webp"]');
  // Producto ajeno donde u_tienda comentó: NO debe salir en su perfil.
  sembrarProducto('p_ajeno', 'u_cliente', 'Bici');

  sembrarComentario('cmt_r1', 'p_mio', 'u_cliente', 'Excelente vendedor', '2026-04-01 10:00:00');
  sembrarComentario('cmt_r2', 'p_ajeno', 'u_tienda', 'Yo comenté esto', '2026-04-01 11:00:00');

  const { comments } = db.getCommentsReceivedBySeller('u_tienda');

  assert.strictEqual(comments.length, 1);
  assert.strictEqual(comments[0].texto, 'Excelente vendedor');
  assert.strictEqual(comments[0].author.id, 'u_cliente');
  assert.strictEqual(db.countCommentsReceivedBySeller('u_tienda'), 1);
});

test('el perfil adjunta título y primera foto del producto comentado', () => {
  const { comments } = db.getCommentsReceivedBySeller('u_tienda');

  assert.strictEqual(comments[0].product.id, 'p_mio');
  assert.strictEqual(comments[0].product.title, 'Audífonos Sony');
  assert.strictEqual(comments[0].product.image, '/uploads/sony.webp');
});

test('un producto sin fotos deja la miniatura en null en vez de fallar', () => {
  sembrarProducto('p_sinfoto', 'u_tienda', 'Sin foto', '[]');
  sembrarComentario('cmt_r3', 'p_sinfoto', 'u_cliente', 'sin foto', '2026-04-02 10:00:00');

  const { comments } = db.getCommentsReceivedBySeller('u_tienda');
  assert.strictEqual(comments[0].product.image, null);
});

test('un images corrupto no tumba la pestaña entera del perfil', () => {
  sembrarProducto('p_corrupto', 'u_tienda', 'JSON roto', 'esto no es json');
  sembrarComentario('cmt_r4', 'p_corrupto', 'u_cliente', 'roto', '2026-04-03 10:00:00');

  const { comments } = db.getCommentsReceivedBySeller('u_tienda');
  assert.strictEqual(comments[0].product.image, null);
  assert.strictEqual(comments[0].texto, 'roto');
});

test('el perfil no cuenta los comentarios que el dueño se dejó a sí mismo', () => {
  sembrarComentario('cmt_auto', 'p_mio', 'u_tienda', 'Soy buenísimo', '2026-04-04 10:00:00');

  const { comments } = db.getCommentsReceivedBySeller('u_tienda');
  assert.ok(!comments.some(c => c.texto === 'Soy buenísimo'));
});

test('segundosDesdeUltimoComentario es null si el usuario nunca comentó', () => {
  assert.strictEqual(db.segundosDesdeUltimoComentario('u_jamas'), null);
});

test('segundosDesdeUltimoComentario mide contra el reloj UTC de SQLite', () => {
  // El proceso corre con TZ=America/Monterrey (index.js) y created_at se
  // guarda en UTC: restar contra un `new Date()` de Node daría seis horas de
  // diferencia y el rate limit no frenaría absolutamente nada.
  sembrarVendedor('u_reciente');
  sembrarProducto('p_reciente', 'u_dueno');
  db.createProductComment('cmt_ahora', 'p_reciente', 'u_reciente', 'ahorita');

  const segundos = db.segundosDesdeUltimoComentario('u_reciente');
  assert.ok(segundos !== null && segundos >= 0 && segundos < 5, `dio ${segundos}s`);
});

test('el CHECK de la tabla rechaza un texto de más de 500 caracteres', () => {
  // Segunda línea de defensa: si una ruta futura olvida sanear, la base para.
  assert.throws(() => {
    sembrarComentario('cmt_largo', 'p_basico', 'u_autor', 'x'.repeat(501), '2026-05-01 10:00:00');
  }, /CHECK constraint failed/);
});

test('borrar el producto arrastra sus comentarios (ON DELETE CASCADE)', () => {
  sembrarProducto('p_efimero', 'u_dueno');
  sembrarComentario('cmt_ef', 'p_efimero', 'u_autor', 'adiós', '2026-06-01 10:00:00');
  assert.strictEqual(db.countProductComments('p_efimero'), 1);

  raw.prepare('DELETE FROM products WHERE id = ?').run('p_efimero');

  assert.strictEqual(db.countProductComments('p_efimero'), 0);
  assert.strictEqual(db.getProductCommentRow('cmt_ef'), undefined);
});
