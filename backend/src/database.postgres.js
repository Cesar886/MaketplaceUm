'use strict';

const crypto = require('crypto');
const {
  database: db,
  initPostgres,
  closePostgres
} = require('./db/postgres');
async function initDatabase() {
  await initPostgres();
  await refrescarCuentasDueno();
  const purgadas = await purgeOldSearchQueries();
  if (purgadas > 0) {
    console.log(`🧹 ${purgadas} búsquedas antiguas purgadas del historial`);
  }
  await recomputeAllSellerRatings();
  console.log('🐘 Base de datos PostgreSQL inicializada');
  return db;
}
async function closeDatabase() {
  await closePostgres();
}

// ─── Presencia ───────────────────────────────────────────────

/**
 * Marca cuándo se desconectó el usuario. Se llama una sola vez por sesión
 * (al cerrarse su último socket), no periódicamente.
 */
async function setUltimaActividad(userId, iso) {
  await getDb().prepare('UPDATE sellers SET last_active = ? WHERE id = ?').run(iso, userId);
}

/** Enciende o apaga "mostrar mi estado en línea" para el usuario. */
async function setMostrarEstadoEnLinea(userId, comparte) {
  await getDb().prepare('UPDATE sellers SET show_online_status = ? WHERE id = ?').run(comparte ? 1 : 0, userId);
}

/**
 * Datos de presencia persistidos de un usuario.
 *
 * Un id desconocido devuelve `comparteEstado: false` en vez de lanzar: la
 * lista de chats puede traer conversaciones con cuentas ya borradas, y ahí
 * lo correcto es no mostrar nada, no reventar la pantalla.
 *
 * @returns {{lastActive: string|null, comparteEstado: boolean}}
 */
async function getPresencia(userId) {
  const fila = await getDb().prepare('SELECT last_active, show_online_status FROM sellers WHERE id = ?').get(userId);
  if (!fila) return {
    lastActive: null,
    comparteEstado: false
  };
  return {
    lastActive: fila.last_active || null,
    comparteEstado: fila.show_online_status !== 0
  };
}

/**
 * Retira un método de pago del catálogo en todos los sitios donde quedó
 * guardado como JSON. Idempotente: correrla de nuevo no cambia nada.
 *
 * El "qué hacer si queda vacío" NO es el mismo en las tres tablas, y es todo
 * el motivo de que esto sea una función y no un UPDATE:
 *
 * - `sellers.paymentMethods` exige al menos un método. Dejarlo en [] rompe
 *   el perfil del vendedor y le bloquea guardar cualquier cambio hasta que
 *   se dé cuenta, así que cae a ['efectivo'], que es el mínimo universal.
 * - En `products` y `wanted_posts`, NULL significa "hereda del perfil". Ahí
 *   quedarse vacío sí tiene una respuesta correcta y no destructiva: volver
 *   a NULL y heredar.
 *
 * @returns {{sellers:number, products:number, wanted:number}} filas tocadas
 */
async function purgarMetodoDePago(conexion, metodo) {
  const tocadas = {
    sellers: 0,
    products: 0,
    wanted: 0
  };
  const purgarTabla = async (tabla, columnaId, siQuedaVacio) => {
    const existe = await conexion.prepare(`SELECT name FROM sqlite_master WHERE type='table' AND name=?`).get(tabla);
    if (!existe) return 0;
    const filas = await conexion.prepare(`SELECT ${columnaId} AS id, paymentMethods FROM ${tabla}
       WHERE paymentMethods IS NOT NULL AND paymentMethods LIKE ?`).all(`%${metodo}%`);
    const actualizar = conexion.prepare(`UPDATE ${tabla} SET paymentMethods = ? WHERE ${columnaId} = ?`);
    let n = 0;
    for (const fila of filas) {
      let lista;
      try {
        lista = JSON.parse(fila.paymentMethods);
      } catch {
        continue; // JSON corrupto: no es asunto de esta migración tocarlo.
      }
      if (!Array.isArray(lista) || !lista.includes(metodo)) continue;
      const restantes = lista.filter(m => m !== metodo);
      const valor = restantes.length > 0 ? JSON.stringify(restantes) : siQuedaVacio;
      await actualizar.run(valor, fila.id);
      n++;
    }
    return n;
  };
  await conexion.transaction(async () => {
    tocadas.sellers = await purgarTabla('sellers', 'id', JSON.stringify(['efectivo']));
    tocadas.products = await purgarTabla('products', 'id', null);
    tocadas.wanted = await purgarTabla('wanted_posts', 'id', null);
  })();
  if (tocadas.sellers || tocadas.products || tocadas.wanted) {
    console.log(`🔄 Método de pago '${metodo}' retirado: ${tocadas.sellers} vendedores, ` + `${tocadas.products} productos, ${tocadas.wanted} búsquedas`);
  }
  return tocadas;
}

// ─── helpers para convertir filas a objetos y viceversa ─────

function rowToProduct(row) {
  if (!row) return null;
  const priceNum = row.priceNum !== null && row.priceNum !== undefined ? row.priceNum : parseFloat(String(row.price || '0').replace(/[^0-9.]/g, '')) || 0;
  return {
    id: row.id,
    title: row.title,
    price: priceNum,
    category: row.category,
    description: row.description,
    publishedAgo: row.publishedAgo,
    seller: row.seller,
    images: JSON.parse(row.images || '[]'),
    imageIcon: row.imageIcon || null,
    imageColor: row.imageColor || '#607D8B',
    previousPrice: row.previousPrice || null,
    discountLabel: row.discountLabel || null,
    isFeatured: !!row.isFeatured,
    isOffer: !!row.isOffer,
    isFavorite: !!row.isFavorite,
    status: row.status || null,
    manual_status: row.manual_status || null,
    offerExpiresAt: row.offerExpiresAt || null,
    extras: JSON.parse(row.extras || '[]'),
    stock_quantity: row.stock_quantity ?? null,
    stock_reset_daily: !!row.stock_reset_daily,
    stock_initial: row.stock_initial ?? null,
    stock_updated_at: row.stock_updated_at || null,
    created_at: row.created_at || null,
    expiresAt: row.expires_at || null,
    moderationStatus: row.moderation_status || 'visible',
    availableDays: JSON.parse(row.availableDays || '[]'),
    updated_at: row.updated_at || null,
    locationLat: row.location_lat ?? null,
    locationLng: row.location_lng ?? null,
    paymentMethods: row.paymentMethods ? JSON.parse(row.paymentMethods) : null,
    views: row.views ?? 0,
    // Respuestas a las preguntas dinámicas de la categoría. Siempre un
    // objeto (nunca null) para que el cliente y las rutas puedan leerlo sin
    // chequeo previo; los productos anteriores a la migración 36 lo tienen
    // vacío. Un JSON corrupto se degrada a {} en vez de tumbar el arranque:
    // getAllProducts corre al importar data.js y una sola fila mala dejaría
    // el servidor entero sin levantar.
    atributos: parseAtributosCategoria(row.atributos_categoria)
  };
}

/** Lectura tolerante de la columna JSON de atributos. Ver rowToProduct. */
function parseAtributosCategoria(raw) {
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}
function productToRow(product) {
  const priceNum = typeof product.price === 'number' ? product.price : parseFloat(String(product.price || '0').replace(/[^0-9.]/g, '')) || 0;
  return {
    id: product.id,
    title: product.title,
    price: String(priceNum),
    priceNum: priceNum,
    category: product.category || null,
    description: product.description || null,
    publishedAgo: product.publishedAgo || null,
    seller: product.seller || null,
    images: JSON.stringify(product.images || []),
    imageIcon: product.imageIcon || null,
    imageColor: product.imageColor || null,
    previousPrice: product.previousPrice || null,
    discountLabel: product.discountLabel || null,
    isFeatured: product.isFeatured ? 1 : 0,
    isOffer: product.isOffer ? 1 : 0,
    isFavorite: product.isFavorite ? 1 : 0,
    status: product.status || null,
    manual_status: product.manual_status || null,
    offerExpiresAt: product.offerExpiresAt || null,
    extras: JSON.stringify(product.extras || []),
    stock_quantity: product.stock_quantity ?? null,
    stock_reset_daily: product.stock_reset_daily ? 1 : 0,
    stock_initial: product.stock_initial ?? null,
    stock_updated_at: product.stock_updated_at || null,
    created_at: product.created_at || new Date().toISOString().replace('T', ' ').slice(0, 19),
    availableDays: JSON.stringify(product.availableDays || []),
    updated_at: product.updated_at || null,
    location_lat: product.locationLat ?? null,
    location_lng: product.locationLng ?? null,
    paymentMethods: product.paymentMethods ? JSON.stringify(product.paymentMethods) : null,
    expires_at: product.expiresAt || null,
    // Se guarda NULL, no '{}', cuando no hay ninguna respuesta: así la
    // columna distingue "sin contestar" de "contestó y quedó vacío" sin
    // ocupar espacio en cada fila del histórico.
    atributos_categoria: product.atributos && Object.keys(product.atributos).length > 0 ? JSON.stringify(product.atributos) : null
  };
}
function rowToWantedPost(row) {
  if (!row) return null;
  return {
    id: row.id,
    userId: row.user_id,
    title: row.title,
    description: row.description || null,
    categoryId: row.category_id,
    type: row.type,
    priceMin: row.price_min ?? null,
    priceMax: row.price_max ?? null,
    status: row.status,
    resolvedWithUserId: row.resolved_with_user_id || null,
    createdAt: row.created_at,
    resolvedAt: row.resolved_at || null,
    updatedAt: row.updated_at || null,
    locationLat: row.location_lat ?? null,
    locationLng: row.location_lng ?? null,
    paymentMethods: row.paymentMethods ? JSON.parse(row.paymentMethods) : null,
    views: row.views ?? 0,
    expiresAt: row.expires_at || null,
    moderationStatus: row.moderation_status || 'visible'
  };
}

// ─── API de datos ──────────────────────────────────────────

async function getCategories() {
  return await db.prepare('SELECT * FROM categories ORDER BY id').all();
}

// Cuentas propias del admin: siempre se ven con todas las insignias
// desbloqueadas, sin que ningún flujo normal (revocar verificación, perder
// racha, etc.) se las pueda quitar — es un caso hardcodeado, no una fila que
// se pueda editar por error.
//
// La lista mezcla dos clases de correo A PROPÓSITO, porque son columnas
// distintas y la primera versión de esto solo miraba una:
//
//   - Correos de LOGIN (`sellers.email`): el de la cuenta de Google con la
//     que se entra a la app.
//   - Correo INSTITUCIONAL (`verificaciones.correo_institucional`): el del
//     trámite de verificación.
//
// El intento anterior comparaba `sellers.email` contra el institucional, y
// por eso no se activó nunca: el flujo de verificación (`verificacion.js`)
// jamás escribe el correo institucional en `sellers.email` — ahí vive el de
// Google. La condición era falsa para todas las filas de la base.
const CORREOS_DUENO = new Set(['cesar4herrera@gmail.com', '1220326@alumno.um.edu.mx', 'cesar8herrera@gmail.com']);
function normalizarCorreo(email) {
  return (email || '').trim().toLowerCase();
}
function esCuentaTodosLosBadges(email) {
  return CORREOS_DUENO.has(normalizarCorreo(email));
}

// Ids de usuario resueltos de una vez, no una consulta por fila.
//
// `rowToSeller` corre sobre CADA vendedor de una respuesta, así que mirar la
// tabla `verificaciones` ahí dentro sería una consulta por fila. En vez de
// eso se resuelve el conjunto entero con una sola consulta y se guarda.
//
// El caché se refresca por tiempo (y a mano tras una verificación) porque el
// conjunto puede crecer sin reiniciar el proceso: basta con que una de estas
// cuentas complete el trámite institucional.
let _cuentasDuenoIds = null;
let _cuentasDuenoAt = 0;
const CUENTAS_DUENO_TTL_MS = 60_000;

/** Recalcula ya el conjunto de cuentas dueño. */
async function refrescarCuentasDueno() {
  const correos = [...CORREOS_DUENO];
  const marcadores = correos.map(() => '?').join(', ');
  const filas = await db.prepare(`SELECT id FROM sellers WHERE lower(trim(email)) IN (${marcadores})
       UNION
       SELECT usuario_id AS id FROM verificaciones
        WHERE estado = 'verificado'
          AND lower(trim(correo_institucional)) IN (${marcadores})`).all(...correos, ...correos);
  _cuentasDuenoIds = new Set(filas.map(f => f.id));
  _cuentasDuenoAt = Date.now();
  return _cuentasDuenoIds;
}

/** Fuerza NULL como método de pago para las cuentas oficiales del dueño. */
async function anularMetodosPagoCuentasDueno() {
  const ids = [...(await refrescarCuentasDueno())];
  if (ids.length === 0) return 0;
  const marcadores = ids.map(() => '?').join(', ');
  return (await db.prepare(`UPDATE sellers SET paymentMethods = NULL
     WHERE id IN (${marcadores}) AND paymentMethods IS NOT NULL`).run(...ids)).changes;
}

/**
 * ¿`usuarioId` es una cuenta del dueño?
 *
 * Es la única puerta: la usan `rowToSeller`, el endpoint de perfil, el chat y
 * los autores de comentarios y preguntas. Antes cada uno leía `row.email` o
 * `row.socio_fundador` por su cuenta y tres de ellos ni se enteraban de la
 * regla, así que la palomita aparecía en el perfil y no en el chat.
 */
function parsearInsigniasOcultas(valor) {
  if (!valor) return [];
  try {
    const lista = JSON.parse(valor);
    return Array.isArray(lista) ? lista.filter(c => typeof c === 'string') : [];
  } catch {
    return [];
  }
}
function esUsuarioTodosLosBadges(usuarioId) {
  if (!usuarioId) return false;
  if (!_cuentasDuenoIds || Date.now() - _cuentasDuenoAt > CUENTAS_DUENO_TTL_MS) {
    _cuentasDuenoAt = Date.now();
    void refrescarCuentasDueno().catch(error => console.error('[db] no se pudo refrescar el caché de cuentas oficiales:', error.message));
  }
  return _cuentasDuenoIds ? _cuentasDuenoIds.has(usuarioId) : false;
}
function rowToSeller(row) {
  if (!row) return null;
  const todosLosBadges = esUsuarioTodosLosBadges(row.id) || esCuentaTodosLosBadges(row.email);
  const tipoCuenta = row.tipo_cuenta || 'particular';
  return {
    id: row.id,
    name: row.name,
    // El teléfono sí se expone públicamente (a diferencia del email): es lo
    // que permite el botón "Contactar por WhatsApp" sin necesidad de login.
    // Un vendedor que publica un producto implícitamente acepta que lo
    // contacten por ese medio.
    phone: row.phone || null,
    avatarInitials: row.avatarInitials || '',
    major: row.major || '',
    isBusiness: !!row.isBusiness,
    logoUrl: row.logoUrl || null,
    rating: row.rating ?? 0,
    reviews: row.reviews ?? 0,
    verified: tipoCuenta !== 'particular' && (todosLosBadges || !!row.verified),
    // Insignia verde otorgada a mano por el admin. Separada de `verified` a
    // propósito: no la gana ningún dato ni trámite de la cuenta, así que no
    // comparte puerta con la verificación. Ver
    // scripts/otorgar-socio-fundador.js.
    socioFundador: todosLosBadges || !!row.socio_fundador,
    // Determina el color/etiqueta de la insignia de verificación en la app.
    // 'particular' es lo que la UI llama "externo".
    tipoCuenta,
    // Solo se llena para cuentas de estudiante verificadas (ver
    // routes/verificacion.js). El perfil cae a "Estudiante" cuando es null.
    carrera: row.carrera || null,
    // 'estudiante' | 'empleado': distingue al alumno del personal de la
    // universidad, que comparten tipo_cuenta='estudiante'. El perfil muestra
    // "Personal UM" cuando vale 'empleado'.
    tipoVerificacion: row.tipo_verificacion || null,
    businessDescription: row.businessDescription || null,
    businessCategory: row.businessCategory || null,
    businessHours: JSON.parse(row.businessHours || '{}'),
    locationLat: row.location_lat ?? null,
    locationLng: row.location_lng ?? null,
    paymentMethods: JSON.parse(row.paymentMethods || '[]'),
    // ID del swatch elegido, no un hex — ver migración 27.
    colorAcento: row.colorAcento || null,
    productoFijadoId: row.producto_fijado_id || null,
    // Claves de las insignias que su dueño decidió no mostrar. NULL en la
    // columna = nunca tocó el ajuste = se muestran todas (migración 43).
    // Un JSON corrupto se trata como "ninguna oculta" en vez de reventar el
    // perfil entero: es una preferencia de presentación, no un dato crítico.
    insigniasOcultas: parsearInsigniasOcultas(row.insignias_ocultas),
    // Mediana en minutos entre el mensaje de un comprador y la respuesta del
    // vendedor. null = todavía no hay respuestas suficientes para calcularla.
    medianResponseMinutes: row.median_response_minutes ?? null,
    facebookUrl: row.facebook_url || null,
    instagramUrl: row.instagram_url || null,
    whatsappNumber: row.whatsapp_number || null,
    tiktokUrl: row.tiktok_url || null,
    twitterUrl: row.twitter_url || null,
    // Fecha de alta de la cuenta. Ver migración 42: en cuentas creadas antes
    // de esa migración no es la fecha real de alta, es la fecha en la que se
    // corrió la migración.
    createdAt: row.created_at
  };
}

// Cuentas oficiales de soporte: a donde manda el botón "Reportar un
// problema" del perfil. Mismos dos correos que `CORREOS_DUENO` (son las
// cuentas de Daniel), pero es una lista aparte a propósito: una cosa es
// "quién tiene todas las insignias" y otra "a quién se le reportan
// problemas" — hoy coinciden, pero no tienen por qué seguir coincidiendo.
const CORREOS_SOPORTE = ['cesar8herrera@gmail.com', 'cesar4herrera@gmail.com'];

/** Las cuentas oficiales de soporte, en el orden de `CORREOS_SOPORTE`
 *  (la de Reportes primero). Filtra las que no existan en esta base. */
async function getCuentasSoporte() {
  const rows = await Promise.all(CORREOS_SOPORTE.map(correo => db.prepare('SELECT * FROM sellers WHERE lower(trim(email)) = ?').get(correo)));
  return rows.filter(Boolean).map(rowToSeller);
}

/**
 * ¿`userId` participa en `conversationId`?
 *
 * Es la comprobación que decide quién puede LEER una conversación, y por eso
 * vive aquí y no repetida en cada llamador: la usan la ruta REST de mensajes,
 * el borrado y la sala de Socket.IO, y si las tres divergieran bastaría con
 * que una se quedara corta para reabrir la fuga.
 */
async function esParticipanteDeConversacion(conversationId, userId) {
  if (!conversationId || !userId) return false;
  const fila = await db.prepare('SELECT 1 FROM conversations WHERE id = ? AND (buyer_id = ? OR seller_id = ?)').get(conversationId, userId, userId);
  return !!fila;
}
async function getSellers() {
  const rows = await db.prepare('SELECT * FROM sellers ORDER BY id').all();
  return rows.map(rowToSeller);
}
async function insertSeller(seller) {
  await db.prepare(`
    INSERT OR IGNORE INTO sellers (id, name, avatarInitials, major, isBusiness, logoUrl, rating, reviews, verified, created_at)
    VALUES (@id, @name, @avatarInitials, @major, @isBusiness, @logoUrl, @rating, @reviews, @verified, datetime('now'))
  `).run({
    ...seller,
    isBusiness: seller.isBusiness ? 1 : 0,
    verified: seller.verified ? 1 : 0,
    rating: seller.rating ?? 0,
    reviews: seller.reviews ?? 0,
    logoUrl: seller.logoUrl || null
  });
}
async function getHighlightPlans() {
  return await db.prepare("SELECT * FROM highlight_plans ORDER BY " + "CASE id WHEN 'd1' THEN 1 WHEN 'd3' THEN 2 WHEN 'd7' THEN 3 WHEN 'm1' THEN 4 ELSE 5 END").all();
}
async function getAllProducts() {
  const rows = await db.prepare("SELECT * FROM products WHERE moderation_status = 'visible'").all();
  return rows.map(rowToProduct);
}
async function getProductById(id) {
  const row = await db.prepare(`SELECT * FROM products p
    WHERE p.id = ? AND p.moderation_status = 'visible'
      AND EXISTS (
        SELECT 1 FROM sellers s WHERE s.id = p.seller AND (
          s.admin_status = 'active'
          OR (s.admin_status = 'suspended' AND s.admin_status_until IS NOT NULL
            AND datetime(s.admin_status_until) <= datetime('now'))
        )
      )`).get(id);
  return rowToProduct(row);
}
async function isSellerPubliclyActive(userId) {
  return !!(await db.prepare(`SELECT 1 FROM sellers
    WHERE id = ? AND (
      admin_status = 'active'
      OR (admin_status = 'suspended' AND admin_status_until IS NOT NULL
        AND datetime(admin_status_until) <= datetime('now'))
    )`).get(userId));
}
async function getPublicationLimitSince(userId, kind, fallbackIso) {
  if (!['products', 'wanted'].includes(kind)) return fallbackIso;
  const column = kind === 'products' ? 'products_reset_at' : 'wanted_reset_at';
  const row = await db.prepare(`SELECT ${column} AS reset_at
    FROM publication_limit_resets WHERE user_id = ?`).get(userId);
  return row?.reset_at && row.reset_at > fallbackIso ? row.reset_at : fallbackIso;
}
async function countProductsSince(userId, isoTimestamp) {
  return (await db.prepare('SELECT COUNT(*) AS count FROM products WHERE seller = ? AND created_at >= ?').get(userId, isoTimestamp))?.count ?? 0;
}
async function insertProduct(product) {
  const row = productToRow(product);
  // NUNCA usar INSERT OR REPLACE: en SQLite eso hace un DELETE + INSERT de la
  // fila existente, y con foreign_keys=ON eso dispara el ON DELETE CASCADE de
  // product_ratings (y cualquier otra tabla hija), borrando datos relacionados
  // cada vez que se guarda un producto ya existente. Un upsert real (ON
  // CONFLICT DO UPDATE) modifica la fila in place sin disparar cascadas.
  await db.prepare(`
    INSERT INTO products (id, title, price, priceNum, category, description, publishedAgo, seller,
      images, imageIcon, imageColor, previousPrice, discountLabel,
      isFeatured, isOffer, isFavorite, status, manual_status, offerExpiresAt, extras,
      stock_quantity, stock_reset_daily, stock_initial, stock_updated_at, created_at, availableDays, updated_at,
      location_lat, location_lng, paymentMethods, atributos_categoria, expires_at)
    VALUES (@id, @title, @price, @priceNum, @category, @description, @publishedAgo, @seller,
      @images, @imageIcon, @imageColor, @previousPrice, @discountLabel,
      @isFeatured, @isOffer, @isFavorite, @status, @manual_status, @offerExpiresAt, @extras,
      @stock_quantity, @stock_reset_daily, @stock_initial, @stock_updated_at, @created_at, @availableDays, @updated_at,
      @location_lat, @location_lng, @paymentMethods, @atributos_categoria, @expires_at)
    ON CONFLICT(id) DO UPDATE SET
      title = excluded.title, price = excluded.price, priceNum = excluded.priceNum,
      category = excluded.category, description = excluded.description,
      publishedAgo = excluded.publishedAgo, seller = excluded.seller,
      images = excluded.images, imageIcon = excluded.imageIcon, imageColor = excluded.imageColor,
      previousPrice = excluded.previousPrice, discountLabel = excluded.discountLabel,
      isFeatured = excluded.isFeatured, isOffer = excluded.isOffer, isFavorite = excluded.isFavorite,
      status = excluded.status, manual_status = excluded.manual_status, offerExpiresAt = excluded.offerExpiresAt, extras = excluded.extras,
      stock_quantity = excluded.stock_quantity, stock_reset_daily = excluded.stock_reset_daily,
      stock_initial = excluded.stock_initial, stock_updated_at = excluded.stock_updated_at,
      created_at = excluded.created_at, availableDays = excluded.availableDays, updated_at = excluded.updated_at,
      location_lat = excluded.location_lat, location_lng = excluded.location_lng,
      paymentMethods = excluded.paymentMethods,
      atributos_categoria = excluded.atributos_categoria,
      expires_at = excluded.expires_at
  `).run(row);
}
async function updateProduct(id, updates) {
  const existing = await getProductById(id);
  if (!existing) return null;
  const merged = {
    ...existing,
    ...updates
  };
  const row = productToRow(merged);
  await db.prepare(`
    UPDATE products SET
      title = @title, price = @price, priceNum = @priceNum, category = @category,
      description = @description, publishedAgo = @publishedAgo, seller = @seller,
      images = @images, imageIcon = @imageIcon, imageColor = @imageColor,
      previousPrice = @previousPrice, discountLabel = @discountLabel,
      isFeatured = @isFeatured, isOffer = @isOffer, isFavorite = @isFavorite,
      status = @status, manual_status = @manual_status, offerExpiresAt = @offerExpiresAt, extras = @extras,
      stock_quantity = @stock_quantity, stock_reset_daily = @stock_reset_daily,
      stock_initial = @stock_initial, stock_updated_at = @stock_updated_at,
      availableDays = @availableDays, updated_at = @updated_at,
      location_lat = @location_lat, location_lng = @location_lng,
      paymentMethods = @paymentMethods, atributos_categoria = @atributos_categoria
    WHERE id = ?
  `).run(row, id);
  return await getProductById(id);
}
async function deleteProduct(id) {
  await db.prepare('DELETE FROM products WHERE id = ?').run(id);
}
async function incrementProductViews(id) {
  await db.prepare('UPDATE products SET views = views + 3 WHERE id = ?').run(id);
}

/**
 * Total historico de vistas de todos los productos que aun conserva la base
 * para un vendedor. No filtra por disponibilidad, vencimiento ni moderacion:
 * vendido, archivado y retirado siguen siendo actividad real acumulada.
 *
 * La agregacion ocurre enteramente en SQLite y usa idx_products_seller; nunca
 * carga la coleccion para sumarla en JavaScript.
 */
async function getSellerProductViews(sellerId) {
  const row = await db.prepare(`
    SELECT COALESCE(SUM(COALESCE(p.views, 0)), 0) AS total
      FROM sellers s
      LEFT JOIN products p ON p.seller = s.id
     WHERE s.id = ?
     GROUP BY s.id
  `).get(sellerId);
  return row?.total ?? 0;
}

/**
 * Suma una apertura ajena al perfil solo si ese visitante no fue contado en
 * la ventana reciente. Evita que refresh, volver atrás/entrar o recargas de
 * la pantalla inflen la métrica.
 */
async function recordSellerProfileView(profileId, viewerKey, windowHours = 24) {
  if (!profileId || !viewerKey) return false;
  const windowModifier = `-${Math.max(1, Math.min(Number(windowHours) || 24, 24 * 30))} hours`;
  return await db.transaction(async () => {
    const recent = await db.prepare(`
      SELECT 1 FROM profile_view_events
       WHERE profile_id = ? AND viewer_key = ?
         AND viewed_at >= datetime('now', ?)
    `).get(profileId, viewerKey, windowModifier);
    if (recent) return false;
    await db.prepare(`
      INSERT INTO profile_view_events (profile_id, viewer_key, viewed_at)
      VALUES (?, ?, datetime('now'))
      ON CONFLICT(profile_id, viewer_key) DO UPDATE SET viewed_at = excluded.viewed_at
    `).run(profileId, viewerKey);
    await db.prepare('UPDATE sellers SET profile_views = profile_views + 1 WHERE id = ?').run(profileId);
    return true;
  })();
}

/** Suma una apertura ajena al perfil, independiente de publicaciones. */
async function incrementSellerProfileViews(id) {
  await db.prepare('UPDATE sellers SET profile_views = profile_views + 1 WHERE id = ?').run(id);
}

// ─── Carrito ────────────────────────────────────────────────
//
// Todas las operaciones van acotadas por `userId`. Las firmas piden el
// usuario como primer argumento a propósito: así es imposible escribir por
// descuido una consulta de carrito que no filtre por dueño, que es
// exactamente el bug que tenía la versión anterior de estas funciones.

async function getCartItems(userId) {
  return await db.prepare('SELECT * FROM cart WHERE user_id = ?').all(userId);
}
async function getCartItem(userId, id) {
  return await db.prepare('SELECT * FROM cart WHERE id = ? AND user_id = ?').get(id, userId);
}

/** Agrega o suma cantidad si el producto ya está en el carrito del usuario. */
async function upsertCartItem(userId, {
  id,
  productId,
  quantity,
  meetingPoint
}) {
  const existing = await db.prepare('SELECT * FROM cart WHERE user_id = ? AND productId = ?').get(userId, productId);
  if (existing) {
    await db.prepare(`UPDATE cart SET quantity = quantity + ?,
       meetingPoint = COALESCE(?, meetingPoint) WHERE id = ?`).run(quantity, meetingPoint || null, existing.id);
    return existing.id;
  }
  await db.prepare(`
    INSERT INTO cart (id, user_id, productId, quantity, meetingPoint)
    VALUES (?, ?, ?, ?, ?)
  `).run(id, userId, productId, quantity, meetingPoint || 'Por definir');
  return id;
}
async function updateCartItem(userId, id, {
  quantity,
  meetingPoint
}) {
  const item = await getCartItem(userId, id);
  if (!item) return false;
  await db.prepare(`UPDATE cart SET quantity = COALESCE(?, quantity),
     meetingPoint = COALESCE(?, meetingPoint) WHERE id = ? AND user_id = ?`).run(quantity ?? null, meetingPoint ?? null, id, userId);
  return true;
}
async function deleteCartItem(userId, id) {
  return (await db.prepare('DELETE FROM cart WHERE id = ? AND user_id = ?').run(id, userId)).changes > 0;
}
async function clearCartItems(userId, productIds) {
  if (!productIds || productIds.length === 0) return;
  const placeholders = productIds.map(() => '?').join(',');
  await db.prepare(`DELETE FROM cart WHERE user_id = ? AND productId IN (${placeholders})`).run(userId, ...productIds);
}
async function getAllListings() {
  return await db.prepare('SELECT * FROM listings').all();
}
async function addListing(listing) {
  await db.prepare('INSERT INTO listings (id, productId) VALUES (?, ?)').run(listing.id, listing.productId);
}
function getDb() {
  if (!db) throw new Error('Database not initialized. Call initDatabase() first.');
  return db;
}

// ─── Price History ─────────────────────────────────────────────

/**
 * Obtiene el precio más alto de un producto en los últimos [days] días
 * según su historial de precios.
 */
async function getHighestPriceInLastDays(productId, days = 30) {
  const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  const row = await db.prepare(`
    SELECT MAX(price) as highest FROM price_history
    WHERE product_id = ? AND changed_at >= ?
  `).get(productId, cutoff);
  return row?.highest ?? null;
}

/**
 * Obtiene el precio más bajo registrado para un producto en los últimos [days] días,
 * considerando el precio actual y todo el historial.
 */
async function getLowestPriceInLastDays(productId, currentPrice, days = 30) {
  const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  const row = await db.prepare(`
    SELECT MIN(min_price) as lowest FROM (
      SELECT price as min_price FROM price_history
        WHERE product_id = ? AND changed_at >= ?
      UNION ALL
      SELECT ? as min_price
    )
  `).get(productId, cutoff, currentPrice ?? 0);
  const lowest = row?.lowest;
  return typeof lowest === 'number' && lowest > 0 ? lowest : currentPrice ?? 0;
}

/**
 * Obtiene el cambio de precio más reciente para verificar el cooldown de 72h.
 */
async function getLastPriceChange(productId) {
  return await db.prepare(`
    SELECT * FROM price_history
    WHERE product_id = ?
    ORDER BY changed_at DESC
    LIMIT 1
  `).get(productId);
}

/**
 * Obtiene el listado de historial de precios de los últimos [days] días.
 */
async function getPriceHistoryList(productId, days = 30) {
  const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  return await db.prepare(`
    SELECT price, changed_at
    FROM price_history
    WHERE product_id = ? AND changed_at >= ?
    ORDER BY changed_at ASC
  `).all(productId, cutoff);
}

/**
 * Cuenta cuántas ediciones de precio hubo para un producto en la última hora.
 */
async function countPriceEditsLastHour(productId) {
  const cutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const row = await db.prepare(`
    SELECT COUNT(*) as count FROM price_history
    WHERE product_id = ? AND changed_at >= ?
  `).get(productId, cutoff);
  return row?.count ?? 0;
}

/**
 * Inserta un registro en price_history con el precio anterior.
 */
async function insertPriceHistory(productId, price) {
  await db.prepare(`
    INSERT INTO price_history (product_id, price, changed_at)
    VALUES (?, ?, datetime('now'))
  `).run(productId, price);
}

/**
 * Limpia ofertas expiradas (offerExpiresAt ya pasó o status = 'sold').
 * Se llama al iniciar y al editar precios.
 */
async function expireStaleOffers() {
  const now = new Date().toISOString();
  await db.prepare(`
    UPDATE products SET
      isOffer = 0,
      previousPrice = NULL,
      discountLabel = NULL,
      offerExpiresAt = NULL
    WHERE isOffer = 1 AND (
      offerExpiresAt IS NOT NULL AND offerExpiresAt < ?
    )
  `).run(now);
}

// ─── Product Ratings ──────────────────────────────────────────

async function upsertProductRating(productId, userId, stars) {
  const existing = await db.prepare('SELECT * FROM product_ratings WHERE product_id = ? AND user_id = ?').get(productId, userId);
  if (existing) {
    await db.prepare(`
      UPDATE product_ratings SET stars = ?, updated_at = datetime('now')
      WHERE product_id = ? AND user_id = ?
    `).run(stars, productId, userId);
  } else {
    await db.prepare(`
      INSERT INTO product_ratings (product_id, user_id, stars, created_at, updated_at)
      VALUES (?, ?, ?, datetime('now'), datetime('now'))
    `).run(productId, userId, stars);
  }
}
async function getProductRatingStats(productId) {
  const row = await db.prepare(`
    SELECT
      COALESCE(AVG(CAST(stars AS REAL)), 0) as average,
      COUNT(*) as count
    FROM product_ratings
    WHERE product_id = ?
  `).get(productId);
  return {
    average: Math.round((row.average || 0) * 10) / 10,
    count: row.count || 0
  };
}
async function getUserProductRating(productId, userId) {
  const row = await db.prepare('SELECT stars FROM product_ratings WHERE product_id = ? AND user_id = ?').get(productId, userId);
  return row ? row.stars : null;
}
async function getSellerRatingStats(sellerId) {
  const row = await db.prepare(`
    SELECT
      COALESCE(AVG(CAST(pr.stars AS REAL)), 0) as average,
      COUNT(*) as count
    FROM product_ratings pr
    JOIN products p ON p.id = pr.product_id
    WHERE p.seller = ?
  `).get(sellerId);
  return {
    rating: Math.round((row.average || 0) * 10) / 10,
    reviews: row.count || 0
  };
}

// `sellers.rating`/`sellers.reviews` son un caché denormalizado de la query de
// arriba. No es opcional mantenerlo: el scoring del feed lo lee dentro de SQL
// (`COALESCE(s.rating, 0)` en getRankedFeed), así que no basta con calcular el
// promedio al vuelo en las rutas. Estas dos funciones son el único camino por
// el que ese caché debe escribirse.

async function syncSellerRating(sellerId) {
  const stats = await getSellerRatingStats(sellerId);
  await db.prepare('UPDATE sellers SET rating = ?, reviews = ? WHERE id = ?').run(stats.rating, stats.reviews, sellerId);
  return stats;
}

// ─── Tiempo de respuesta (mediana) ──────────────────────────────
//
// Un vendedor no queda marcado como "responde rápido" con una sola respuesta
// afortunada: hacen falta al menos estas respuestas para que la mediana
// signifique algo.
const MIN_RESPUESTAS_PARA_MEDIANA = 3;

/// Minutos entre cada mensaje de comprador y la respuesta del vendedor.
///
/// Solo cuenta el PRIMER mensaje de cada ráfaga: si alguien escribe cuatro
/// mensajes seguidos y el vendedor contesta una vez, eso es UNA respuesta
/// medida desde el primero, no cuatro. Contar cada mensaje por separado
/// premiaría al vendedor cuando el comprador es insistente.
async function getResponseDeltasMinutes(sellerId) {
  const rows = await db.prepare(`
    SELECT
      m.conversation_id,
      m.sender_id,
      -- strftime interpreta created_at como UTC, que es como lo escribe
      -- datetime('now'). Hacer el delta en JS con Date.parse dependería de
      -- la zona horaria del servidor.
      CAST(strftime('%s', m.created_at) AS INTEGER) AS ts
    FROM messages m
    JOIN conversations c ON c.id = m.conversation_id
    WHERE c.seller_id = ?
    -- created_at solo tiene precisión de SEGUNDO (datetime('now') de
    -- SQLite); dos mensajes en el mismo segundo (un intercambio rápido de
    -- "sí"/"no", por ejemplo) empatan y SQLite no garantiza su orden real
    -- en el ORDER BY. El id sí tiene precisión de milisegundo (msg seguido
    -- del timestamp) y ordena igual que created_at cuando no hay empate,
    -- así que sirve de desempate sin cambiar el orden en el caso normal.
    ORDER BY m.conversation_id, m.created_at, m.id
  `).all(sellerId);
  const deltas = [];
  let conversacionActual = null;
  let esperandoDesde = null;
  for (const row of rows) {
    if (row.conversation_id !== conversacionActual) {
      conversacionActual = row.conversation_id;
      esperandoDesde = null;
    }
    if (row.sender_id === sellerId) {
      if (esperandoDesde !== null) {
        deltas.push((row.ts - esperandoDesde) / 60);
        esperandoDesde = null;
      }
      continue;
    }
    // Mensaje del comprador: abre una espera solo si no había una abierta.
    if (esperandoDesde === null) esperandoDesde = row.ts;
  }
  return deltas;
}
function medianOf(numeros) {
  if (numeros.length === 0) return null;
  const ordenados = [...numeros].sort((a, b) => a - b);
  const medio = Math.floor(ordenados.length / 2);
  return ordenados.length % 2 === 1 ? ordenados[medio] : (ordenados[medio - 1] + ordenados[medio]) / 2;
}

/// Recalcula y cachea la mediana de respuesta del vendedor. Devuelve los
/// minutos, o null si todavía no hay respuestas suficientes.
async function syncSellerResponseTime(sellerId) {
  const deltas = await getResponseDeltasMinutes(sellerId);
  const mediana = deltas.length >= MIN_RESPUESTAS_PARA_MEDIANA ? Math.round(medianOf(deltas)) : null;
  await db.prepare('UPDATE sellers SET median_response_minutes = ? WHERE id = ?').run(mediana, sellerId);
  return mediana;
}

// ─── Racha de publicaciones ─────────────────────────────────────
//
// La racha cuenta SEMANAS consecutivas con al menos una publicación, no
// días: en un marketplace universitario nadie publica algo nuevo cada día,
// y una racha diaria estaría rota para todo el mundo el 100% del tiempo.
//
// Solo cuenta publicar. Vender no entra: si contara, un vendedor con
// inventario parado perdería su racha por algo que no depende de él, y la
// racha dejaría de medir constancia para medir suerte.

/// Cuenta ventanas MÓVILES de 7 días hacia atrás desde ahora: la ventana 0
/// son los últimos 7 días, la 1 los 7 anteriores, y así. La racha es cuántas
/// ventanas consecutivas desde la 0 tienen al menos una publicación.
///
/// Se usan ventanas móviles y no semanas de calendario a propósito. Con
/// bloques fijos, "publiqué el domingo y el lunes" cae en dos semanas
/// distintas y regala una racha de 2, mientras que "publiqué el lunes y el
/// domingo siguiente" (13 días de diferencia) cuenta como una sola. La
/// ventana móvil mide lo que la palabra promete: que no has dejado pasar
/// siete días sin publicar.
async function computeRachaPublicaciones(sellerId) {
  const ventanas = new Set((await db.prepare(`
    SELECT DISTINCT
      CAST((julianday('now') - julianday(created_at)) / 7 AS INTEGER) AS ventana
    FROM products
    WHERE seller = ?
  `).all(sellerId)).map(r => r.ventana));
  let racha = 0;
  while (ventanas.has(racha)) racha += 1;
  return racha;
}

// Ventas confirmadas de un vendedor: órdenes con status = 'paid', el único
// estado que significa que el cobro se completó (ver CHECK de la tabla
// orders). 'pending'/'cancelled'/'requires_other_method' no cuentan como
// venta, son intentos que no llegaron a buen puerto.
async function countVentasConfirmadas(sellerId) {
  const row = await db.prepare(`SELECT COUNT(*) AS n FROM orders WHERE vendor_id = ? AND status = 'paid'`).get(sellerId);
  return row ? row.n : 0;
}

/**
 * Qué insignias permanentes tiene registradas este vendedor.
 *
 * Devuelve un Set de claves del catálogo (`validation/insignias.js`), vacío
 * si no tiene ninguna. Es lo que hace que subir un umbral no le quite la
 * insignia a quien ya la había ganado con el umbral anterior.
 */
async function getInsigniasOtorgadas(sellerId) {
  const filas = await db.prepare('SELECT clave FROM insignias_otorgadas WHERE seller_id = ?').all(sellerId);
  return new Set(filas.map(f => f.clave));
}

/**
 * Deja registrado que este vendedor ganó una insignia permanente.
 *
 * INSERT OR IGNORE: se llama desde la lectura del perfil, que puede pasar
 * muchas veces por el mismo caso; la primera escribe y el resto no hace
 * nada. El llamador solo debe invocarla cuando la insignia se acaba de
 * cumplir POR LA REGLA — nunca por la excepción de las cuentas del dueño,
 * que la tienen siempre y no necesitan que nadie se la guarde.
 */
async function registrarInsigniaOtorgada(sellerId, clave) {
  await db.prepare('INSERT OR IGNORE INTO insignias_otorgadas (seller_id, clave) VALUES (?, ?)').run(sellerId, clave);
}

/**
 * Dinero facturado de por vida, en MXN, para la insignia "Vendedor de oro".
 *
 * Suma `orders.amount` (el total cobrado) y no `order_items.unit_price`:
 * `amount` es lo que realmente se acordó por la orden completa, y es la
 * misma columna que el resto del sistema de pagos considera la verdad.
 * Solo 'paid', igual que countVentasConfirmadas: una orden cancelada o
 * pendiente no es dinero vendido.
 */
async function sumarVentasConfirmadas(sellerId) {
  const row = await db.prepare(`SELECT COALESCE(SUM(amount), 0) AS total
       FROM orders WHERE vendor_id = ? AND status = 'paid'`).get(sellerId);
  return row ? row.total : 0;
}

/**
 * Calificaciones del vendedor separadas en total y cincos perfectos.
 *
 * Las dos insignias de reseñas se calculan desde aquí y NO desde el caché
 * `sellers.rating`, que está redondeado a un decimal: con 60 cincos y un
 * cuatro el promedio real es 4.98 pero el caché dice 5.0, así que usarlo
 * regalaría la insignia "Impecable" a quien no tiene el promedio perfecto.
 * Con el conteo crudo, "perfecto" es literalmente cincos === total.
 */
async function getEstadisticasCalificaciones(sellerId) {
  const row = await db.prepare(`
    SELECT
      COUNT(*) AS total,
      COALESCE(SUM(CASE WHEN pr.stars = 5 THEN 1 ELSE 0 END), 0) AS cincos
    FROM product_ratings pr
    JOIN products p ON p.id = pr.product_id
    WHERE p.seller = ?
  `).get(sellerId);
  return {
    total: row ? row.total : 0,
    cincos: row ? row.cincos : 0
  };
}

/**
 * Preguntas recibidas y respondidas, para la insignia "Siempre responde".
 *
 * Una sola consulta por `seller_id` (índice idx_product_questions_seller) en
 * vez de dos: el perfil ya hace varias agregaciones al vuelo y esta se pide
 * en cada visita.
 */
async function getEstadisticasPreguntasVendedor(sellerId) {
  const row = await db.prepare(`
    SELECT
      COUNT(*) AS total,
      COALESCE(SUM(CASE WHEN status = 'answered' THEN 1 ELSE 0 END), 0) AS respondidas
    FROM product_questions
    WHERE seller_id = ?
  `).get(sellerId);
  return {
    total: row ? row.total : 0,
    respondidas: row ? row.respondidas : 0
  };
}

// Recalcula el caché de TODOS los vendedores desde product_ratings. Corre al
// arrancar: es lo que repara las filas que quedaron con valores inventados
// (semilla) o desactualizados por escrituras que solo tocaban memoria.
async function recomputeAllSellerRatings() {
  const stmt = db.prepare(`
    UPDATE sellers SET
      rating = COALESCE((
        SELECT ROUND(AVG(pr.stars)::numeric, 1)::double precision
        FROM product_ratings pr
        JOIN products p ON p.id = pr.product_id
        WHERE p.seller = sellers.id
      ), 0),
      reviews = COALESCE((
        SELECT COUNT(*)
        FROM product_ratings pr
        JOIN products p ON p.id = pr.product_id
        WHERE p.seller = sellers.id
      ), 0)
  `);
  const info = await stmt.run();
  return info.changes;
}

// ─── Product Comments ───────────────────────────────────────────

/** Tamaño de página por defecto del hilo de comentarios. */
const COMENTARIOS_POR_PAGINA = 20;

/** Tope duro: un cliente no puede pedir páginas arbitrariamente grandes. */
const COMENTARIOS_MAX_POR_PAGINA = 50;

// Proyección del autor: lista blanca, al estilo de routes/public.js. Son
// exactamente los campos que necesitan `subtituloRol()` e
// `InsigniaVerificada` en la app (lib/widgets/user_role.dart y badges.dart),
// ni uno más. Fuera quedan teléfono y correo: un comentario es contenido
// público y no debe convertir el hilo en un directorio de contacto.
//
// created_at se emite como ISO-8601 con 'Z' explícita, no como el
// 'YYYY-MM-DD HH:MM:SS' crudo que guarda SQLite: ese formato lo interpreta
// `DateTime.parse` de Dart como hora LOCAL, aunque el valor sea UTC, y el
// "hace 2 h" saldría corrido por el offset del dispositivo.
const SELECT_COMENTARIO = `
  SELECT
    c.id                  AS id,
    c.product_id          AS productId,
    c.user_id             AS userId,
    c.texto               AS texto,
    strftime('%Y-%m-%dT%H:%M:%SZ', c.created_at) AS createdAt,
    -- Formato crudo de SQLite: es contra ESTE valor que compara el WHERE de
    -- la página siguiente, así que el cursor tiene que llevarlo tal cual.
    c.created_at          AS createdAtRaw,
    s.name                AS autorNombre,
    s.avatarInitials      AS autorIniciales,
    s.logoUrl             AS autorLogo,
    s.major               AS autorMajor,
    s.isBusiness          AS autorEsNegocio,
    s.verified            AS autorVerificado,
    s.tipo_cuenta         AS autorTipoCuenta,
    s.carrera             AS autorCarrera,
    s.tipo_verificacion   AS autorTipoVerificacion,
    s.socio_fundador      AS autorSocioFundador
  FROM product_comments c
  LEFT JOIN sellers s ON s.id = c.user_id
`;

/**
 * Convierte una fila de [SELECT_COMENTARIO] a la forma que consume la app.
 * Es la ÚNICA función que arma esta forma, para que la respuesta REST y el
 * evento de Socket.IO no se puedan desincronizar entre sí.
 */
function rowToProductComment(row) {
  if (!row) return null;
  return {
    id: row.id,
    productId: row.productId,
    texto: row.texto,
    createdAt: row.createdAt,
    author: {
      id: row.userId,
      // Una cuenta borrada deja su comentario en pie pero sin autor que
      // resolver; el hilo no debe romperse por eso.
      name: row.autorNombre ?? 'Usuario',
      avatarInitials: row.autorIniciales || '??',
      logoUrl: row.autorLogo || null,
      major: row.autorMajor || '',
      isBusiness: !!row.autorEsNegocio,
      // `|| esUsuarioTodosLosBadges` y no solo la columna: este autor se arma
      // desde el JOIN, sin pasar por `rowToSeller`, así que sin esto el
      // comentario salía sin palomita aunque el perfil sí la tuviera.
      verified: esUsuarioTodosLosBadges(row.userId) || !!row.autorVerificado,
      socioFundador: esUsuarioTodosLosBadges(row.userId) || !!row.autorSocioFundador,
      tipoCuenta: row.autorTipoCuenta || 'particular',
      carrera: row.autorCarrera || null,
      tipoVerificacion: row.autorTipoVerificacion || null
    }
  };
}

/**
 * Normaliza el tamaño de página pedido por el cliente.
 * Un valor ausente, no numérico o fuera de rango cae al default.
 */
function normalizarLimiteComentarios(limite) {
  const n = parseInt(limite, 10);
  if (!Number.isFinite(n) || n < 1) return COMENTARIOS_POR_PAGINA;
  return Math.min(n, COMENTARIOS_MAX_POR_PAGINA);
}

/**
 * Ejecuta una consulta paginada por keyset sobre product_comments.
 *
 * Se pide una fila DE MÁS que el límite: si vuelve, hay página siguiente.
 * Así no hace falta un COUNT(*) extra por request solo para saber si pintar
 * el botón "Ver más".
 *
 * Keyset y no OFFSET porque el hilo recibe comentarios nuevos por Socket.IO
 * mientras el usuario pagina: con OFFSET, cada inserción en el tope recorre
 * la ventana y la página siguiente repetiría filas ya mostradas.
 */
async function paginarComentarios(sqlBase, params, limite) {
  const filas = await db.prepare(`${sqlBase} LIMIT ?`).all(...params, limite + 1);
  const hayMas = filas.length > limite;
  const pagina = hayMas ? filas.slice(0, limite) : filas;
  const ultima = pagina[pagina.length - 1];
  return {
    filas: pagina,
    // El cursor apunta a la última fila entregada.
    nextCursor: hayMas && ultima ? `${ultima.createdAtRaw}|${ultima.id}` : null
  };
}

/** Parte un cursor `<created_at>|<id>` en sus dos componentes, o null. */
function parseCursorComentario(cursor) {
  if (typeof cursor !== 'string' || !cursor.includes('|')) return null;
  const separador = cursor.indexOf('|');
  const createdAt = cursor.slice(0, separador);
  const id = cursor.slice(separador + 1);
  if (!createdAt || !id) return null;
  return {
    createdAt,
    id
  };
}

/**
 * Hilo de comentarios de un producto, del más reciente al más antiguo.
 * Excluye los borrados lógicamente.
 */
async function getProductComments(productId, {
  limit,
  cursor
} = {}) {
  const limite = normalizarLimiteComentarios(limit);
  const desde = parseCursorComentario(cursor);
  const where = desde ? `WHERE c.product_id = ? AND c.deleted_at IS NULL
         AND (c.created_at < ? OR (c.created_at = ? AND c.id < ?))` : `WHERE c.product_id = ? AND c.deleted_at IS NULL`;
  const params = desde ? [productId, desde.createdAt, desde.createdAt, desde.id] : [productId];
  const {
    filas,
    nextCursor
  } = await paginarComentarios(`${SELECT_COMENTARIO} ${where} ORDER BY c.created_at DESC, c.id DESC`, params, limite);
  return {
    comments: filas.map(rowToProductComment),
    nextCursor
  };
}

/** Cuántos comentarios vivos tiene un producto (el contador del header). */
async function countProductComments(productId) {
  const row = await db.prepare('SELECT COUNT(*) AS total FROM product_comments WHERE product_id = ? AND deleted_at IS NULL').get(productId);
  return row ? row.total : 0;
}

/**
 * Comentarios que OTROS dejaron en las publicaciones de [sellerId] — la
 * pestaña "Comentarios" del perfil, que existe como prueba social.
 *
 * No es el inverso trivial de getProductComments: filtra por el dueño del
 * producto, no por el autor del comentario, y excluye lo que el propio
 * dueño escribió en sus publicaciones (elogiarse a uno mismo no es prueba
 * de nada). Trae título y primera foto del producto para que la tarjeta
 * pueda navegar al detalle sin una segunda llamada por fila.
 */
async function getCommentsReceivedBySeller(sellerId, {
  limit,
  cursor
} = {}) {
  const limite = normalizarLimiteComentarios(limit);
  const desde = parseCursorComentario(cursor);
  const filtroCursor = desde ? `AND (c.created_at < ? OR (c.created_at = ? AND c.id < ?))` : '';
  const params = desde ? [sellerId, sellerId, desde.createdAt, desde.createdAt, desde.id] : [sellerId, sellerId];
  const sql = `
    SELECT
      c.id                  AS id,
      c.product_id          AS productId,
      c.user_id             AS userId,
      c.texto               AS texto,
      strftime('%Y-%m-%dT%H:%M:%SZ', c.created_at) AS createdAt,
      c.created_at          AS createdAtRaw,
      s.name                AS autorNombre,
      s.avatarInitials      AS autorIniciales,
      s.logoUrl             AS autorLogo,
      s.major               AS autorMajor,
      s.isBusiness          AS autorEsNegocio,
      s.verified            AS autorVerificado,
      s.tipo_cuenta         AS autorTipoCuenta,
      s.carrera             AS autorCarrera,
      s.tipo_verificacion   AS autorTipoVerificacion,
      s.socio_fundador      AS autorSocioFundador,
      p.title               AS productoTitulo,
      p.images              AS productoImagenes
    FROM product_comments c
    JOIN products p ON p.id = c.product_id AND p.seller = ?
    LEFT JOIN sellers s ON s.id = c.user_id
    WHERE c.deleted_at IS NULL AND c.user_id != ? ${filtroCursor}
    ORDER BY c.created_at DESC, c.id DESC
  `;
  const {
    filas,
    nextCursor
  } = await paginarComentarios(sql, params, limite);
  const comments = filas.map(fila => {
    const base = rowToProductComment(fila);
    let fotos = [];
    try {
      fotos = JSON.parse(fila.productoImagenes || '[]');
    } catch (_) {
      // Un `images` corrupto no debe tirar la pestaña entera: la tarjeta se
      // pinta sin miniatura.
      fotos = [];
    }
    return {
      ...base,
      product: {
        id: fila.productId,
        title: fila.productoTitulo,
        image: Array.isArray(fotos) && fotos.length > 0 ? fotos[0] : null
      }
    };
  });
  return {
    comments,
    nextCursor
  };
}

/** Cuántos comentarios vivos recibió [sellerId] en sus publicaciones. */
async function countCommentsReceivedBySeller(sellerId) {
  const row = await db.prepare(`
    SELECT COUNT(*) AS total
    FROM product_comments c
    JOIN products p ON p.id = c.product_id AND p.seller = ?
    WHERE c.deleted_at IS NULL AND c.user_id != ?
  `).get(sellerId, sellerId);
  return row ? row.total : 0;
}

/** Fila cruda de un comentario (incluye los borrados). Para permisos. */
async function getProductCommentRow(commentId) {
  return await db.prepare('SELECT * FROM product_comments WHERE id = ?').get(commentId);
}

/** Comentario ya en forma de API, por id. Usado tras insertar. */
async function getProductCommentById(commentId) {
  const fila = await db.prepare(`${SELECT_COMENTARIO} WHERE c.id = ?`).get(commentId);
  return rowToProductComment(fila);
}

/** Inserta un comentario y devuelve su forma de API, autor incluido. */
async function createProductComment(id, productId, userId, texto) {
  await db.prepare('INSERT INTO product_comments (id, product_id, user_id, texto) VALUES (?, ?, ?, ?)').run(id, productId, userId, texto);
  return await getProductCommentById(id);
}

/**
 * Segundos transcurridos desde el último comentario de [userId], o null si
 * nunca ha comentado.
 *
 * El cálculo va entero dentro de SQLite a propósito. `created_at` se guarda
 * con datetime('now'), que es UTC, pero el proceso corre con TZ=America/
 * Monterrey (ver index.js): restarlo contra un `new Date()` de Node daría
 * seis horas de diferencia y el rate limit no frenaría nada.
 */
async function segundosDesdeUltimoComentario(userId) {
  const row = await db.prepare(`
    SELECT CAST((julianday('now') - julianday(MAX(created_at))) * 86400.0 AS INTEGER) AS segundos
    FROM product_comments WHERE user_id = ?
  `).get(userId);
  return row && row.segundos != null ? row.segundos : null;
}

/**
 * Borrado lógico. Devuelve true solo si esta llamada fue la que lo marcó:
 * un comentario ya borrado devuelve false, así la ruta no vuelve a emitir
 * el evento de Socket.IO por un doble tap.
 */
async function softDeleteProductComment(commentId, actorId) {
  const info = await db.prepare(`
    UPDATE product_comments
    SET deleted_at = datetime('now'), deleted_by = ?
    WHERE id = ? AND deleted_at IS NULL
  `).run(actorId, commentId);
  return info.changes > 0;
}

// ─── Enigma escondido ───────────────────────────────────────────

/** Fila de `secret_solves` de un usuario, o undefined si no lo ha resuelto. */
async function getResolucionEnigma(userId) {
  return await db.prepare('SELECT user_id, posicion, solved_at FROM secret_solves WHERE user_id = ?').get(userId);
}

/** Cuánta gente lo ha resuelto ya. */
async function contarResolucionesEnigma() {
  return (await db.prepare('SELECT COUNT(*) AS c FROM secret_solves').get()).c;
}

/**
 * Registra que [userId] resolvió el enigma y devuelve su posición.
 *
 * Idempotente: quien vuelva a acertar conserva la posición y la fecha de la
 * primera vez (`repetida: true`), no se le adelanta ni se le atrasa.
 *
 * El cálculo de la posición y el INSERT van en una transacción porque son
 * un solo hecho: sin ella, dos aciertos simultáneos leerían el mismo COUNT
 * y se declararían ambos "el #1". better-sqlite3 es síncrono y el servidor
 * de un solo hilo, así que hoy no puede pasar; la transacción está para que
 * siga sin poder pasar el día que esto corra en más de un proceso.
 *
 * @returns {{posicion: number, solvedAt: string, repetida: boolean}}
 */
async function registrarResolucionEnigma(userId) {
  // La transacción se arma aquí y no en una constante de módulo porque `db`
  // no existe hasta initDatabase(): envolverla al cargar el archivo
  // reventaría el require.
  return await db.transaction(async () => {
    const previa = await getResolucionEnigma(userId);
    if (previa) {
      return {
        posicion: previa.posicion,
        solvedAt: previa.solved_at,
        repetida: true
      };
    }
    const posicion = (await contarResolucionesEnigma()) + 1;
    await db.prepare('INSERT INTO secret_solves (user_id, posicion) VALUES (?, ?)').run(userId, posicion);
    return {
      posicion,
      solvedAt: (await getResolucionEnigma(userId)).solved_at,
      repetida: false
    };
  })();
}

// ─── Preguntas y respuestas de producto ─────────────────────────

/** Tamaño de página del listado completo y tope que puede pedir el cliente. */
const PREGUNTAS_POR_PAGINA = 20;
const PREGUNTAS_MAX_POR_PAGINA = 50;

/** Cuántas preguntas se muestran en el preview del detalle. */
const PREGUNTAS_PREVIEW = 3;
const SELECT_PREGUNTA = `
  SELECT
    q.id            AS id,
    q.product_id    AS productId,
    q.seller_id     AS sellerId,
    q.asked_by      AS askedBy,
    q.question_text AS questionText,
    q.answer_text   AS answerText,
    q.status        AS status,
    strftime('%Y-%m-%dT%H:%M:%SZ', q.created_at)  AS createdAt,
    strftime('%Y-%m-%dT%H:%M:%SZ', q.answered_at) AS answeredAt,
    -- Formato crudo de SQLite: es contra ESTE valor que compara el WHERE de
    -- la página siguiente, así que el cursor tiene que llevarlo tal cual.
    q.created_at    AS createdAtRaw,
    s.name              AS autorNombre,
    s.avatarInitials    AS autorIniciales,
    s.logoUrl           AS autorLogo,
    s.major             AS autorMajor,
    s.isBusiness        AS autorEsNegocio,
    s.verified          AS autorVerificado,
    s.tipo_cuenta       AS autorTipoCuenta,
    s.carrera           AS autorCarrera,
    s.tipo_verificacion AS autorTipoVerificacion,
    s.socio_fundador    AS autorSocioFundador
  FROM product_questions q
  LEFT JOIN sellers s ON s.id = q.asked_by
`;

/**
 * Convierte una fila de [SELECT_PREGUNTA] a la forma que consume la app.
 * Única función que arma esta forma, para que las cuatro rutas (crear,
 * preview, listado y responder) devuelvan exactamente lo mismo.
 *
 * `author` trae solo lo que necesita la UI para pintar nombre e insignia —
 * la misma proyección que los comentarios. Ni teléfono ni correo: esto es
 * un hilo público.
 */
function rowToProductQuestion(row) {
  if (!row) return null;
  return {
    id: row.id,
    productId: row.productId,
    questionText: row.questionText,
    answerText: row.answerText || null,
    status: row.status,
    createdAt: row.createdAt,
    answeredAt: row.answeredAt || null,
    author: {
      id: row.askedBy,
      // Una cuenta borrada deja su pregunta en pie pero sin autor que
      // resolver; el hilo no debe romperse por eso.
      name: row.autorNombre ?? 'Usuario',
      avatarInitials: row.autorIniciales || '??',
      logoUrl: row.autorLogo || null,
      major: row.autorMajor || '',
      isBusiness: !!row.autorEsNegocio,
      // Igual que en el comentario: este autor no pasa por `rowToSeller`.
      verified: esUsuarioTodosLosBadges(row.askedBy) || !!row.autorVerificado,
      socioFundador: esUsuarioTodosLosBadges(row.askedBy) || !!row.autorSocioFundador,
      tipoCuenta: row.autorTipoCuenta || 'particular',
      carrera: row.autorCarrera || null,
      tipoVerificacion: row.autorTipoVerificacion || null
    }
  };
}
function normalizarLimitePreguntas(limite) {
  const n = parseInt(limite, 10);
  if (!Number.isFinite(n) || n < 1) return PREGUNTAS_POR_PAGINA;
  return Math.min(n, PREGUNTAS_MAX_POR_PAGINA);
}
async function getProductQuestionById(id) {
  return rowToProductQuestion(await db.prepare(`${SELECT_PREGUNTA} WHERE q.id = ?`).get(id));
}

/** Fila cruda, para las validaciones de permiso de la ruta (seller_id). */
async function getProductQuestionRow(id) {
  return await db.prepare('SELECT * FROM product_questions WHERE id = ?').get(id);
}
async function createProductQuestion(id, productId, sellerId, askedBy, texto) {
  await db.prepare(`
    INSERT INTO product_questions (id, product_id, seller_id, asked_by, question_text)
    VALUES (?, ?, ?, ?, ?)
  `).run(id, productId, sellerId, askedBy, texto);
  return await getProductQuestionById(id);
}

/**
 * Guarda (o corrige) la respuesta del vendedor.
 *
 * Una pregunta admite UNA respuesta: si ya había, se sobrescribe en vez de
 * insertar otra fila, y `answered_at` se refresca — para el que preguntó,
 * una respuesta editada es una respuesta nueva. `status` viaja en el mismo
 * UPDATE, nunca por separado, para que no pueda quedar en 'pending' con
 * texto de respuesta guardado.
 *
 * La ruta ya validó quién responde; aquí no se decide permiso.
 */
async function answerProductQuestion(id, texto) {
  await db.prepare(`
    UPDATE product_questions
    SET answer_text = ?, status = 'answered', answered_at = datetime('now')
    WHERE id = ?
  `).run(texto, id);
  return await getProductQuestionById(id);
}

/**
 * Elimina una pregunta completa del hilo.
 *
 * A diferencia de comentarios, las preguntas no tienen columna de borrado
 * lógico ni se muestran como prueba social en otro perfil. Si se borra una
 * pregunta, desaparece junto con su respuesta y los contadores se recalculan
 * sobre las filas vivas.
 */
async function deleteProductQuestion(id) {
  const result = await db.prepare('DELETE FROM product_questions WHERE id = ?').run(id);
  return result.changes > 0;
}

/**
 * Página del listado completo, de la más reciente a la más antigua.
 *
 * Keyset y no OFFSET por lo mismo que en comentarios: llegan preguntas
 * nuevas al tope mientras alguien pagina, y con OFFSET la página siguiente
 * repetiría filas ya vistas.
 *
 * `filter: 'pending'` es lo que usa el chip "sin responder" del dueño. Va
 * como filtro y no como orden mezclado a propósito: ordenar "pendientes
 * primero" rompería el keyset, porque un cursor sobre created_at no puede
 * saltar entre dos bloques con criterios de orden distintos sin repetir o
 * saltarse filas.
 */
async function getProductQuestions(productId, {
  limit,
  cursor,
  filter
} = {}) {
  const limite = normalizarLimitePreguntas(limit);
  const desde = parseCursorComentario(cursor);
  const condiciones = ['q.product_id = ?'];
  const params = [productId];
  if (filter === 'pending') condiciones.push("q.status = 'pending'");
  if (desde) {
    condiciones.push('(q.created_at < ? OR (q.created_at = ? AND q.id < ?))');
    params.push(desde.createdAt, desde.createdAt, desde.id);
  }
  const {
    filas,
    nextCursor
  } = await paginarComentarios(`${SELECT_PREGUNTA} WHERE ${condiciones.join(' AND ')}
     ORDER BY q.created_at DESC, q.id DESC`, params, limite);
  return {
    questions: filas.map(rowToProductQuestion),
    nextCursor
  };
}

/**
 * Las pocas preguntas que se asoman en el detalle del producto.
 *
 * Prioriza respondidas recientes y completa con pendientes si no llenan el
 * cupo: una pregunta con respuesta informa a quien está mirando el producto
 * (que es de quien es esta pantalla), mientras que una pendiente solo dice
 * que alguien más preguntó. Dentro de cada grupo, lo más reciente primero,
 * usando la fecha que le da sentido a cada uno: cuándo se respondió para
 * las respondidas, cuándo se preguntó para las pendientes.
 */
async function getProductQuestionsPreview(productId, {
  limit = PREGUNTAS_PREVIEW
} = {}) {
  const filas = await db.prepare(`
    ${SELECT_PREGUNTA}
    WHERE q.product_id = ?
    ORDER BY
      CASE WHEN q.status = 'answered' THEN 0 ELSE 1 END,
      COALESCE(q.answered_at, q.created_at) DESC,
      q.id DESC
    LIMIT ?
  `).all(productId, limit);
  return filas.map(rowToProductQuestion);
}

/** Total de preguntas de un producto (el "Ver las N preguntas"). */
async function countProductQuestions(productId) {
  const row = await db.prepare('SELECT COUNT(*) AS total FROM product_questions WHERE product_id = ?').get(productId);
  return row ? row.total : 0;
}

/** Cuántas están sin responder — el chip del dueño. */
async function countPendingProductQuestions(productId) {
  const row = await db.prepare("SELECT COUNT(*) AS total FROM product_questions WHERE product_id = ? AND status = 'pending'").get(productId);
  return row ? row.total : 0;
}

/**
 * Segundos desde la última pregunta de [userId] en cualquier producto, o
 * null si nunca ha preguntado. Frena el tecleo compulsivo en varios hilos.
 *
 * El cálculo va entero dentro de SQLite por lo mismo que en comentarios:
 * created_at es UTC y el proceso corre en horario de Monterrey, así que
 * restarlo contra un Date de Node daría seis horas de más.
 */
async function segundosDesdeUltimaPregunta(userId) {
  const row = await db.prepare(`
    SELECT CAST((julianday('now') - julianday(MAX(created_at))) * 86400.0 AS INTEGER) AS segundos
    FROM product_questions WHERE asked_by = ?
  `).get(userId);
  return row && row.segundos != null ? row.segundos : null;
}

/**
 * Cuántas preguntas lleva [userId] en [productId] dentro de las últimas
 * [horas]. Es el límite que de verdad importa: el daño no es preguntar
 * mucho en la app, es inundar UNA publicación ajena.
 */
async function contarPreguntasRecientes(userId, productId, horas) {
  const row = await db.prepare(`
    SELECT COUNT(*) AS total FROM product_questions
    WHERE asked_by = ? AND product_id = ?
      AND created_at >= datetime('now', '-' || ? || ' hours')
  `).get(userId, productId, horas);
  return row ? row.total : 0;
}

// ─── Category Interests ─────────────────────────────────────────

async function addCategoryInterest(userId, categoryId) {
  await db.prepare('INSERT OR IGNORE INTO category_interests (user_id, category_id) VALUES (?, ?)').run(userId, categoryId);
}
async function removeCategoryInterest(userId, categoryId) {
  await db.prepare('DELETE FROM category_interests WHERE user_id = ? AND category_id = ?').run(userId, categoryId);
}
async function getCategoryInterests(userId) {
  return (await db.prepare('SELECT category_id FROM category_interests WHERE user_id = ?').all(userId)).map(r => r.category_id);
}
async function getUsersInterestedInCategory(categoryId) {
  return (await db.prepare('SELECT user_id FROM category_interests WHERE category_id = ?').all(categoryId)).map(r => r.user_id);
}

// ─── Notifications ──────────────────────────────────────────────

async function createNotification(id, userId, type, title, body, data) {
  await db.prepare(`
    INSERT INTO notifications (id, user_id, type, title, body, data, read, created_at)
    VALUES (?, ?, ?, ?, ?, ?, 0, datetime('now'))
  `).run(id, userId, type, title, body, JSON.stringify(data || {}));
}
async function getNotifications(userId) {
  return (await db.prepare('SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 50').all(userId)).map(row => ({
    id: row.id,
    userId: row.user_id,
    type: row.type,
    title: row.title,
    body: row.body,
    data: JSON.parse(row.data || '{}'),
    read: !!row.read,
    createdAt: row.created_at
  }));
}
async function markNotificationRead(notificationId, userId) {
  return (await db.prepare('UPDATE notifications SET read = 1 WHERE id = ? AND user_id = ?').run(notificationId, userId)).changes > 0;
}
async function markAllNotificationsRead(userId) {
  await db.prepare('UPDATE notifications SET read = 1 WHERE user_id = ? AND read = 0').run(userId);
}

/** Marca como leídas las notificaciones in-app de una conversación concreta.
 *
 *  Abrir un chat ya marca sus *mensajes* como leídos, pero cada mensaje deja
 *  además una fila en `notifications` (ver notifyNewMessage) que alimenta el
 *  badge de la campana. Sin esto, el contador sigue subiendo aunque el usuario
 *  ya haya leído la conversación.
 *
 *  El `conversationId` vive dentro del JSON de `data`, de ahí el json_extract.
 *  Retorna cuántas filas se marcaron, para que quien llame sepa si hace falta
 *  refrescar el badge. */
async function markNotificationsReadForConversation(userId, conversationId) {
  const info = await db.prepare(`
    UPDATE notifications SET read = 1
    WHERE user_id = ?
      AND read = 0
      AND json_extract(data, '$.conversationId') = ?
  `).run(userId, conversationId);
  return info.changes;
}
async function getUnreadNotificationCount(userId) {
  const row = await db.prepare('SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND read = 0').get(userId);
  return row?.count ?? 0;
}

// ─── Conversations ──────────────────────────────────────────────

async function createConversation(id, productId, buyerId, sellerId) {
  await db.prepare(`
    INSERT INTO conversations (id, product_id, buyer_id, seller_id, created_at, last_message_at, last_message_preview)
    VALUES (?, ?, ?, ?, datetime('now'), datetime('now'), '')
  `).run(id, productId, buyerId, sellerId);
}
async function findConversation(productId, buyerId, sellerId) {
  return await db.prepare('SELECT * FROM conversations WHERE product_id = ? AND buyer_id = ? AND seller_id = ?').get(productId, buyerId, sellerId);
}

/** Chat directo entre dos personas, sin producto ni "se busca" de por medio:
 *  el que abre el botón "Contactar por chat" del perfil público. */
async function createDirectConversation(id, buyerId, sellerId) {
  await db.prepare(`
    INSERT INTO conversations (id, product_id, wanted_post_id, buyer_id, seller_id, created_at, last_message_at, last_message_preview)
    VALUES (?, NULL, NULL, ?, ?, datetime('now'), datetime('now'), '')
  `).run(id, buyerId, sellerId);
}

/** El chat directo entre dos personas, mirado en los DOS sentidos.
 *
 *  Dos detalles que no son estilo:
 *
 *  1. `product_id IS NULL`, no `product_id = ?`. En SQL, `NULL = NULL` es
 *     desconocido, nunca verdadero: una búsqueda por igualdad no encontraría
 *     jamás el hilo directo y cada mensaje abriría uno nuevo.
 *  2. Los dos sentidos de (buyer, seller). Sin producto no hay quién compra
 *     ni quién vende — son dos personas hablando — y quien escribe primero se
 *     queda como `buyer_id`. Si después el otro contesta desde el perfil de
 *     quien lo escribió, los roles llegan invertidos, y buscar en un solo
 *     sentido dejaría dos hilos paralelos entre las mismas dos personas. */
async function findDirectConversation(unoId, otroId) {
  return await db.prepare(`
    SELECT * FROM conversations
    WHERE product_id IS NULL AND wanted_post_id IS NULL
      AND ((buyer_id = ? AND seller_id = ?) OR (buyer_id = ? AND seller_id = ?))
  `).get(unoId, otroId, otroId, unoId);
}
const MENSAJES_PRIMER_CONTACTO = 5;

/** Estado de contacto entre dos personas, compartido por TODOS sus hilos.
 *
 * El límite no se calcula por conversación: de hacerlo así bastaría abrir
 * otro producto del mismo vendedor para mandar otros tres mensajes. La relación
 * queda aceptada en cuanto existe al menos un mensaje de cada lado, sin
 * importar cuál de los dos inició el contacto. */
async function getChatRelationship(ownerId, targetId) {
  if (!ownerId || !targetId || ownerId === targetId) {
    return {
      blockedByMe: false,
      blockedMe: false,
      mutedByMe: false,
      accepted: true,
      awaitingReply: false,
      firstContactLimit: MENSAJES_PRIMER_CONTACTO,
      remainingMessages: null,
      canSend: ownerId === targetId ? false : true
    };
  }
  const mine = await db.prepare(`
    SELECT blocked, muted FROM chat_user_settings
    WHERE owner_id = ? AND target_id = ?
  `).get(ownerId, targetId);
  const theirs = await db.prepare(`
    SELECT blocked FROM chat_user_settings
    WHERE owner_id = ? AND target_id = ?
  `).get(targetId, ownerId);
  const counts = await db.prepare(`
    SELECT
      COALESCE(SUM(CASE WHEN m.sender_id = ? THEN 1 ELSE 0 END), 0) AS mine,
      COALESCE(SUM(CASE WHEN m.sender_id = ? THEN 1 ELSE 0 END), 0) AS theirs
    FROM messages m
    JOIN conversations c ON c.id = m.conversation_id
    WHERE (c.buyer_id = ? AND c.seller_id = ?)
       OR (c.buyer_id = ? AND c.seller_id = ?)
  `).get(ownerId, targetId, ownerId, targetId, targetId, ownerId);
  const sentByMe = Number(counts?.mine || 0);
  const sentByThem = Number(counts?.theirs || 0);
  const accepted = sentByMe > 0 && sentByThem > 0;
  const remainingMessages = accepted ? null : Math.max(0, MENSAJES_PRIMER_CONTACTO - sentByMe);
  const blockedByMe = !!mine?.blocked;
  const blockedMe = !!theirs?.blocked;
  const blocked = blockedByMe || blockedMe;
  return {
    blockedByMe,
    blockedMe,
    mutedByMe: !!mine?.muted,
    accepted,
    awaitingReply: !accepted && sentByMe >= MENSAJES_PRIMER_CONTACTO,
    firstContactLimit: MENSAJES_PRIMER_CONTACTO,
    remainingMessages,
    canSend: !blocked && (accepted || sentByMe < MENSAJES_PRIMER_CONTACTO)
  };
}
async function setChatUserSetting(ownerId, targetId, setting, enabled) {
  if (!ownerId || !targetId || ownerId === targetId) return false;
  if (setting !== 'blocked' && setting !== 'muted') return false;
  await db.prepare(`
    INSERT INTO chat_user_settings (owner_id, target_id, ${setting}, updated_at)
    VALUES (?, ?, ?, datetime('now'))
    ON CONFLICT(owner_id, target_id) DO UPDATE SET
      ${setting} = excluded.${setting},
      updated_at = excluded.updated_at
  `).run(ownerId, targetId, enabled ? 1 : 0);
  return true;
}
async function areUsersBlocked(oneId, otherId) {
  if (!oneId || !otherId) return false;
  const row = await db.prepare(`
    SELECT 1 FROM chat_user_settings
    WHERE ((owner_id = ? AND target_id = ?)
        OR (owner_id = ? AND target_id = ?))
      AND blocked = 1
    LIMIT 1
  `).get(oneId, otherId, otherId, oneId);
  return !!row;
}
async function isChatUserMuted(ownerId, targetId) {
  const row = await db.prepare(`
    SELECT muted FROM chat_user_settings
    WHERE owner_id = ? AND target_id = ?
  `).get(ownerId, targetId);
  return !!row?.muted;
}
async function getChatSafetySettings(ownerId) {
  if (!ownerId) return [];
  return (await db.prepare(`
    SELECT s.target_id AS userId, s.blocked, s.muted, s.updated_at AS updatedAt,
           COALESCE(u.name, s.target_id) AS name,
           u.avatarInitials, u.logoUrl, u.verified, u.isBusiness,
           u.socio_fundador AS socioFundador
      FROM chat_user_settings s
      LEFT JOIN sellers u ON u.id = s.target_id
     WHERE s.owner_id = ? AND (s.blocked = 1 OR s.muted = 1)
     ORDER BY s.updated_at DESC, s.target_id ASC
  `).all(ownerId)).map(row => ({
    userId: row.userId,
    name: row.name,
    avatarInitials: row.avatarInitials || '',
    logoUrl: row.logoUrl || null,
    verified: !!row.verified,
    isBusiness: !!row.isBusiness,
    socioFundador: !!row.socioFundador,
    blocked: !!row.blocked,
    muted: !!row.muted,
    updatedAt: row.updatedAt
  }));
}
const REPORT_TARGET_TYPES = new Set(['user', 'product', 'wanted', 'chat']);
const REPORT_STATUSES = new Set(['received', 'reviewing', 'resolved', 'dismissed']);
async function createReport({
  reporterId,
  targetType,
  targetId,
  targetUserId = null,
  reason,
  details = ''
}) {
  if (!REPORT_TARGET_TYPES.has(targetType)) throw new Error('Tipo de reporte invalido.');
  const safeReason = String(reason || '').trim();
  const safeDetails = String(details || '').trim();
  if (safeReason.length < 3 || safeReason.length > 120) throw new Error('Motivo invalido.');
  if (!targetId || String(targetId).length > 180) throw new Error('Objetivo invalido.');
  if (safeDetails.length > 1000) throw new Error('Detalle invalido.');
  const id = `rep_${Date.now()}_${crypto.randomBytes(6).toString('hex')}`;
  await db.prepare(`
    INSERT INTO reports (
      id, reporter_id, target_type, target_id, target_user_id, reason, details,
      status, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 'received', datetime('now'), datetime('now'))
  `).run(id, reporterId, targetType, String(targetId), targetUserId || null, safeReason, safeDetails);
  return await getReportById(id);
}
async function getReportById(id) {
  return await db.prepare(`
    SELECT r.*, reporter.name AS reporterName, target.name AS targetUserName
      FROM reports r
      LEFT JOIN sellers reporter ON reporter.id = r.reporter_id
      LEFT JOIN sellers target ON target.id = r.target_user_id
     WHERE r.id = ?
  `).get(id);
}
async function listReports({
  status = 'all',
  targetType = 'all',
  limit = 50,
  offset = 0
} = {}) {
  const where = [];
  const params = [];
  if (status !== 'all') {
    if (!REPORT_STATUSES.has(status)) return null;
    where.push('r.status = ?');
    params.push(status);
  }
  if (targetType !== 'all') {
    if (!REPORT_TARGET_TYPES.has(targetType)) return null;
    where.push('r.target_type = ?');
    params.push(targetType);
  }
  const clause = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const total = (await db.prepare(`SELECT COUNT(*) AS total FROM reports r ${clause}`).get(...params)).total;
  const reports = await db.prepare(`
    SELECT r.*, reporter.name AS reporterName, target.name AS targetUserName
      FROM reports r
      LEFT JOIN sellers reporter ON reporter.id = r.reporter_id
      LEFT JOIN sellers target ON target.id = r.target_user_id
      ${clause}
     ORDER BY r.created_at DESC, r.id DESC
     LIMIT ? OFFSET ?
  `).all(...params, limit, offset);
  return {
    reports,
    total
  };
}
async function updateReportStatus({
  id,
  status,
  adminNote = '',
  adminId
}) {
  if (!REPORT_STATUSES.has(status)) return null;
  const before = await getReportById(id);
  if (!before) return null;
  const resolved = status === 'resolved' || status === 'dismissed';
  await db.prepare(`
    UPDATE reports
       SET status = ?, admin_note = ?, updated_at = datetime('now'),
           resolved_at = CASE WHEN ? THEN datetime('now') ELSE NULL END,
           resolved_by_admin_id = CASE WHEN ? THEN (?::bigint) ELSE NULL END
     WHERE id = ?
  `).run(status, String(adminNote || '').trim().slice(0, 1000), resolved ? 1 : 0, resolved ? 1 : 0, adminId, id);
  return {
    before,
    after: await getReportById(id)
  };
}
async function anonymizeSellerAccount(userId) {
  const seller = await db.prepare('SELECT * FROM sellers WHERE id = ?').get(userId);
  if (!seller) return null;
  const now = new Date().toISOString();
  await db.transaction(async () => {
    await db.prepare('DELETE FROM push_tokens WHERE user_id = ?').run(userId);
    await db.prepare('UPDATE refresh_sessions SET revoked_at = datetime(\'now\') WHERE user_id = ? AND revoked_at IS NULL').run(userId);
    await db.prepare('DELETE FROM category_interests WHERE user_id = ?').run(userId);
    await db.prepare('DELETE FROM cart WHERE user_id = ?').run(userId);
    await db.prepare('DELETE FROM chat_user_settings WHERE owner_id = ? OR target_id = ?').run(userId, userId);
    await db.prepare('DELETE FROM conversations WHERE buyer_id = ? OR seller_id = ?').run(userId, userId);
    await db.prepare('DELETE FROM verification_documents WHERE usuario_id = ?').run(userId);
    await db.prepare('DELETE FROM verificaciones WHERE usuario_id = ?').run(userId);
    await db.prepare('DELETE FROM product_ratings WHERE user_id = ?').run(userId);
    await db.prepare("UPDATE product_comments SET texto = '[Comentario eliminado]', deleted_at = datetime('now'), deleted_by = ? WHERE user_id = ? AND deleted_at IS NULL").run(userId, userId);
    await db.prepare("UPDATE product_questions SET question_text = '[Pregunta eliminada]' WHERE asked_by = ?").run(userId);
    await db.prepare("UPDATE product_questions SET answer_text = '[Respuesta eliminada]' WHERE seller_id = ? AND answer_text IS NOT NULL").run(userId);
    await db.prepare(`UPDATE products SET
      title = '[Publicacion eliminada]',
      description = '',
      images = '[]',
      imageIcon = NULL,
      imageColor = NULL,
      extras = '[]',
      manual_status = 'paused',
      moderation_status = 'removed',
      moderation_reason = 'Cuenta eliminada por el usuario',
      updated_at = datetime('now')
      WHERE seller = ?`).run(userId);
    await db.prepare(`UPDATE wanted_posts SET
      title = '[Busqueda eliminada]',
      description = '',
      status = 'cerrada',
      moderation_status = 'removed',
      moderation_reason = 'Cuenta eliminada por el usuario'
      WHERE user_id = ?`).run(userId);
    await db.prepare(`
      UPDATE sellers SET
        name = ?,
        email = NULL,
        phone = NULL,
        avatarInitials = 'EU',
        major = NULL,
        logoUrl = NULL,
        businessDescription = NULL,
        businessCategory = NULL,
        businessHours = NULL,
        paymentMethods = '[]',
        whatsapp_number = NULL,
        facebook_url = NULL,
        instagram_url = NULL,
        tiktok_url = NULL,
        twitter_url = NULL,
        producto_fijado_id = NULL,
        verified = 0,
        socio_fundador = 0,
        admin_status = 'banned',
        admin_status_reason = 'Cuenta eliminada por solicitud del usuario',
        admin_status_until = NULL,
        deleted_at = ?
      WHERE id = ?
    `).run(`Cuenta eliminada ${userId.slice(-6)}`, now, userId);
  })();
  return {
    id: userId,
    deletedAt: now
  };
}
async function getConversationsForUser(userId) {
  return (await db.prepare(`
    SELECT c.* FROM conversations c
    LEFT JOIN conversation_deletions d
      ON d.conversation_id = c.id AND d.user_id = ?
    WHERE (c.buyer_id = ? OR c.seller_id = ?)
      AND (
        d.conversation_id IS NULL
        OR EXISTS (
          SELECT 1 FROM messages nuevos
          WHERE nuevos.conversation_id = c.id
            AND nuevos.rowid > COALESCE((
              SELECT corte.rowid FROM messages corte
              WHERE corte.id = d.deleted_through_message_id
            ), 0)
        )
      )
    ORDER BY c.last_message_at DESC
  `).all(userId, userId, userId)).map(row => ({
    id: row.id,
    productId: row.product_id,
    wantedPostId: row.wanted_post_id,
    buyerId: row.buyer_id,
    sellerId: row.seller_id,
    createdAt: row.created_at,
    lastMessageAt: row.last_message_at,
    lastMessagePreview: row.last_message_preview || ''
  }));
}

/** Retira una conversación solo de la bandeja de `userId`.
 *
 *  No borra mensajes compartidos. Guarda el id del último que vio la persona
 *  para que un mensaje posterior reactive el chat sin restaurar el historial
 *  que ya había eliminado. También consume sus mensajes/notificaciones pendientes
 *  para que los badges bajen en la misma operación.
 *
 *  Retorna false si la conversación no existe o el usuario no participa. */
async function deleteConversationForUser(conversationId, userId) {
  const conversation = await db.prepare(`
    SELECT id FROM conversations
    WHERE id = ? AND (buyer_id = ? OR seller_id = ?)
  `).get(conversationId, userId, userId);
  if (!conversation) return false;
  await db.transaction(async () => {
    const ultimo = await db.prepare(`
      SELECT id FROM messages
      WHERE conversation_id = ?
      ORDER BY rowid DESC
      LIMIT 1
    `).get(conversationId);
    await db.prepare(`
      INSERT INTO conversation_deletions
        (conversation_id, user_id, deleted_through_message_id, deleted_at)
      VALUES (?, ?, ?, datetime('now'))
      ON CONFLICT(conversation_id, user_id) DO UPDATE SET
        deleted_through_message_id = excluded.deleted_through_message_id,
        deleted_at = excluded.deleted_at
    `).run(conversationId, userId, ultimo?.id ?? null);
    await db.prepare(`
      UPDATE messages SET read = 1
      WHERE conversation_id = ? AND sender_id != ? AND read = 0
    `).run(conversationId, userId);
    await markNotificationsReadForConversation(userId, conversationId);
  })();
  return true;
}
async function updateConversationPreview(conversationId, previewText) {
  await db.prepare(`
    UPDATE conversations SET last_message_at = datetime('now'), last_message_preview = ? WHERE id = ?
  `).run(previewText, conversationId);
}
async function getUnreadMessageCount(userId) {
  const row = await db.prepare(`
    SELECT COUNT(*) as count FROM messages m
    JOIN conversations c ON c.id = m.conversation_id
    LEFT JOIN conversation_deletions d
      ON d.conversation_id = c.id AND d.user_id = ?
    WHERE (c.buyer_id = ? OR c.seller_id = ?)
      AND m.sender_id != ?
      AND m.read = 0
      AND m.rowid > COALESCE((
        SELECT corte.rowid FROM messages corte
        WHERE corte.id = d.deleted_through_message_id
      ), 0)
  `).get(userId, userId, userId, userId);
  return row?.count ?? 0;
}

// ─── Wanted Posts ───────────────────────────────────────────────

async function createWantedPost(post) {
  await db.prepare(`
    INSERT INTO wanted_posts (id, user_id, title, description, category_id, type, price_min, price_max, status, created_at, location_lat, location_lng, paymentMethods, expires_at)
    VALUES (@id, @userId, @title, @description, @categoryId, @type, @priceMin, @priceMax, 'abierta', datetime('now'), @location_lat, @location_lng, @paymentMethods, @expires_at)
  `).run({
    id: post.id,
    userId: post.userId,
    title: post.title,
    description: post.description || null,
    categoryId: post.categoryId,
    type: post.type,
    priceMin: post.priceMin ?? null,
    priceMax: post.priceMax ?? null,
    location_lat: post.locationLat ?? null,
    location_lng: post.locationLng ?? null,
    paymentMethods: post.paymentMethods ? JSON.stringify(post.paymentMethods) : null,
    expires_at: post.expiresAt || null
  });
  return await getWantedPostById(post.id);
}
async function getWantedPostById(id) {
  const row = await db.prepare(`SELECT * FROM wanted_posts w
    WHERE w.id = ? AND w.moderation_status = 'visible'
      AND EXISTS (
        SELECT 1 FROM sellers s WHERE s.id = w.user_id AND (
          s.admin_status = 'active'
          OR (s.admin_status = 'suspended' AND s.admin_status_until IS NOT NULL
            AND datetime(s.admin_status_until) <= datetime('now'))
        )
      )`).get(id);
  return rowToWantedPost(row);
}
async function listWantedPosts({
  categoryId,
  status,
  type
} = {}) {
  let query = `SELECT * FROM wanted_posts w WHERE moderation_status = 'visible'
    AND EXISTS (
      SELECT 1 FROM sellers s WHERE s.id = w.user_id AND (
        s.admin_status = 'active'
        OR (s.admin_status = 'suspended' AND s.admin_status_until IS NOT NULL
          AND datetime(s.admin_status_until) <= datetime('now'))
      )
    )`;
  const params = [];
  if (categoryId) {
    query += ' AND category_id = ?';
    params.push(categoryId);
  }
  query += ' AND status = ?';
  params.push(status || 'abierta');
  query += " AND (expires_at IS NULL OR datetime(expires_at) > datetime('now'))";
  if (type) {
    query += ' AND type = ?';
    params.push(type);
  }
  query += ' ORDER BY created_at DESC';
  return (await db.prepare(query).all(...params)).map(rowToWantedPost);
}
async function incrementWantedPostViews(id) {
  await db.prepare('UPDATE wanted_posts SET views = views + 1 WHERE id = ?').run(id);
}

/**
 * Edita una publicación "se busca" existente. Solo actualiza los campos
 * de contenido (title/description/categoryId/type/priceMin/priceMax);
 * no toca user_id, status, resolved_with_user_id, created_at ni resolved_at.
 */
async function updateWantedPost(id, updates) {
  await db.prepare(`
    UPDATE wanted_posts SET
      title = @title,
      description = @description,
      category_id = @categoryId,
      type = @type,
      price_min = @priceMin,
      price_max = @priceMax,
      paymentMethods = @paymentMethods,
      updated_at = datetime('now')
    WHERE id = @id
  `).run({
    id,
    title: updates.title,
    description: updates.description ?? null,
    categoryId: updates.categoryId,
    type: updates.type,
    priceMin: updates.priceMin ?? null,
    priceMax: updates.priceMax ?? null,
    paymentMethods: updates.paymentMethods ? JSON.stringify(updates.paymentMethods) : null
  });
  return await getWantedPostById(id);
}
async function resolveWantedPost(id, resolvedWithUserId) {
  await db.prepare(`
    UPDATE wanted_posts SET status = 'resuelta', resolved_with_user_id = ?, resolved_at = datetime('now')
    WHERE id = ?
  `).run(resolvedWithUserId || null, id);
  return await getWantedPostById(id);
}
async function countWantedPostsSince(userId, isoTimestamp) {
  const row = await db.prepare('SELECT COUNT(*) as count FROM wanted_posts WHERE user_id = ? AND created_at >= ?').get(userId, isoTimestamp);
  return row?.count ?? 0;
}
async function countActiveWantedPosts(userId) {
  return (await db.prepare(`SELECT COUNT(*) AS count FROM wanted_posts
    WHERE user_id = ? AND status = 'abierta'
      AND moderation_status = 'visible'
      AND (expires_at IS NULL OR datetime(expires_at) > datetime('now'))`).get(userId))?.count ?? 0;
}
async function createWantedConversation(id, wantedPostId, buyerId, sellerId) {
  await db.prepare(`
    INSERT INTO conversations (id, product_id, wanted_post_id, buyer_id, seller_id, created_at, last_message_at, last_message_preview)
    VALUES (?, NULL, ?, ?, ?, datetime('now'), datetime('now'), '')
  `).run(id, wantedPostId, buyerId, sellerId);
}
async function findWantedConversation(wantedPostId, buyerId, sellerId) {
  return await db.prepare('SELECT * FROM conversations WHERE wanted_post_id = ? AND buyer_id = ? AND seller_id = ?').get(wantedPostId, buyerId, sellerId);
}

// ─── Push Tokens (FCM) ────────────────────────────────────────────

async function registerPushToken(userId, playerId, platform) {
  await db.prepare(`
    INSERT OR IGNORE INTO push_tokens (user_id, player_id, platform, created_at)
    VALUES (?, ?, ?, datetime('now'))
  `).run(userId, playerId, platform || 'unknown');
}
async function unregisterPushToken(userId, playerId) {
  await db.prepare('DELETE FROM push_tokens WHERE user_id = ? AND player_id = ?').run(userId, playerId);
}
async function getPushTokensForUser(userId) {
  return (await db.prepare('SELECT player_id FROM push_tokens WHERE user_id = ?').all(userId)).map(r => r.player_id);
}
async function unregisterAllPushTokensForUser(userId) {
  await db.prepare('DELETE FROM push_tokens WHERE user_id = ?').run(userId);
}

// ─── Messages ───────────────────────────────────────────────────

async function createMessage(id, conversationId, senderId, text, imageUrl = null, replyToMessageId = null) {
  await db.prepare(`
    INSERT INTO messages (id, conversation_id, sender_id, text, image_url, reply_to_message_id, created_at, read)
    VALUES (?, ?, ?, ?, ?, ?, datetime('now'), 0)
  `).run(id, conversationId, senderId, text, imageUrl, replyToMessageId);
  await updateConversationPreview(conversationId, imageUrl ? '📷 Foto' : text);

  // El recálculo va aquí y no en la ruta para que valga también para los
  // mensajes con imagen y para cualquier call site futuro. Solo corre cuando
  // quien escribe es el vendedor: un mensaje del comprador abre una espera,
  // no la cierra, y no puede cambiar la mediana.
  const conv = await db.prepare('SELECT seller_id FROM conversations WHERE id = ?').get(conversationId);
  if (conv && conv.seller_id === senderId) {
    await syncSellerResponseTime(senderId);
  }
}

/** Da forma a una fila de `messages` tal como la consume el cliente.
 *
 *  `replyTo` viene resuelto (no solo el id) para que la burbuja pueda pintar
 *  la cita sin una petición extra por mensaje. Los alias `reply_*` los produce
 *  el LEFT JOIN de [getMessages]; cuando la fila no trae join (emisión por
 *  socket de un mensaje recién creado) se resuelve con [getRepliedMessage]. */
function rowToMessage(row, replyTo = undefined) {
  return {
    id: row.id,
    conversationId: row.conversation_id,
    senderId: row.sender_id,
    text: row.text,
    imageUrl: row.image_url || null,
    createdAt: row.created_at,
    read: !!row.read,
    replyToMessageId: row.reply_to_message_id || null,
    replyTo: replyTo !== undefined ? replyTo : row.reply_id ? {
      id: row.reply_id,
      senderId: row.reply_sender_id,
      text: row.reply_text,
      imageUrl: row.reply_image_url || null
    } : null
  };
}
async function getMessages(conversationId, userId = null) {
  const deletion = userId ? await db.prepare(`
        SELECT deleted_through_message_id FROM conversation_deletions
        WHERE conversation_id = ? AND user_id = ?
      `).get(conversationId, userId) : null;
  const deletedThroughRowid = deletion?.deleted_through_message_id ? (await db.prepare('SELECT rowid FROM messages WHERE id = ?').get(deletion.deleted_through_message_id))?.rowid ?? 0 : 0;

  // LEFT JOIN y no una consulta por mensaje: un chat de 200 mensajes con
  // respuestas haría 200 SELECT extra.
  return (await db.prepare(`
    SELECT m.*,
           r.id         AS reply_id,
           r.sender_id  AS reply_sender_id,
           r.text       AS reply_text,
           r.image_url  AS reply_image_url
    FROM messages m
    LEFT JOIN messages r ON r.id = m.reply_to_message_id
    WHERE m.conversation_id = ? AND m.rowid > ?
    ORDER BY m.created_at ASC
  `).all(conversationId, deletedThroughRowid)).map(row => rowToMessage(row));
}

/** Devuelve el resumen del mensaje citado, o null si no existe. */
async function getRepliedMessage(messageId) {
  if (!messageId) return null;
  const row = await db.prepare('SELECT id, sender_id, text, image_url FROM messages WHERE id = ?').get(messageId);
  if (!row) return null;
  return {
    id: row.id,
    senderId: row.sender_id,
    text: row.text,
    imageUrl: row.image_url || null
  };
}

/** ¿Este mensaje existe y pertenece a esta conversación?
 *
 *  Sirve para rechazar una respuesta que cite un mensaje de otro chat: sin
 *  esta comprobación, un cliente podría filtrar el texto de una conversación
 *  ajena haciendo que se pinte como cita dentro de la suya. */
async function messageBelongsToConversation(messageId, conversationId) {
  const row = await db.prepare('SELECT 1 AS ok FROM messages WHERE id = ? AND conversation_id = ?').get(messageId, conversationId);
  return !!row;
}
async function markConversationMessagesRead(conversationId, userId) {
  await db.prepare(`
    UPDATE messages SET read = 1
    WHERE conversation_id = ? AND sender_id != ? AND read = 0
  `).run(conversationId, userId);
}

/** Soft-delete: reemplaza el texto del mensaje por un placeholder.
 *  Solo el sender puede borrar su propio mensaje.
 *  Retorna true si se eliminó, false si no existía. */
async function deleteMessage(messageId, userId) {
  const msg = await db.prepare('SELECT * FROM messages WHERE id = ?').get(messageId);
  if (!msg) return false;
  if (msg.sender_id !== userId) return false; // solo el dueño
  await db.prepare("UPDATE messages SET text = '[Mensaje eliminado]', image_url = NULL WHERE id = ?").run(messageId);
  return true;
}

// ─── Feed Ranking ───────────────────────────────────────────────

// Pesos y parámetros de la fórmula de score. Viven aquí (no en el SQL crudo
// de las rutas) para que ajustar el ranking no implique tocar la consulta.
const FEED_WEIGHTS = {
  RECENCY_BASE: 100,
  // puntos iniciales de un producto recién publicado
  RECENCY_DECAY_PER_DAY: 2,
  // puntos que pierde por cada día de antigüedad
  W_VIEWS: 0.5,
  // peso por vista
  W_FAVORITOS: 3,
  // peso por guardado en favoritos
  W_CONTACTOS: 6,
  // peso por mensaje enviado al vendedor
  W_ENGAGEMENT: 25,
  // peso de (contactos/vistas), calidad del interés
  W_SELLER_RATING: 15,
  // bonus máximo por rating de vendedor (5 estrellas)
  W_SELLER_PHOTO: 5,
  // bonus por tener foto/logo de perfil
  W_SELLER_FAST_REPLY: 8,
  // bonus por responder rápido
  FAST_REPLY_MAX_MINUTES: 60,
  // umbral para considerar "responde rápido"
  INSTANT_REPLY_MAX_MINUTES: 10,
  // umbral, más estricto, para "respuesta instantánea"
  TOP_RATED_MIN_RATING: 4.5,
  // rating mínimo para "vendedor confiable"
  TOP_RATED_MIN_REVIEWS: 10,
  // reseñas mínimas para que el rating anterior cuente
  NOVATO_MAX_DIAS: 60,
  // ventana desde el alta en la que la insignia de Novato puede mostrarse
  // ── Insignias élite ────────────────────────────────────────────
  // Umbrales pensados para que casi nadie las tenga: son el techo del
  // sistema, no un escalón más. Si con el tiempo se vuelven comunes, lo que
  // hay que subir es el número, no añadir otra insignia encima.
  LEYENDA_MIN_VENTAS: 100,
  // ventas confirmadas para "Leyenda del Mercadito"
  ORO_MIN_FACTURADO: 100000,
  // MXN facturados (órdenes pagadas) para "Vendedor de oro"
  IMPECABLE_MIN_RESENAS: 50,
  // reseñas mínimas para que un 5.0 perfecto cuente
  CENTENARIO_MIN_CINCOS: 100,
  // calificaciones de 5 estrellas para "Centenario"
  SIEMPRE_RESPONDE_MIN_PREGUNTAS: 20,
  // preguntas recibidas mínimas para que la tasa signifique algo
  SIEMPRE_RESPONDE_MIN_TASA: 0.95,
  // proporción de preguntas respondidas
  AFFINITY_MULTIPLIER: 1.3,
  // multiplicador si la categoría es top-3 del device/usuario
  NO_STOCK_PENALTY_FACTOR: 0.01,
  // castigo drástico si no hay stock/está vendido
  POPULARITY_WINDOW_DAYS: 180,
  // ventana de interacciones que cuentan para popularidad
  AFFINITY_WINDOW_DAYS: 90,
  // ventana de interacciones que cuentan para afinidad
  AFFINITY_TOP_N: 3,
  // top-N categorías más vistas por device/usuario
  INTERACTION_RETENTION_DAYS: 180,
  // política de limpieza: no guardar más de X días
  INTERACTION_MAX_PER_DEVICE: 500 // ...ni más de N filas por device_id
};

/**
 * Registra una interacción (vista/favorito/contacto) de un device_id
 * (siempre) y, si hay sesión, también del user_id. No requiere cuenta.
 */
async function registrarInteraccion({
  deviceId,
  userId,
  productId,
  category,
  tipo
}) {
  await db.prepare(`
    INSERT INTO interacciones_dispositivo (device_id, user_id, product_id, category, tipo, created_at)
    VALUES (?, ?, ?, ?, ?, datetime('now'))
  `).run(deviceId, userId || null, productId, category, tipo);
}

/**
 * Vincula el historial anónimo de un device_id a un user_id, para que al
 * registrarse no se pierda el historial de favoritos/vistas/contactos
 * acumulado como anónimo (afecta el ranking de afinidad del feed).
 * Se llama una vez al registrarse/iniciar sesión con un deviceId conocido.
 */
async function linkDeviceToUser(deviceId, userId) {
  if (!deviceId || !userId) return;
  await db.prepare(`
    UPDATE interacciones_dispositivo SET user_id = ? WHERE device_id = ? AND user_id IS NULL
  `).run(userId, deviceId);
}

/**
 * Poda interacciones_dispositivo para no acumular indefinidamente:
 * borra lo más viejo que INTERACTION_RETENTION_DAYS y, por device_id,
 * conserva solo las INTERACTION_MAX_PER_DEVICE filas más recientes.
 * Pensado para llamarse periódicamente (cron/arranque), no en cada request.
 */
async function limpiarInteraccionesAntiguas({
  retentionDays = FEED_WEIGHTS.INTERACTION_RETENTION_DAYS,
  maxPerDevice = FEED_WEIGHTS.INTERACTION_MAX_PER_DEVICE
} = {}) {
  await db.prepare(`
    DELETE FROM interacciones_dispositivo
    WHERE created_at < datetime('now', '-' || ? || ' days')
  `).run(retentionDays);
  await db.prepare(`
    DELETE FROM interacciones_dispositivo
    WHERE id IN (
      SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (
          PARTITION BY device_id ORDER BY created_at DESC
        ) AS rn
        FROM interacciones_dispositivo
      ) WHERE rn > ?
    )
  `).run(maxPerDevice);
}

/**
 * Calcula el feed rankeado (Fase 1: score base + Fase 2: afinidad por
 * device_id/user_id). device_id es obligatorio, user_id opcional. Usa
 * LEFT JOIN en todas las agregaciones para que un device_id sin historial
 * (cold start) reciba el feed base sin errores ni penalización.
 */
async function getFeedRanked({
  deviceId,
  userId,
  limit = 60,
  offset = 0
}) {
  const w = FEED_WEIGHTS;
  const rows = await db.prepare(`
    WITH product_stats AS (
      SELECT
        product_id,
        SUM(CASE WHEN tipo = 'vista' THEN 1 ELSE 0 END) AS vistas,
        SUM(CASE WHEN tipo = 'favorito' THEN 1 ELSE 0 END) AS favoritos,
        SUM(CASE WHEN tipo = 'contacto' THEN 1 ELSE 0 END) AS contactos
      FROM interacciones_dispositivo
      WHERE created_at >= datetime('now', '-' || @popularityWindowDays || ' days')
      GROUP BY product_id
    ),
    device_top_categories AS (
      SELECT category
      FROM (
        SELECT category, COUNT(*) AS cnt,
          ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
        FROM interacciones_dispositivo
        WHERE created_at >= datetime('now', '-' || @affinityWindowDays || ' days')
          AND (device_id = @deviceId OR (@userId IS NOT NULL AND user_id = @userId))
        GROUP BY category
      )
      WHERE rn <= @affinityTopN
    )
    SELECT
      p.*,
      COALESCE(ps.vistas, 0) AS vistas,
      COALESCE(ps.favoritos, 0) AS favoritos,
      COALESCE(ps.contactos, 0) AS contactos,
      CASE WHEN dtc.category IS NOT NULL THEN 1 ELSE 0 END AS es_categoria_afin,
      (
        (
          -- Recencia: decae con los días de antigüedad, sin bajar de 0
          MAX(0, @recencyBase - @recencyDecayPerDay * (julianday('now') - julianday(p.created_at)))
          -- Popularidad: vistas, favoritos y contactos, cada uno con su propio peso
          + CAST(@wViews AS DOUBLE PRECISION) * COALESCE(ps.vistas, 0)
          + CAST(@wFavoritos AS DOUBLE PRECISION) * COALESCE(ps.favoritos, 0)
          + CAST(@wContactos AS DOUBLE PRECISION) * COALESCE(ps.contactos, 0)
          -- Tasa de interacción: qué tan bien conviertes vistas en contactos.
          -- COALESCE externo porque NULLIF(ps.vistas, 0) es NULL sin vistas,
          -- lo que sin este COALESCE volvería NULL toda la suma del score.
          + COALESCE(@wEngagement * (COALESCE(ps.contactos, 0) * 1.0 / NULLIF(ps.vistas, 0)), 0)
          -- Calidad del vendedor: rating, foto de perfil, tiempo de respuesta
          + @wSellerRating * (COALESCE(s.rating, 0) / 5.0)
          + CASE WHEN s.logoUrl IS NOT NULL AND s.logoUrl != '' THEN @wSellerPhoto ELSE 0 END
          + CASE WHEN s.median_response_minutes IS NOT NULL
                  AND s.median_response_minutes <= @fastReplyMaxMinutes
                 THEN @wSellerFastReply ELSE 0 END
        )
        -- Afinidad: bonus multiplicativo si la categoría es top-N del device/usuario
        * CASE WHEN dtc.category IS NOT NULL THEN @affinityMultiplier ELSE 1.0 END
        -- Disponibilidad: castigo drástico si no hay stock o ya se vendió
        * CASE WHEN p.status = 'sold'
                 OR (p.stock_quantity IS NOT NULL AND p.stock_quantity <= 0)
               THEN @noStockPenaltyFactor ELSE 1.0 END
      ) AS score
    FROM products p
    LEFT JOIN product_stats ps ON ps.product_id = p.id
    LEFT JOIN sellers s ON s.id = p.seller
    LEFT JOIN device_top_categories dtc ON dtc.category = p.category
    WHERE p.moderation_status = 'visible'
      AND (s.admin_status = 'active'
        OR (s.admin_status = 'suspended' AND s.admin_status_until IS NOT NULL
          AND datetime(s.admin_status_until) <= datetime('now')))
    ORDER BY score DESC
    LIMIT @limit OFFSET @offset
  `).all({
    deviceId,
    userId: userId || null,
    limit,
    offset,
    popularityWindowDays: w.POPULARITY_WINDOW_DAYS,
    affinityWindowDays: w.AFFINITY_WINDOW_DAYS,
    affinityTopN: w.AFFINITY_TOP_N,
    recencyBase: w.RECENCY_BASE,
    recencyDecayPerDay: w.RECENCY_DECAY_PER_DAY,
    wViews: w.W_VIEWS,
    wFavoritos: w.W_FAVORITOS,
    wContactos: w.W_CONTACTOS,
    wEngagement: w.W_ENGAGEMENT,
    wSellerRating: w.W_SELLER_RATING,
    wSellerPhoto: w.W_SELLER_PHOTO,
    wSellerFastReply: w.W_SELLER_FAST_REPLY,
    fastReplyMaxMinutes: w.FAST_REPLY_MAX_MINUTES,
    affinityMultiplier: w.AFFINITY_MULTIPLIER,
    noStockPenaltyFactor: w.NO_STOCK_PENALTY_FACTOR
  });
  return rows.map(row => ({
    ...rowToProduct(row),
    vistas: row.vistas,
    favoritos: row.favoritos,
    contactos: row.contactos,
    esCategoriaAfin: !!row.es_categoria_afin,
    score: row.score
  }));
}

// ─── Relacionados (detalle de producto) ─────────────────────────

/**
 * Un producto se considera "activo" para recomendar si sigue a la venta hoy.
 *
 * 'reserved' y 'negotiating' SÍ entran: son estados de una venta en curso que
 * todavía puede caerse, y el feed tampoco los esconde. Lo que se excluye es
 * lo que deja al usuario en un callejón sin salida: vendido, pausado por el
 * vendedor y sin inventario. Los estados temporales (fuera de horario, "solo
 * los martes") no se filtran aquí: se recalculan en cada lectura y mañana el
 * producto vuelve a estar disponible.
 */
const SQL_PRODUCTO_ACTIVO = `
  p.moderation_status = 'visible'
  AND EXISTS (
    SELECT 1 FROM sellers visible_seller
    WHERE visible_seller.id = p.seller AND (
      visible_seller.admin_status = 'active'
      OR (visible_seller.admin_status = 'suspended'
        AND visible_seller.admin_status_until IS NOT NULL
        AND datetime(visible_seller.admin_status_until) <= datetime('now'))
    )
  )
  AND
  (p.manual_status IS NULL OR p.manual_status NOT IN ('sold', 'paused'))
  AND (p.status IS NULL OR p.status != 'sold')
  AND (p.stock_quantity IS NULL OR p.stock_quantity > 0)
  AND (p.expires_at IS NULL OR datetime(p.expires_at) > datetime('now'))
`;

/**
 * Score sin personalizar: recencia + popularidad, con los mismos pesos del
 * feed. No lleva afinidad por device_id (el bloque de relacionados no depende
 * de quién mira, sino de qué producto se está viendo) ni calidad del
 * vendedor, que en esta sección sesgaría el resultado hacia las mismas
 * tiendas grandes una y otra vez.
 */
const SQL_SCORE_RELACIONADOS = `
  MAX(0, @recencyBase - @recencyDecayPerDay * (julianday('now') - julianday(p.created_at)))
  + CAST(@wViews AS DOUBLE PRECISION) * COALESCE(ps.vistas, 0)
  + CAST(@wFavoritos AS DOUBLE PRECISION) * COALESCE(ps.favoritos, 0)
  + CAST(@wContactos AS DOUBLE PRECISION) * COALESCE(ps.contactos, 0)
`;
const SQL_STATS_POPULARIDAD = `
  SELECT
    product_id,
    SUM(CASE WHEN tipo = 'vista' THEN 1 ELSE 0 END) AS vistas,
    SUM(CASE WHEN tipo = 'favorito' THEN 1 ELSE 0 END) AS favoritos,
    SUM(CASE WHEN tipo = 'contacto' THEN 1 ELSE 0 END) AS contactos
  FROM interacciones_dispositivo
  WHERE created_at >= datetime('now', '-' || @popularityWindowDays || ' days')
  GROUP BY product_id
`;

/** Parámetros de score comunes a las dos consultas de esta sección. */
function paramsScore() {
  const w = FEED_WEIGHTS;
  return {
    popularityWindowDays: w.POPULARITY_WINDOW_DAYS,
    recencyBase: w.RECENCY_BASE,
    recencyDecayPerDay: w.RECENCY_DECAY_PER_DAY,
    wViews: w.W_VIEWS,
    wFavoritos: w.W_FAVORITOS,
    wContactos: w.W_CONTACTOS
  };
}

/** Palabras del título largas como para significar algo al buscar parecidos. */
const LARGO_MINIMO_KEYWORD = 4;
const MAX_KEYWORDS = 6;

/**
 * Extrae las palabras del título que sirven como señal de parecido.
 *
 * El corte por longitud hace de lista de stopwords sin tener que mantener
 * una: en español las que aparecen en medio catálogo ("de", "la", "con",
 * "por") son cortas, y las que de verdad identifican un producto
 * ("calculadora", "bicicleta") no. Sin este filtro, el tramo de keywords
 * llenaría la sección de ruido en cuanto la categoría no diera cupo.
 */
function palabrasClaveDeTitulo(titulo) {
  return [...new Set(String(titulo || '').toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(palabra => palabra.length >= LARGO_MINIMO_KEYWORD))].slice(0, MAX_KEYWORDS);
}

/**
 * Productos parecidos al que se está viendo, para "También te puede
 * interesar". La disponibilidad es prioridad, no exclusión: primero se llena
 * el cupo con productos disponibles y solo si faltan espacios se completa con
 * no disponibles (vendido/pausado/agotado, ver `SQL_PRODUCTO_ACTIVO`),
 * siempre después de TODOS los disponibles, nunca intercalados. Dentro de
 * cada uno de esos dos grupos, dos tramos de relevancia por orden de
 * prioridad, en UNA sola consulta:
 *
 *   0. misma categoría;
 *   1. si falta cupo, coincidencia de palabras del título.
 *
 * Excluye siempre el producto actual y todo lo del mismo vendedor: eso va en
 * `getSellerOtherProducts`, y repetirlo en los dos carruseles se ve como un
 * bug. Dentro de cada tramo ordena por score (recencia + popularidad).
 *
 * @param product Producto actual, ya normalizado (id, category, seller, title).
 * @returns Productos vía rowToProduct — el shape que espera attachRelations.
 */
async function getRelatedProducts(product, {
  limit = 10
} = {}) {
  if (!product) return [];
  const keywords = palabrasClaveDeTitulo(product.title);
  // Un OR de LIKEs, uno por palabra. Van como parámetros nombrados (@kw0,
  // @kw1...) y no interpolados, para que un título con comillas o con un %
  // no se convierta en inyección ni en un comodín accidental.
  const condicionKeywords = keywords.length ? keywords.map((_, i) => `LOWER(p.title) LIKE @kw${i} ESCAPE '\\'`).join(' OR ') : '0';
  const paramsKeywords = Object.fromEntries(keywords.map((palabra, i) => [`kw${i}`, `%${escaparLike(palabra)}%`]));
  const rows = await db.prepare(`
    WITH product_stats AS (${SQL_STATS_POPULARIDAD})
    SELECT p.*,
      CASE WHEN ${SQL_PRODUCTO_ACTIVO} THEN 0 ELSE 1 END AS tramoDisponibilidad,
      CASE WHEN p.category = @category THEN 0 ELSE 1 END AS tramo,
      (${SQL_SCORE_RELACIONADOS}) AS score
    FROM products p
    LEFT JOIN product_stats ps ON ps.product_id = p.id
    WHERE p.id != @productId
      AND (@seller IS NULL OR p.seller IS NULL OR p.seller != @seller)
      AND (p.category = @category OR ${condicionKeywords})
    ORDER BY "tramoDisponibilidad" ASC, tramo ASC, score DESC, p.created_at DESC
    LIMIT @limit
  `).all({
    ...paramsScore(),
    ...paramsKeywords,
    productId: product.id,
    seller: product.seller || null,
    category: product.category || null,
    limit
  });
  return rows.map(rowToProduct);
}

/** Escapa los comodines de LIKE para que un título con % o _ no los active. */
function escaparLike(texto) {
  return texto.replace(/[\\%_]/g, c => `\\${c}`);
}

/**
 * Las otras publicaciones activas del mismo vendedor, de la más reciente a la
 * más vieja. Sin score de popularidad a propósito: aquí el usuario ya decidió
 * que le interesa ESTE vendedor, y lo que espera ver es su catálogo al día,
 * no un ranking.
 */
async function getSellerOtherProducts(sellerId, {
  excludeProductId = null,
  limit = 10
} = {}) {
  if (!sellerId) return [];
  const rows = await db.prepare(`
    SELECT p.* FROM products p
    WHERE p.seller = @sellerId
      AND (@excludeProductId IS NULL OR p.id != @excludeProductId)
      AND ${SQL_PRODUCTO_ACTIVO}
    ORDER BY p.created_at DESC, p.id DESC
    LIMIT @limit
  `).all({
    sellerId,
    excludeProductId,
    limit
  });
  return rows.map(rowToProduct);
}
const SEARCH_QUERY_MIN_LEN = 2;
const SEARCH_QUERY_MAX_LEN = 60;

/**
 * Ventana durante la cual una MISMA persona buscando lo MISMO no vuelve a
 * sumar. Quien corrige el filtro y le da enter tres veces seguidas está
 * haciendo una sola búsqueda, no tres.
 */
const SEARCH_QUERY_DEDUPE_SECONDS = 120;

/**
 * Cuánto historial de búsquedas se conserva.
 *
 * El ranking solo mira 7 días, así que todo lo anterior es peso muerto en
 * disco y en la consulta de deduplicación. Se guardan 60 y no 7 para dejar
 * margen a análisis a posteriori ("qué se buscaba el mes pasado") y para que
 * subir la ventana del ranking no exija recolectar datos desde cero.
 */
const SEARCH_QUERY_RETENTION_DAYS = 60;

/** Cada cuánto, como mucho, se hace la limpieza. */
const SEARCH_PURGE_INTERVAL_MS = 24 * 60 * 60 * 1000;
let ultimaPurgaSearchQueries = 0;

/**
 * Borra el historial de búsquedas más viejo que `days`. Devuelve cuántas
 * filas se fueron.
 */
async function purgeOldSearchQueries({
  days = SEARCH_QUERY_RETENTION_DAYS
} = {}) {
  const info = await db.prepare("DELETE FROM search_queries WHERE created_at < datetime('now', '-' || ? || ' days')").run(days);
  ultimaPurgaSearchQueries = Date.now();
  return info.changes;
}

/**
 * Limpieza oportunista: corre como mucho una vez cada
 * SEARCH_PURGE_INTERVAL_MS, colgada del registro de búsquedas.
 *
 * Va aquí y no en un setInterval a propósito: un timer de fondo sobrevive a
 * los tests (hay que acordarse de unref) y corre igual en un proceso que no
 * está recibiendo tráfico. Colgarla de la escritura hace que la tabla se
 * limpie exactamente cuando está creciendo, que es cuando importa.
 */
async function purgeOldSearchQueriesIfDue() {
  if (Date.now() - ultimaPurgaSearchQueries < SEARCH_PURGE_INTERVAL_MS) return 0;
  return await purgeOldSearchQueries();
}

/**
 * Revisión monotónica de `search_queries`: sube con cada búsqueda registrada.
 *
 * Existe para que quien cachee el agregado (routes/search.js) sepa que su
 * copia quedó vieja SIN tener que consultar la tabla. Antes el caché solo
 * moría por TTL, y en la práctica eso significaba que el placeholder no
 * cambiaba hasta reiniciar el proceso.
 */
let searchQueriesRevision = 0;
function getSearchQueriesRevision() {
  return searchQueriesRevision;
}

/** Forma legible del término: es la que termina en el placeholder. */
function normalizeSearchQuery(text) {
  return String(text ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
}

/**
 * Clave canónica con la que se agrupan las búsquedas.
 *
 * Sobre la forma legible quita acentos, quita puntuación y pasa cada palabra
 * a singular. Es lo que hace que "Cálculo", "calculo", "calculo!" y
 * "calculos" sumen al MISMO contador en vez de repartirse cuatro votos
 * sueltos que nunca llegan al top 10.
 *
 * El singular es un simple recorte de la "s" final en palabras de más de 3
 * letras. Es tosco a propósito: no pretende ser correcto lingüísticamente,
 * solo estable — "ingles" e "inglés" caen los dos en "ingle", que como clave
 * interna da igual porque lo que se muestra sale de `query_text`, nunca de
 * aquí.
 */
function searchQueryKey(text) {
  return normalizeSearchQuery(text).normalize('NFD').replace(/[\u0300-\u036f]/g, '') // marcas de acento sueltas que dejó NFD
  .replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim().split(' ').map(palabra => palabra.length > 3 && palabra.endsWith('s') ? palabra.slice(0, -1) : palabra).join(' ');
}

/**
 * Registra una búsqueda ejecutada. Descarta ruido (vacía, muy corta/larga) y
 * los reintentos del mismo dispositivo sobre el mismo término dentro de
 * SEARCH_QUERY_DEDUPE_SECONDS.
 *
 * Devuelve true solo si la fila entró (es decir, si el ranking cambió).
 */
async function recordSearchQuery(text, deviceId = null) {
  const normalized = normalizeSearchQuery(text);
  if (normalized.length < SEARCH_QUERY_MIN_LEN || normalized.length > SEARCH_QUERY_MAX_LEN) {
    return false;
  }
  const key = searchQueryKey(normalized);
  if (!key) return false;
  await purgeOldSearchQueriesIfDue();

  // La deduplicación es por dispositivo: sin deviceId no se puede distinguir
  // "la misma persona insistiendo" de "dos personas buscando lo mismo", y
  // castigar la segunda sería peor que dejar pasar la primera.
  if (deviceId) {
    const reciente = await db.prepare(`
      SELECT 1 FROM search_queries
      WHERE device_id = ? AND query_key = ?
        AND created_at >= datetime('now', '-' || ? || ' seconds')
      LIMIT 1
    `).get(deviceId, key, SEARCH_QUERY_DEDUPE_SECONDS);
    if (reciente) return false;
  }
  await db.prepare('INSERT INTO search_queries (query_text, query_key, device_id) VALUES (?, ?, ?)').run(normalized, key, deviceId || null);
  searchQueriesRevision++;
  return true;
}

/**
 * Los términos más buscados de los últimos `days` días, del más al menos
 * popular.
 *
 * Tres decisiones que valen más que el COUNT(*) que había antes:
 *
 * 1. Se agrupa por `query_key`, no por el texto tal cual, para que las
 *    variantes del mismo término sumen juntas (ver searchQueryKey). Las
 *    filas anteriores a la migración 39 no tienen clave, así que se cae a
 *    `query_text`: cuentan como antes en vez de desaparecer del ranking.
 *
 * 2. Se cuentan DISPOSITIVOS distintos, no filas: un término que buscaron 8
 *    personas una vez es más popular que uno que una sola persona buscó 30
 *    veces. Las filas sin device_id cuentan como una unidad cada una.
 *
 * 3. A igualdad de dispositivos manda lo más reciente (una búsqueda de hoy
 *    pesa 3, la de esta semana 1), para que el placeholder siga a lo que
 *    está pasando ahora y no se quede clavado en el término del lunes.
 *
 * El texto que se muestra es la variante escrita más veces dentro del grupo,
 * así que la comunidad decide también cómo se ve — con acentos si así la
 * escribe la mayoría.
 */
async function getTrendingSearches({
  days,
  limit
}) {
  return await db.prepare(`
    WITH recientes AS (
      SELECT id, query_text, device_id, created_at,
             COALESCE(query_key, query_text) AS clave
      FROM search_queries
      WHERE created_at >= datetime('now', '-' || @days || ' days')
    ),
    ranking AS (
      SELECT clave,
             COUNT(DISTINCT COALESCE(device_id, 'fila:' || id)) AS personas,
             SUM(CASE
                   WHEN created_at >= datetime('now', '-1 day')  THEN 3
                   WHEN created_at >= datetime('now', '-3 days') THEN 2
                   ELSE 1
                 END) AS recencia,
             MAX(created_at) AS ultima
      FROM recientes
      GROUP BY clave
    ),
    etiquetas AS (
      SELECT clave, query_text,
             ROW_NUMBER() OVER (
               PARTITION BY clave
               -- query_text al final para que un empate no dependa del orden
               -- físico de las filas: el placeholder no debe cambiar de
               -- ortografía entre dos lecturas idénticas.
               ORDER BY COUNT(*) DESC, MAX(created_at) DESC, query_text ASC
             ) AS puesto
      FROM recientes
      GROUP BY clave, query_text
    )
    SELECT e.query_text AS queryText, r.personas AS count
    FROM ranking r
    JOIN etiquetas e ON e.clave = r.clave AND e.puesto = 1
    ORDER BY r.personas DESC, r.recencia DESC, r.ultima DESC
    LIMIT @limit
  `).all({
    days,
    limit
  });
}

/**
 * Términos de respaldo cuando todavía nadie ha buscado nada (app recién
 * desplegada, o una semana sin búsquedas).
 *
 * Son los nombres de las categorías que de verdad tienen producto activo,
 * de la más surtida a la menos. Se eligen sobre los títulos de producto a
 * propósito: caben en un placeholder, y `SearchScreen` filtra por nombre de
 * categoría además de por título, así que tocar la sugerencia siempre
 * devuelve resultados en vez de dejar la lista vacía.
 */
/**
 * Fallback de "búsquedas populares" para cuando aún no hay historial de
 * búsquedas reales (arranque en frío).
 *
 * Antes caía a nombres de categorías ("Electrónica", "Ropa"...), pero eso no
 * es una búsqueda: es un rótulo del catálogo, y como placeholder confunde
 * ("¿por qué me sugiere 'Hogar' como si alguien lo hubiera buscado?").
 *
 * En su lugar usa los nombres de los productos con más interacción real
 * (vistas/favoritos/contactos, misma señal que rankea el feed en
 * getFeedRanked) dentro de la ventana de popularidad: eso sí se parece a lo
 * que la gente busca, porque es lo que la gente efectivamente toca. Con cero
 * interacciones todavía (día uno, sin tráfico) cae a los productos más
 * recientes, que siguen siendo términos de producto reales y no categorías.
 */
async function getFallbackSearchTerms({
  limit
}) {
  const w = FEED_WEIGHTS;
  return await db.prepare(`
    WITH product_stats AS (
      SELECT
        product_id,
        SUM(CASE WHEN tipo = 'vista' THEN 1 ELSE 0 END) AS vistas,
        SUM(CASE WHEN tipo = 'favorito' THEN 1 ELSE 0 END) AS favoritos,
        SUM(CASE WHEN tipo = 'contacto' THEN 1 ELSE 0 END) AS contactos
      FROM interacciones_dispositivo
      WHERE created_at >= datetime('now', '-' || @popularityWindowDays || ' days')
      GROUP BY product_id
    )
    SELECT
      p.title AS queryText,
      (
        CAST(@wViews AS DOUBLE PRECISION) * COALESCE(ps.vistas, 0)
        + CAST(@wFavoritos AS DOUBLE PRECISION) * COALESCE(ps.favoritos, 0)
        + CAST(@wContactos AS DOUBLE PRECISION) * COALESCE(ps.contactos, 0)
      ) AS score
    FROM products p
    LEFT JOIN product_stats ps ON ps.product_id = p.id
    WHERE ${SQL_PRODUCTO_ACTIVO}
    ORDER BY score DESC, p.created_at DESC
    LIMIT @limit
  `).all({
    popularityWindowDays: w.POPULARITY_WINDOW_DAYS,
    wViews: w.W_VIEWS,
    wFavoritos: w.W_FAVORITOS,
    wContactos: w.W_CONTACTOS,
    limit
  });
}

// ─── Category Engagement (orden dinámico de íconos de categoría) ─────────
// Pesos y ventana viven en un solo lugar para poder tunearlos sin tocar la
// query. Ventana corta a propósito: una categoría popular hace un mes no
// debe seguir arriba si ya nadie la toca.
const CATEGORY_ENGAGEMENT_WEIGHTS = {
  publish: 10,
  // señal fuerte: alguien generó oferta real
  product_view: 3,
  // señal media: interés en un producto concreto
  icon_tap: 1 // señal débil: curiosidad/navegación
};
const CATEGORY_ENGAGEMENT_WINDOW_DAYS = 14;
const CATEGORY_RANKED_CACHE_TTL_MS = 20 * 60 * 1000;
let categoriesRankedCache = null; // { data, expiresAt }

/**
 * Registra un evento de engagement de categoría (publish/icon_tap/
 * product_view). Best-effort a propósito: se difiere con setImmediate para
 * no sumar latencia a la respuesta que disparó el evento, y cualquier error
 * se traga (nunca debe tumbar la acción principal del usuario).
 */
function trackCategoryEngagement(categoryId, eventType) {
  if (!categoryId || !eventType) return;
  setImmediate(async () => {
    try {
      await db.prepare(`
        INSERT INTO category_engagement_events (category_id, event_type, created_at)
        VALUES (?, ?, datetime('now'))
      `).run(categoryId, eventType);
    } catch (err) {
      console.error('trackCategoryEngagement falló:', err.message);
    }
  });
}

/**
 * Todas las categorías ordenadas por score de engagement (ventana de
 * CATEGORY_ENGAGEMENT_WINDOW_DAYS días) descendente. Las que no tuvieron
 * actividad reciente quedan con score 0 al final, no se excluyen. Cacheado
 * en memoria del proceso: esto no requiere tiempo real exacto.
 */
async function getCategoriesRanked() {
  if (categoriesRankedCache && categoriesRankedCache.expiresAt > Date.now()) {
    return categoriesRankedCache.data;
  }
  const eventTypes = Object.keys(CATEGORY_ENGAGEMENT_WEIGHTS);
  const scoreExpr = eventTypes.map(() => `SUM(CASE WHEN e.event_type = ? THEN ? ELSE 0 END)`).join(' + ');
  const weightParams = eventTypes.flatMap(type => [type, CATEGORY_ENGAGEMENT_WEIGHTS[type]]);
  const rows = await db.prepare(`
    SELECT c.id, c.name, c.emoji, c.icon, c.color,
           (${scoreExpr}) AS score
    FROM categories c
    LEFT JOIN category_engagement_events e
      ON e.category_id = c.id
      AND e.created_at >= datetime('now', ?)
    GROUP BY c.id
    ORDER BY score DESC, c.id ASC
  `).all(...weightParams, `-${CATEGORY_ENGAGEMENT_WINDOW_DAYS} days`);
  categoriesRankedCache = {
    data: rows,
    expiresAt: Date.now() + CATEGORY_RANKED_CACHE_TTL_MS
  };
  return rows;
}

/** Solo para tests: fuerza a que la próxima getCategoriesRanked() recalcule. */
function invalidateCategoriesRankedCache() {
  categoriesRankedCache = null;
}
module.exports = {
  initDatabase,
  closeDatabase,
  getDb,
  getCategories,
  getSellers,
  esParticipanteDeConversacion,
  rowToSeller,
  esCuentaTodosLosBadges,
  esUsuarioTodosLosBadges,
  getCuentasSoporte,
  refrescarCuentasDueno,
  anularMetodosPagoCuentasDueno,
  insertSeller,
  getHighlightPlans,
  getAllProducts,
  getProductById,
  isSellerPubliclyActive,
  getPublicationLimitSince,
  countProductsSince,
  insertProduct,
  updateProduct,
  deleteProduct,
  incrementProductViews,
  getSellerProductViews,
  incrementSellerProfileViews,
  // Carrito (siempre acotado por usuario)
  getCartItems,
  getCartItem,
  upsertCartItem,
  updateCartItem,
  deleteCartItem,
  clearCartItems,
  purgarMetodoDePago,
  getAllListings,
  addListing,
  // Price history
  getHighestPriceInLastDays,
  getLowestPriceInLastDays,
  getLastPriceChange,
  getPriceHistoryList,
  countPriceEditsLastHour,
  insertPriceHistory,
  expireStaleOffers,
  // Product ratings
  upsertProductRating,
  getProductRatingStats,
  getUserProductRating,
  getSellerRatingStats,
  syncSellerRating,
  recomputeAllSellerRatings,
  // Métricas de perfil
  MIN_RESPUESTAS_PARA_MEDIANA,
  getResponseDeltasMinutes,
  syncSellerResponseTime,
  computeRachaPublicaciones,
  countVentasConfirmadas,
  sumarVentasConfirmadas,
  getInsigniasOtorgadas,
  registrarInsigniaOtorgada,
  getEstadisticasCalificaciones,
  getEstadisticasPreguntasVendedor,
  // Product comments
  COMENTARIOS_POR_PAGINA,
  COMENTARIOS_MAX_POR_PAGINA,
  createProductComment,
  getProductComments,
  countProductComments,
  getProductCommentById,
  getProductCommentRow,
  getCommentsReceivedBySeller,
  countCommentsReceivedBySeller,
  segundosDesdeUltimoComentario,
  softDeleteProductComment,
  // Enigma escondido
  getResolucionEnigma,
  contarResolucionesEnigma,
  registrarResolucionEnigma,
  // Preguntas y respuestas
  PREGUNTAS_POR_PAGINA,
  PREGUNTAS_MAX_POR_PAGINA,
  PREGUNTAS_PREVIEW,
  createProductQuestion,
  answerProductQuestion,
  deleteProductQuestion,
  getProductQuestions,
  getProductQuestionsPreview,
  getProductQuestionById,
  getProductQuestionRow,
  countProductQuestions,
  countPendingProductQuestions,
  segundosDesdeUltimaPregunta,
  contarPreguntasRecientes,
  // Category Interests
  addCategoryInterest,
  removeCategoryInterest,
  getCategoryInterests,
  getUsersInterestedInCategory,
  // Notifications
  createNotification,
  getNotifications,
  markNotificationRead,
  markAllNotificationsRead,
  markNotificationsReadForConversation,
  getUnreadNotificationCount,
  recordSellerProfileView,
  // Conversations
  createConversation,
  findConversation,
  createDirectConversation,
  findDirectConversation,
  MENSAJES_PRIMER_CONTACTO,
  getChatRelationship,
  setChatUserSetting,
  getChatSafetySettings,
  areUsersBlocked,
  isChatUserMuted,
  getConversationsForUser,
  deleteConversationForUser,
  setUltimaActividad,
  setMostrarEstadoEnLinea,
  getPresencia,
  getUnreadMessageCount,
  // Wanted Posts
  createWantedPost,
  getWantedPostById,
  listWantedPosts,
  updateWantedPost,
  incrementWantedPostViews,
  resolveWantedPost,
  countWantedPostsSince,
  countActiveWantedPosts,
  createWantedConversation,
  findWantedConversation,
  // Push Tokens
  registerPushToken,
  unregisterPushToken,
  getPushTokensForUser,
  unregisterAllPushTokensForUser,
  // Messages
  createMessage,
  getMessages,
  getRepliedMessage,
  messageBelongsToConversation,
  markConversationMessagesRead,
  deleteMessage,
  // Feed Ranking
  FEED_WEIGHTS,
  registrarInteraccion,
  limpiarInteraccionesAntiguas,
  linkDeviceToUser,
  getFeedRanked,
  // Relacionados (detalle de producto)
  getRelatedProducts,
  getSellerOtherProducts,
  // Search trending
  normalizeSearchQuery,
  searchQueryKey,
  recordSearchQuery,
  getSearchQueriesRevision,
  SEARCH_QUERY_RETENTION_DAYS,
  purgeOldSearchQueries,
  getTrendingSearches,
  getFallbackSearchTerms,
  // Category engagement (orden dinámico de categorías)
  CATEGORY_ENGAGEMENT_WEIGHTS,
  CATEGORY_ENGAGEMENT_WINDOW_DAYS,
  trackCategoryEngagement,
  getCategoriesRanked,
  invalidateCategoriesRankedCache,
  createReport,
  getReportById,
  listReports,
  updateReportStatus,
  anonymizeSellerAccount
};
