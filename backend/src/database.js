const crypto = require('crypto');
const fs = require('fs');
const Database = require('better-sqlite3');
const path = require('path');
const {
  DEFAULT_PUBLICATION_POLICIES,
  PUBLICATION_POLICY_RANGES,
} = require('./publicationPolicy');

// Configurable para que los tests puedan correr contra una base temporal con
// el schema y las migraciones REALES, en vez de recrear a mano un schema
// paralelo que se desincroniza en silencio. En ejecución normal la variable
// no está definida y se usa la base del servidor.
const DB_PATH =
  process.env.MERCADITO_DB_PATH || path.join(__dirname, '..', 'mercadito_um.db');

let db;

function initDatabase() {
  db = new Database(DB_PATH);

  // WAL mode para mejor rendimiento
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  db.exec(`
    CREATE TABLE IF NOT EXISTS categories (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      emoji TEXT,
      icon TEXT,
      color TEXT
    );

    CREATE TABLE IF NOT EXISTS sellers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT,
      phone TEXT,
      avatarInitials TEXT,
      major TEXT,
      isBusiness INTEGER DEFAULT 0,
      logoUrl TEXT,
      rating REAL DEFAULT 0,
      reviews INTEGER DEFAULT 0,
      -- Contador exclusivo de aperturas del perfil público. No comparte la
      -- métrica de vistas de productos ni la de publicaciones solicitadas.
      profile_views INTEGER NOT NULL DEFAULT 0,
      verified INTEGER DEFAULT 0,
      businessDescription TEXT,
      businessCategory TEXT,
      businessHours TEXT,
      -- Insignia verde "Socio Fundador": no la gana ninguna cuenta sola con
      -- datos ni acciones propias, la otorga a mano el admin (ver
      -- scripts/otorgar-socio-fundador.js). Va aparte de 'verified' a
      -- propósito: verificar es un trámite (comprobar un dato real de
      -- contacto) y esto es una distinción, no tienen la misma puerta ni el
      -- mismo significado.
      socio_fundador INTEGER DEFAULT 0,
      -- Fecha de alta, para la insignia de Aniversario y para decidir qué
      -- cuentas son "nuevas" (insignia de Novato). Ver migración 42 para
      -- bases que ya existían antes de esta columna: ahí no hay DEFAULT de
      -- tabla que valga (SQLite no acepta uno no-constante en ADD COLUMN),
      -- así que las tres vías de alta (data.js, authGoogle.js, insertSeller)
      -- mandan datetime('now') explícito en el INSERT.
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS products (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      price TEXT NOT NULL DEFAULT '0',
      category TEXT,
      description TEXT,
      publishedAgo TEXT,
      seller TEXT,
      images TEXT DEFAULT '[]',
      imageIcon TEXT,
      imageColor TEXT,
      previousPrice TEXT,
      discountLabel TEXT,
      isFeatured INTEGER DEFAULT 0,
      isOffer INTEGER DEFAULT 0,
      isFavorite INTEGER DEFAULT 0,
      status TEXT DEFAULT NULL,
      priceNum REAL DEFAULT 0,
      offerExpiresAt TEXT DEFAULT NULL,
      extras TEXT DEFAULT '[]',
      stock_quantity INTEGER,
      stock_reset_daily INTEGER DEFAULT 0,
      stock_initial INTEGER,
      stock_updated_at TEXT,
      availableDays TEXT DEFAULT '[]',
      manual_status TEXT DEFAULT NULL,
      expires_at TEXT DEFAULT NULL
    );

    CREATE TABLE IF NOT EXISTS price_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id TEXT NOT NULL,
      price REAL NOT NULL,
      changed_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_price_history_product ON price_history(product_id, changed_at);

    CREATE TABLE IF NOT EXISTS cart (
      id TEXT PRIMARY KEY,
      productId TEXT NOT NULL,
      quantity INTEGER DEFAULT 1,
      meetingPoint TEXT DEFAULT 'Por definir'
    );

    CREATE TABLE IF NOT EXISTS listings (
      id TEXT PRIMARY KEY,
      productId TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS highlight_plans (
      id TEXT PRIMARY KEY,
      title TEXT,
      price TEXT,
      description TEXT,
      days INTEGER
    );

    CREATE TABLE IF NOT EXISTS category_interests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      category_id TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(user_id, category_id)
    );

    CREATE TABLE IF NOT EXISTS notifications (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      type TEXT NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      data TEXT DEFAULT '{}',
      read INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, created_at);

    CREATE TABLE IF NOT EXISTS conversations (
      id TEXT PRIMARY KEY,
      product_id TEXT NOT NULL,
      buyer_id TEXT NOT NULL,
      seller_id TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_message_at TEXT,
      last_message_preview TEXT DEFAULT ''
    );

    CREATE INDEX IF NOT EXISTS idx_conversations_buyer ON conversations(buyer_id, last_message_at);
    CREATE INDEX IF NOT EXISTS idx_conversations_seller ON conversations(seller_id, last_message_at);

    CREATE TABLE IF NOT EXISTS wanted_posts (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT,
      category_id TEXT NOT NULL,
      type TEXT NOT NULL,
      price_min REAL,
      price_max REAL,
      status TEXT NOT NULL DEFAULT 'abierta',
      resolved_with_user_id TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      resolved_at TEXT,
      expires_at TEXT DEFAULT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_wanted_posts_category ON wanted_posts(category_id, status);
    CREATE INDEX IF NOT EXISTS idx_wanted_posts_user ON wanted_posts(user_id, created_at);

    CREATE TABLE IF NOT EXISTS push_tokens (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      player_id TEXT NOT NULL,
      platform TEXT DEFAULT 'unknown',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(user_id, player_id)
    );

    CREATE INDEX IF NOT EXISTS idx_push_tokens_user ON push_tokens(user_id);

    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      text TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      read INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, created_at);

    CREATE TABLE IF NOT EXISTS product_ratings (
      product_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      stars INTEGER NOT NULL CHECK(stars >= 1 AND stars <= 5),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (product_id, user_id),
      FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_product_ratings_product ON product_ratings(product_id);

    -- Comentarios públicos en una publicación. Escribir exige cuenta
    -- verificada (sellers.verified = 1, sea alumno, personal UM, negocio o
    -- externo; ver routes/comments.js); leer es abierto y no requiere sesión.
    --
    -- El borrado es lógico: la fila se queda y se marca. Un comentario que
    -- retiró su autor y uno que moderó el dueño del producto son casos
    -- distintos, y si alguien reclama por una publicación hay que poder
    -- distinguirlos — de ahí deleted_by además de deleted_at.
    --
    -- Sin FOREIGN KEY hacia sellers a propósito: ninguna tabla de esta base
    -- la tiene (messages.sender_id, notifications.user_id, conversations.*
    -- tampoco), porque varios de esos ids pueden ser de dispositivo anónimo.
    -- No se introduce la excepción solo aquí.
    CREATE TABLE IF NOT EXISTS product_comments (
      id         TEXT PRIMARY KEY,
      product_id TEXT NOT NULL,
      user_id    TEXT NOT NULL,
      texto      TEXT NOT NULL CHECK(length(texto) >= 1 AND length(texto) <= 500),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      deleted_at TEXT DEFAULT NULL,
      deleted_by TEXT DEFAULT NULL,
      FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
    );

    -- Hilo de un producto. Las cuatro columnas en este orden convierten la
    -- paginación por keyset (WHERE product_id=? AND deleted_at IS NULL AND
    -- (created_at, id) < (?, ?) ORDER BY created_at DESC, id DESC) en un
    -- range scan puro, sin paso de ordenamiento.
    CREATE INDEX IF NOT EXISTS idx_product_comments_product
      ON product_comments(product_id, deleted_at, created_at DESC, id DESC);

    -- Rate limit por usuario: "¿hace cuánto comentó?" no puede usar el
    -- índice de arriba, que arranca por product_id.
    CREATE INDEX IF NOT EXISTS idx_product_comments_user
      ON product_comments(user_id, created_at DESC);

    -- Preguntas públicas sobre una publicación, estilo marketplace: pregunta
    -- cualquiera CON SESIÓN (no hace falta estar verificado, a diferencia de
    -- los comentarios) y responde ÚNICAMENTE el dueño del producto.
    --
    -- seller_id va denormalizado del producto: el listado y el futuro panel
    -- de "pendientes por responder" filtran por vendedor, y sin esta columna
    -- cada consulta necesitaría un JOIN con products solo para eso. Se copia
    -- al insertar y no se vuelve a tocar; si un producto cambiara de dueño
    -- (hoy no pasa), las preguntas viejas seguirían apuntando a quien las
    -- recibió, que es lo correcto para un hilo público ya publicado.
    --
    -- status es derivable de answer_text IS NULL, y se guarda igual porque
    -- el índice de pendientes del vendedor lo necesita como columna real.
    -- Para que no se desincronice, se escribe SIEMPRE en el mismo UPDATE
    -- que la respuesta (ver answerProductQuestion) y nunca solo.
    --
    -- Sin FOREIGN KEY hacia sellers, por lo mismo que product_comments.
    CREATE TABLE IF NOT EXISTS product_questions (
      id            TEXT PRIMARY KEY,
      product_id    TEXT NOT NULL,
      seller_id     TEXT NOT NULL,
      asked_by      TEXT NOT NULL,
      question_text TEXT NOT NULL CHECK(length(question_text) >= 1 AND length(question_text) <= 500),
      answer_text   TEXT DEFAULT NULL CHECK(answer_text IS NULL OR (length(answer_text) >= 1 AND length(answer_text) <= 500)),
      status        TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'answered')),
      created_at    TEXT NOT NULL DEFAULT (datetime('now')),
      answered_at   TEXT DEFAULT NULL,
      FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
    );

    -- Listado del detalle y de "ver todas": mismo keyset que el hilo de
    -- comentarios (created_at, id) DESC, resuelto como range scan puro.
    CREATE INDEX IF NOT EXISTS idx_product_questions_product
      ON product_questions(product_id, created_at DESC, id DESC);

    -- "¿Qué me falta por responder?" — el chip de pendientes del dueño y el
    -- panel que vendrá después. Arranca por seller_id, así que no puede
    -- servirse del índice de arriba.
    CREATE INDEX IF NOT EXISTS idx_product_questions_seller
      ON product_questions(seller_id, status, created_at DESC);

    -- Rate limit: "¿cuántas preguntas lleva ESTE usuario en ESTE producto?".
    CREATE INDEX IF NOT EXISTS idx_product_questions_asked_by
      ON product_questions(asked_by, product_id, created_at DESC);

    -- Interacciones de feed: registra vistas/favoritos/contactos por device_id
    -- (siempre presente) y opcionalmente por user_id (si hay sesión). Es la
    -- única fuente tanto para la popularidad de un producto (Fase 1) como
    -- para la afinidad por categoría de cada dispositivo/usuario (Fase 2).
    CREATE TABLE IF NOT EXISTS interacciones_dispositivo (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      device_id TEXT NOT NULL,
      user_id TEXT,
      -- product_id es NULL para tipo='categoria': entrar a navegar una
      -- categoría es una interacción con la categoría, no con un producto.
      product_id TEXT,
      category TEXT NOT NULL,
      tipo TEXT NOT NULL CHECK(tipo IN ('vista', 'favorito', 'contacto', 'categoria')),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_interacciones_device ON interacciones_dispositivo(device_id, created_at);
    CREATE INDEX IF NOT EXISTS idx_interacciones_user ON interacciones_dispositivo(user_id, created_at);
    CREATE INDEX IF NOT EXISTS idx_interacciones_producto_tipo ON interacciones_dispositivo(product_id, tipo);
    CREATE INDEX IF NOT EXISTS idx_interacciones_device_categoria ON interacciones_dispositivo(device_id, category, created_at);
    CREATE INDEX IF NOT EXISTS idx_interacciones_user_categoria ON interacciones_dispositivo(user_id, category, created_at);

    CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
    CREATE INDEX IF NOT EXISTS idx_products_seller ON products(seller);

    -- Búsquedas ejecutadas por los usuarios (al presionar buscar/enter, no
    -- por tecla). Agregado estadístico para alimentar "trending searches".
    --
    -- query_text es la forma legible (lo que se muestra en el placeholder);
    -- query_key es la clave canónica con la que se agrupa (ver
    -- searchQueryKey): sin acentos, sin puntuación y en singular, para que
    -- "Cálculo", "calculo" y "calculos" cuenten como el MISMO término.
    -- device_id es el id anónimo del dispositivo y existe solo para contar
    -- personas distintas en vez de tecleos: sin él, alguien buscando 50 veces
    -- lo mismo se apodera del placeholder de toda la comunidad.
    CREATE TABLE IF NOT EXISTS search_queries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      query_text TEXT NOT NULL,
      query_key TEXT,
      device_id TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_search_queries_created ON search_queries(created_at);
    CREATE INDEX IF NOT EXISTS idx_search_queries_text ON search_queries(query_text, created_at);
    -- El índice por query_key NO va aquí: este bloque corre antes de las
    -- migraciones, y en una base que viene de la versión anterior la columna
    -- todavía no existe (CREATE TABLE IF NOT EXISTS no la agrega). Lo crea la
    -- migración 39, justo después de añadir la columna.

    -- Eventos de engagement por categoría (publicar/tocar ícono/ver
    -- producto), usados para ordenar dinámicamente los íconos de categoría
    -- en home y búsqueda por actividad reciente. Sin device_id/user_id a
    -- propósito: es agregado puro para ranking de categorías, no
    -- personalización.
    CREATE TABLE IF NOT EXISTS category_engagement_events (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      category_id TEXT NOT NULL,
      event_type  TEXT NOT NULL CHECK(event_type IN ('publish', 'icon_tap', 'product_view')),
      created_at  TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_category_engagement_category_created
      ON category_engagement_events(category_id, created_at);

    -- ─── Retargeting conductual por categoría ───────────────────────
    --
    -- El "sujeto" de todo este subsistema es un subject_id, que es el
    -- user_id si hay sesión y el id anónimo (anon_...) si no. No son dos
    -- espacios de nombres distintos: AnonymousId.resolve() en la app
    -- devuelve el mismo valor que se manda como deviceId a
    -- /api/interacciones y como userId a /register-push-anon, así que
    -- sendPush([subjectId]) encuentra los tokens de ambos casos igual.

    -- Snapshot del interés por categoría. NO es la fuente de verdad: lo
    -- reescribe entero refrescarInteres() a partir de
    -- interacciones_dispositivo en cada pasada del job. Existe para poder
    -- consultar y depurar el score sin recalcularlo, y para que cambiar los
    -- pesos no deje scores viejos cocinados en la tabla.
    CREATE TABLE IF NOT EXISTS user_category_interest (
      subject_id          TEXT NOT NULL,
      category_id         TEXT NOT NULL,
      interest_score      REAL NOT NULL,
      last_interaction_at TEXT NOT NULL,
      decay_status        TEXT NOT NULL CHECK(decay_status IN ('fresh', 'decaying')),
      updated_at          TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (subject_id, category_id)
    );

    CREATE INDEX IF NOT EXISTS idx_user_category_interest_categoria
      ON user_category_interest(category_id, interest_score);

    -- Registro de cada push de retargeting enviado. Es la ÚNICA fuente para
    -- el frequency capping, la reducción adaptativa y las métricas: no hay
    -- tabla de contadores ni de backoff que se pueda desincronizar de esto.
    -- product_ids es el JSON de los productos que iban en el push, para
    -- poder deduplicar y para saber qué se anunció.
    CREATE TABLE IF NOT EXISTS notification_log (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      subject_id      TEXT NOT NULL,
      type            TEXT NOT NULL,
      category_id     TEXT,
      product_ids     TEXT NOT NULL DEFAULT '[]',
      notification_id TEXT,
      sent_at         TEXT NOT NULL DEFAULT (datetime('now')),
      opened_at       TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_notification_log_subject_tipo
      ON notification_log(subject_id, type, sent_at);
    CREATE INDEX IF NOT EXISTS idx_notification_log_subject_categoria
      ON notification_log(subject_id, category_id, sent_at);

    -- Preferencias de notificación por sujeto. Semántica OPT-OUT: la
    -- ausencia de fila significa habilitado, así que un usuario nuevo recibe
    -- notificaciones sin necesidad de sembrarle filas al registrarse.
    CREATE TABLE IF NOT EXISTS user_notification_preferences (
      subject_id        TEXT NOT NULL,
      notification_type TEXT NOT NULL,
      enabled           INTEGER NOT NULL DEFAULT 1,
      updated_at        TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (subject_id, notification_type)
    );

    -- Cola de productos publicados pendientes de evaluar para retargeting.
    -- products.created_at existe y bastaría para preguntar "qué es nuevo",
    -- pero entonces el job dependería de una marca de agua de su última
    -- pasada: si el proceso se reinicia entre corridas, o dos corridas se
    -- solapan, se pierden o se repiten productos. La cola da semántica de
    -- procesado-una-vez sin estado en memoria, y el resto de los datos
    -- (título, categoría, vendedor) se lee de products al procesarla para
    -- no duplicarlos aquí y que no queden obsoletos si el producto se edita.
    CREATE TABLE IF NOT EXISTS interest_notification_queue (
      product_id   TEXT PRIMARY KEY,
      created_at   TEXT NOT NULL DEFAULT (datetime('now')),
      processed_at TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_interest_queue_pendientes
      ON interest_notification_queue(processed_at, created_at);

    -- Quién resolvió el enigma escondido (secreto/enigma.js) y en qué orden.
    --
    -- La gracia del juego es llegar primero, así que la posición se congela
    -- al resolver: se calcula una vez al insertar y no se vuelve a tocar.
    -- Derivarla al vuelo (contar filas anteriores por fecha) daría el mismo
    -- número hoy, pero cambiaría si alguna vez se borra una fila, y el "eres
    -- el #3" que alguien ya vio no debe convertirse en otro número después.
    --
    -- user_id como PRIMARY KEY: resolverlo dos veces es la misma hazaña una
    -- vez, y así el INSERT OR IGNORE de registrarResolucionEnigma es la
    -- protección contra el doble tap, sin transacción de por medio.
    CREATE TABLE IF NOT EXISTS secret_solves (
      user_id   TEXT PRIMARY KEY,
      posicion  INTEGER NOT NULL,
      solved_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);

  // ─── Migración desde schema legacy ─────────────────────────
  runMigrations();

  // Sembrar datos de referencia estructurales si están vacíos
  const catCount = db.prepare('SELECT COUNT(*) as c FROM categories').get();
  if (catCount.c === 0) {
    const insertCategory = db.prepare(
      'INSERT OR IGNORE INTO categories (id, name, emoji, icon, color) VALUES (?, ?, ?, ?, ?)'
    );
    const categories = [
      ['books', 'Libros', '\u{1F4DA}', 'menu_book', '#2A6FBB'],
      ['notes', 'Apuntes', '\u{1F4DD}', 'article', '#D97706'],
      ['electronics', 'Electrónicos', '\u{1F4BB}', 'devices', '#1B998B'],
      ['clothes', 'Ropa', '\u{1F454}', 'checkroom', '#9B5DE5'],
      ['services', 'Servicios', '\u{1F6E0}\uFE0F', 'construction', '#E76F51'],
      ['food', 'Comida', '\u{1F355}', 'restaurant', '#E86F2C'],
      ['housing', 'Hospedaje', '\u{1F6CF}\uFE0F', 'bed', '#6A994E'],
      ['other', 'Otros', '\u{1F4E6}', 'category', '#607D8B'],
    ];
    for (const cat of categories) insertCategory.run(...cat);
  }

  const planCount = db.prepare('SELECT COUNT(*) as c FROM highlight_plans').get();
  if (planCount.c === 0) {
    const insertPlan = db.prepare(
      'INSERT OR IGNORE INTO highlight_plans (id, title, price, description, days) VALUES (?, ?, ?, ?, ?)'
    );
    const plans = [
      ['d1', 'Destacado 24h', '$20', 'Para ventas rapidas y urgentes. Aparece arriba por un dia.', 1],
      ['d3', 'Destacado 3 dias', '$40', 'Buena opcion para rotar inventario sin pagar de mas.', 3],
      ['d7', 'Destacado 7 dias', '$70', 'Mayor visibilidad durante toda la semana escolar.', 7],
      ['m1', 'Plan mensual', '$180', 'Pensado para negocios fijos: aparece arriba en su categoria todo el mes.', 30],
    ];
    for (const p of plans) insertPlan.run(...p);
  }

  // Historial de búsquedas viejo: se tira en cada arranque. Además de
  // ahorrar disco, acota la tabla que consulta la deduplicación de
  // recordSearchQuery en cada búsqueda registrada.
  const purgadas = purgeOldSearchQueries();
  if (purgadas > 0) {
    console.log(`🧹 ${purgadas} búsquedas antiguas purgadas del historial`);
  }

  // El caché de calificaciones por vendedor se reconstruye en cada arranque.
  // Es barato (un UPDATE con subconsultas) y garantiza que la columna nunca
  // quede divergiendo de product_ratings, que es la fuente de verdad.
  recomputeAllSellerRatings();

  console.log('🗄️  Base de datos SQLite inicializada');
  return db;
}

// ─── Migración de schema ─────────────────────────────────────

function runMigrations() {
  // 1. Verificar si la columna priceNum ya existe (si no, agregarla)
  const cols = db.prepare("PRAGMA table_info('products')").all();
  const hasPriceNum = cols.some(c => c.name === 'priceNum');
  if (!hasPriceNum) {
    db.exec(`ALTER TABLE products ADD COLUMN priceNum REAL DEFAULT 0`);
  }

  // 2. Migrar datos: poblar priceNum desde price (TEXT → REAL)
  const unmigrated = db.prepare(
    "SELECT id, price FROM products WHERE priceNum IS NULL OR priceNum = 0"
  ).all();
  for (const row of unmigrated) {
    if (row.price) {
      const num = parseFloat(String(row.price).replace(/[^0-9.]/g, ''));
      if (!isNaN(num) && num > 0) {
        db.prepare("UPDATE products SET priceNum = ? WHERE id = ?").run(num, row.id);
      }
    }
  }

  // 3. Verificar si offerExpiresAt existe
  const hasOfferExpiresAt = cols.some(c => c.name === 'offerExpiresAt');
  if (!hasOfferExpiresAt) {
    db.exec(`ALTER TABLE products ADD COLUMN offerExpiresAt TEXT DEFAULT NULL`);
  }

  // 4. Migración para price_history: asegurar columna price
  const phCols = db.prepare("PRAGMA table_info('price_history')").all();
  const hasPriceCol = phCols.some(c => c.name === 'price');
  if (!hasPriceCol) {
    db.exec(`ALTER TABLE price_history ADD COLUMN price REAL`);
    const hasOldPrice = phCols.some(c => c.name === 'old_price');
    if (hasOldPrice) {
      db.exec(`UPDATE price_history SET price = old_price WHERE price IS NULL OR price = 0`);
    }
  }

  // 5. Migrar sellers: agregar isBusiness y logoUrl si no existen
  const sellerCols = db.prepare("PRAGMA table_info('sellers')").all();
  const hasIsBusiness = sellerCols.some(c => c.name === 'isBusiness');
  if (!hasIsBusiness) {
    db.exec(`ALTER TABLE sellers ADD COLUMN isBusiness INTEGER DEFAULT 0`);
  }
  const hasLogoUrl = sellerCols.some(c => c.name === 'logoUrl');
  if (!hasLogoUrl) {
    db.exec(`ALTER TABLE sellers ADD COLUMN logoUrl TEXT`);
  }
  // Poblar isBusiness basado en major existente
  db.prepare(
    "UPDATE sellers SET isBusiness = 1 WHERE major = 'Negocio • Establecimiento' AND (isBusiness IS NULL OR isBusiness = 0)"
  ).run();

  // 6. Migrar productos: agregar extras si no existe
  const hasExtras = cols.some(c => c.name === 'extras');
  if (!hasExtras) {
    db.exec(`ALTER TABLE products ADD COLUMN extras TEXT DEFAULT '[]'`);
  }

  // 7. Migrar productos: agregar columnas de stock si no existen
  const hasStockQuantity = cols.some(c => c.name === 'stock_quantity');
  if (!hasStockQuantity) {
    db.exec(`
      ALTER TABLE products ADD COLUMN stock_quantity INTEGER;
      ALTER TABLE products ADD COLUMN stock_reset_daily INTEGER DEFAULT 0;
      ALTER TABLE products ADD COLUMN stock_initial INTEGER;
      ALTER TABLE products ADD COLUMN stock_updated_at TEXT;
    `);
  }

  // 8. Migrar productos: agregar created_at para poder calcular recencia real
  //    en el feed ranking. Los productos existentes no tienen fecha original
  //    confiable, así que se backfillean a 'now' (entran al feed como si
  //    fueran nuevos en vez de quedar penalizados por antigüedad falsa).
  const hasCreatedAt = cols.some(c => c.name === 'created_at');
  if (!hasCreatedAt) {
    db.exec(`ALTER TABLE products ADD COLUMN created_at TEXT`);
    db.prepare(
      "UPDATE products SET created_at = datetime('now') WHERE created_at IS NULL"
    ).run();
  }

  // 9. Migrar sellers: agregar avg_response_minutes (calidad del vendedor)
  const sellerColsResp = db.prepare("PRAGMA table_info('sellers')").all();
  const hasAvgResponse = sellerColsResp.some(c => c.name === 'avg_response_minutes');
  if (!hasAvgResponse) {
    db.exec(`ALTER TABLE sellers ADD COLUMN avg_response_minutes INTEGER`);
  }

  // 10. Migrar conversations: permitir wanted_post_id y relajar product_id a NULL
  //    (SQLite no permite quitar NOT NULL con ALTER TABLE, así que se recrea la
  //    tabla preservando los datos existentes). También se recrea messages para
  //    arreglar la FK que SQLite reescribe al renombrar conversations.
  const convCols = db.prepare("PRAGMA table_info('conversations')").all();
  const hasWantedPostId = convCols.some(c => c.name === 'wanted_post_id');
  if (!hasWantedPostId) {
    // foreign_keys es una pragma global de la conexión y no puede alternarse
    // dentro de una transacción, así que se conmuta fuera de db.transaction().
    // El bloque DDL/DML en sí se envuelve en una transacción para que, si el
    // proceso se cae a medio camino (p. ej. justo después de renombrar
    // conversations a conversations_legacy), todo el rename/create/copy/drop
    // se revierta atómicamente en vez de dejar el esquema a medio migrar.
    db.pragma('foreign_keys = OFF');
    try {
      const migrateConversations = db.transaction(() => {
        db.exec(`
          ALTER TABLE messages RENAME TO messages_legacy;
          ALTER TABLE conversations RENAME TO conversations_legacy;

          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            product_id TEXT,
            wanted_post_id TEXT,
            buyer_id TEXT NOT NULL,
            seller_id TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            last_message_at TEXT,
            last_message_preview TEXT DEFAULT ''
          );

          INSERT INTO conversations (id, product_id, wanted_post_id, buyer_id, seller_id, created_at, last_message_at, last_message_preview)
            SELECT id, product_id, NULL, buyer_id, seller_id, created_at, last_message_at, last_message_preview
            FROM conversations_legacy;

          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            sender_id TEXT NOT NULL,
            text TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            read INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
          );

          INSERT INTO messages (id, conversation_id, sender_id, text, created_at, read)
            SELECT id, conversation_id, sender_id, text, created_at, read
            FROM messages_legacy;

          DROP TABLE messages_legacy;
          DROP TABLE conversations_legacy;

          CREATE INDEX IF NOT EXISTS idx_conversations_buyer ON conversations(buyer_id, last_message_at);
          CREATE INDEX IF NOT EXISTS idx_conversations_seller ON conversations(seller_id, last_message_at);
          CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, created_at);
        `);
      });
      migrateConversations();
    } finally {
      db.pragma('foreign_keys = ON');
    }
  }

  // 11. Migrar productos: agregar availableDays si no existe
  const hasAvailableDays = cols.some(c => c.name === 'availableDays');
  if (!hasAvailableDays) {
    db.exec(`ALTER TABLE products ADD COLUMN availableDays TEXT DEFAULT '[]'`);
  }

  // 12. Migrar productos: agregar updated_at (marca de "editado" que no
  //     afecta la recencia del score, esa sigue usando solo created_at).
  const hasUpdatedAt = cols.some(c => c.name === 'updated_at');
  if (!hasUpdatedAt) {
    db.exec(`ALTER TABLE products ADD COLUMN updated_at TEXT`);
  }

  // 13. Migrar wanted_posts: agregar updated_at con el mismo propósito
  const wantedCols = db.prepare("PRAGMA table_info('wanted_posts')").all();
  const hasWantedUpdatedAt = wantedCols.some(c => c.name === 'updated_at');
  if (!hasWantedUpdatedAt) {
    db.exec(`ALTER TABLE wanted_posts ADD COLUMN updated_at TEXT`);
  }

  // 14. Migrar sellers: agregar businessDescription y businessCategory
  //     (perfil público de negocio: rubro + descripción corta)
  const sellerColsBiz = db.prepare("PRAGMA table_info('sellers')").all();
  const hasBusinessDescription = sellerColsBiz.some(c => c.name === 'businessDescription');
  if (!hasBusinessDescription) {
    db.exec(`
      ALTER TABLE sellers ADD COLUMN businessDescription TEXT;
      ALTER TABLE sellers ADD COLUMN businessCategory TEXT;
    `);
  }

  // 15. Sellers: índice único de email (case-insensitive) para evitar que dos
  //     cuentas distintas terminen compartiendo el mismo correo. Parcial:
  //     ignora filas con email NULL/'' (cuentas legacy sin correo capturado).
  db.exec(`
    CREATE UNIQUE INDEX IF NOT EXISTS idx_sellers_email_unique
    ON sellers(email COLLATE NOCASE)
    WHERE email IS NOT NULL AND email != ''
  `);

  // 16. Sellers: agregar password_hash. Antes de esto, el password vivía
  // SOLO en el SQLite local del dispositivo (sqflite) y nunca se mandaba al
  // backend, así que el login real dependía de quedarte en el mismo
  // dispositivo/instalación donde te registraste. Con esta columna el
  // backend pasa a ser la autoridad real de credenciales (ver
  // POST /api/auth/register y POST /api/auth/login). Cuentas creadas antes
  // de esta migración quedan con password_hash NULL hasta que su dueño
  // vuelva a "registrarse" con ese email (el endpoint lo backfillea).
  const hasPasswordHash = sellerColsBiz.some(c => c.name === 'password_hash');
  if (!hasPasswordHash) {
    db.exec(`ALTER TABLE sellers ADD COLUMN password_hash TEXT`);
  }

  // 17. Sellers: contador de intentos fallidos de login + bloqueo temporal.
  //     Tras LOGIN_MAX_ATTEMPTS (ver index.js) intentos fallidos seguidos,
  //     la cuenta queda bloqueada hasta locked_until para frenar fuerza bruta.
  //     Un login exitoso resetea el contador.
  const hasFailedAttempts = sellerColsBiz.some(c => c.name === 'failed_login_attempts');
  if (!hasFailedAttempts) {
    db.exec(`
      ALTER TABLE sellers ADD COLUMN failed_login_attempts INTEGER DEFAULT 0;
      ALTER TABLE sellers ADD COLUMN locked_until TEXT;
    `);
  }

  // 18. Mensajes: agregar image_url para soportar mensajes con imagen
  //     (además o en vez de texto) en el chat.
  const msgCols = db.prepare("PRAGMA table_info('messages')").all();
  const hasImageUrl = msgCols.some(c => c.name === 'image_url');
  if (!hasImageUrl) {
    db.exec(`ALTER TABLE messages ADD COLUMN image_url TEXT DEFAULT NULL`);
  }

  // 19. Migrar sellers: agregar businessHours (horario de operación por día).
  //     JSON string keyed por día ('0'=Lunes .. '6'=Domingo), cada valor
  //     { open: 'HH:mm', close: 'HH:mm' }. Un día ausente = cerrado ese día.
  const sellerColsHours = db.prepare("PRAGMA table_info('sellers')").all();
  const hasBusinessHours = sellerColsHours.some(c => c.name === 'businessHours');
  if (!hasBusinessHours) {
    db.exec(`ALTER TABLE sellers ADD COLUMN businessHours TEXT`);
  }

  // 20. Ubicación geográfica opcional (lat/lng), nullable en las tres tablas:
  //     sellers (ubicación guardada de perfil de negocio), products y
  //     wanted_posts (ubicación puntual de una publicación, hoy solo usada
  //     por cuentas de negocio, pero disponible para todos a futuro).
  const sellerColsLoc = db.prepare("PRAGMA table_info('sellers')").all();
  if (!sellerColsLoc.some(c => c.name === 'location_lat')) {
    db.exec(`
      ALTER TABLE sellers ADD COLUMN location_lat REAL;
      ALTER TABLE sellers ADD COLUMN location_lng REAL;
    `);
  }
  if (!cols.some(c => c.name === 'location_lat')) {
    db.exec(`
      ALTER TABLE products ADD COLUMN location_lat REAL;
      ALTER TABLE products ADD COLUMN location_lng REAL;
    `);
  }
  if (!wantedCols.some(c => c.name === 'location_lat')) {
    db.exec(`
      ALTER TABLE wanted_posts ADD COLUMN location_lat REAL;
      ALTER TABLE wanted_posts ADD COLUMN location_lng REAL;
    `);
  }

  // 21. Métodos de pago aceptados. En sellers es el catálogo del perfil
  //     (obligatorio elegir al menos 1 al registrarse); en products/wanted_posts
  //     es un override opcional por publicación — NULL significa "hereda los
  //     del perfil del vendedor", no "sin métodos de pago".
  if (!sellerColsLoc.some(c => c.name === 'paymentMethods')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN paymentMethods TEXT`);
  }
  if (!cols.some(c => c.name === 'paymentMethods')) {
    db.exec(`ALTER TABLE products ADD COLUMN paymentMethods TEXT DEFAULT NULL`);
  }
  if (!wantedCols.some(c => c.name === 'paymentMethods')) {
    db.exec(`ALTER TABLE wanted_posts ADD COLUMN paymentMethods TEXT DEFAULT NULL`);
  }

  // 22. Separar el override manual del vendedor (vendido/apartado/en
  //     negociación/pausado) del badge de disponibilidad, que ahora se
  //     calcula en tiempo real (ver computeProductStatus en products.js) a
  //     partir de manual_status + stock + availableDays + horario del
  //     negocio. `status` queda como columna legacy sin escribirse más;
  //     'available'/'unavailable' dejan de ser valores manuales válidos.
  if (!cols.some(c => c.name === 'manual_status')) {
    db.exec(`ALTER TABLE products ADD COLUMN manual_status TEXT DEFAULT NULL`);
    db.prepare(`
      UPDATE products SET manual_status = status
      WHERE status IN ('sold', 'reserved', 'negotiating', 'paused')
    `).run();
  }

  // 23. Contador simple de vistas (no vistas únicas por usuario): se
  //     incrementa en POST /:id/view salvo que el solicitante sea el dueño.
  if (!cols.some(c => c.name === 'views')) {
    db.exec(`ALTER TABLE products ADD COLUMN views INTEGER DEFAULT 0`);
  }
  if (!wantedCols.some(c => c.name === 'views')) {
    db.exec(`ALTER TABLE wanted_posts ADD COLUMN views INTEGER DEFAULT 0`);
  }
  if (!cols.some(c => c.name === 'expires_at')) {
    db.exec(`ALTER TABLE products ADD COLUMN expires_at TEXT DEFAULT NULL`);
  }
  if (!wantedCols.some(c => c.name === 'expires_at')) {
    db.exec(`ALTER TABLE wanted_posts ADD COLUMN expires_at TEXT DEFAULT NULL`);
  }
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_products_seller_expiry
      ON products(seller, expires_at, created_at);
    CREATE INDEX IF NOT EXISTS idx_wanted_user_expiry
      ON wanted_posts(user_id, status, expires_at, created_at);
  `);

  // 23b. Vistas del perfil público. Las bases existentes necesitan esta
  // migración porque el DEFAULT de CREATE TABLE solo aplica a instalaciones
  // nuevas.
  const sellerColsProfileViews = db.prepare("PRAGMA table_info('sellers')").all();
  if (!sellerColsProfileViews.some(c => c.name === 'profile_views')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN profile_views INTEGER NOT NULL DEFAULT 0`);
  }

  // Documentos de solicitudes manuales de negocio.
  db.exec(`
    CREATE TABLE IF NOT EXISTS verification_documents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      doc_type TEXT NOT NULL CHECK(doc_type IN ('responsible_ine_front','responsible_ine_back','additional_evidence')),
      file_url TEXT NOT NULL,
      original_name TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      uploaded_at TEXT NOT NULL,
      content_hash TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_verification_documents_user ON verification_documents(usuario_id, doc_type, uploaded_at);
  `);

  // 24. Sistema de verificación de cuentas (100% automático, sin revisión
  //     humana). `sellers.verified` — que ya existía y que lee toda la app —
  //     sigue siendo la bandera rápida; la tabla `verificaciones` guarda el
  //     detalle del flujo (OTPs, datos capturados, rate limiting).
  const sellerColsVerif = db.prepare("PRAGMA table_info('sellers')").all();
  if (!sellerColsVerif.some(c => c.name === 'tipo_cuenta')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN tipo_cuenta TEXT`);
    // Backfill desde los datos que ya distinguen el tipo de cuenta hoy:
    // isBusiness (columna real) y major (etiqueta asignada en el registro).
    db.exec(`
      UPDATE sellers SET tipo_cuenta = CASE
        WHEN isBusiness = 1 THEN 'negocio'
        WHEN major = 'Estudiante' THEN 'estudiante'
        ELSE 'particular'
      END
      WHERE tipo_cuenta IS NULL
    `);
  }

  // El tipo 'particular' es lo que la UI llama "externo": se conserva el
  // nombre interno para no migrar el enum de Flutter, el CHECK del SQLite
  // local ni las filas ya guardadas.
  db.exec(`
    CREATE TABLE IF NOT EXISTS verificaciones (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id TEXT NOT NULL UNIQUE REFERENCES sellers(id) ON DELETE CASCADE,
      tipo_cuenta TEXT NOT NULL CHECK(tipo_cuenta IN ('estudiante','negocio','particular')),
      estado TEXT NOT NULL DEFAULT 'pendiente' CHECK(estado IN ('pendiente','verificado','rechazado')),
      fecha_verificacion TEXT,
      creado_en TEXT NOT NULL,

      correo_institucional TEXT,
      matricula TEXT,
      codigo_otp_email TEXT,
      codigo_otp_email_expira TEXT,

      nombre_negocio TEXT,
      responsable_negocio TEXT,
      ubicacion_lat REAL,
      ubicacion_lng REAL,
      link_red_social TEXT,
      solicitud_json TEXT,

      telefono TEXT,
      codigo_otp_sms TEXT,
      codigo_otp_sms_expira TEXT,

      motivo_rechazo TEXT,
      campo_rechazado TEXT,
      intentos_envio INTEGER NOT NULL DEFAULT 0,
      ventana_envio_inicio TEXT,
      intentos_confirmacion INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_verificaciones_correo
      ON verificaciones(correo_institucional);
    CREATE INDEX IF NOT EXISTS idx_verificaciones_telefono
      ON verificaciones(telefono);
  `);

  // 25. Carrera del estudiante (lista fija de la Universidad de Montemorelos,
  //     ver validation/carreras.js). Se captura en `verificaciones.carrera`
  //     al solicitar el código y se copia a `sellers.carrera` al confirmar
  //     (mismo patrón que `sellers.verified`: bandera rápida para mostrar en
  //     el perfil sin tener que hacer join contra `verificaciones`).
  const verifColsCarrera = db.prepare("PRAGMA table_info('verificaciones')").all();
  if (!verifColsCarrera.some(c => c.name === 'carrera')) {
    db.exec(`ALTER TABLE verificaciones ADD COLUMN carrera TEXT`);
  }
  const sellerColsCarrera = db.prepare("PRAGMA table_info('sellers')").all();
  if (!sellerColsCarrera.some(c => c.name === 'carrera')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN carrera TEXT`);
  }

  // 26. `tipo_verificacion` ('estudiante' | 'empleado'): el mismo flujo de OTP
  //     por correo sirve a alumnos y a personal de la universidad, y el tipo
  //     lo declara el cliente al solicitar el código.
  //
  //     Va en una columna NUEVA y no en `verificaciones.tipo_cuenta`: esa
  //     tiene CHECK(tipo_cuenta IN ('estudiante','negocio','particular')), y
  //     guardar 'empleado' ahí reventaría el INSERT — ampliar un CHECK en
  //     SQLite obliga a reconstruir la tabla entera. Ambos siguen siendo
  //     tipo_cuenta='estudiante'; lo que los distingue es esta columna.
  if (!verifColsCarrera.some(c => c.name === 'tipo_verificacion')) {
    db.exec(`ALTER TABLE verificaciones ADD COLUMN tipo_verificacion TEXT`);
    // Las filas que ya existen son todas de alumno: este flujo es lo único
    // que había antes de que el personal pudiera verificarse.
    db.exec(`
      UPDATE verificaciones SET tipo_verificacion = 'estudiante'
      WHERE tipo_verificacion IS NULL AND tipo_cuenta = 'estudiante'
    `);
  }
  if (!sellerColsCarrera.some(c => c.name === 'tipo_verificacion')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN tipo_verificacion TEXT`);
  }

  // 27. Personalización del perfil: color de acento y producto fijado.
  //
  //     `colorAcento` guarda el ID del swatch ('salvia', 'navy', …) y no un
  //     hex: cada swatch son cuatro colores distintos (relleno, foreground,
  //     y la variante de línea de cada tema), así que guardar un hex suelto
  //     obligaría al cliente a adivinar los otros tres. Guardar el ID deja
  //     que la paleta evolucione sin migrar datos.
  //
  //     `producto_fijado_id` sin FOREIGN KEY, consistente con el resto del
  //     esquema: la integridad se valida en el PATCH (el producto debe ser
  //     del vendedor) y al leer se comprueba que siga existiendo, así que un
  //     producto borrado simplemente deja de aparecer fijado.
  const sellerColsPersonalizacion = db.prepare("PRAGMA table_info('sellers')").all();
  if (!sellerColsPersonalizacion.some(c => c.name === 'colorAcento')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN colorAcento TEXT`);
  }
  if (!sellerColsPersonalizacion.some(c => c.name === 'producto_fijado_id')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN producto_fijado_id TEXT`);
  }

  // 28. Tiempo de respuesta como MEDIANA, no promedio.
  //
  //     `avg_response_minutes` (migración 9) nunca llegó a poblarse: el
  //     ranking del feed la leía y siempre daba NULL, así que el bonus de
  //     "responde rápido" jamás se aplicó a nadie. Se reemplaza por una
  //     columna con el nombre correcto en vez de meter una mediana en una
  //     columna llamada "avg", que es la clase de mentira que después
  //     produce un bug imposible de leer.
  //
  //     La mediana es lo correcto aquí porque una sola conversación
  //     olvidada durante tres días arrastra el promedio de un vendedor que
  //     normalmente contesta en diez minutos; la mediana la ignora.
  const sellerColsRespuesta = db.prepare("PRAGMA table_info('sellers')").all();
  if (!sellerColsRespuesta.some(c => c.name === 'median_response_minutes')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN median_response_minutes INTEGER`);
  }
  if (sellerColsRespuesta.some(c => c.name === 'avg_response_minutes')) {
    // DROP COLUMN existe desde SQLite 3.35. Si la versión es anterior, la
    // columna muerta se queda: es preferible a abortar el arranque entero.
    try {
      db.exec(`ALTER TABLE sellers DROP COLUMN avg_response_minutes`);
    } catch (err) {
      console.warn('No se pudo eliminar avg_response_minutes:', err.message);
    }
  }

  // 29. Carrito POR USUARIO.
  //
  //     La tabla `cart` nació sin `user_id`: había una sola fila por
  //     producto para toda la instalación, y `GET /api/cart` ni siquiera
  //     pedía autenticación. En la práctica eso es un carrito global
  //     compartido — cualquiera veía y modificaba lo que otra persona había
  //     agregado. Es un bug de privacidad, no una decisión de diseño.
  //
  //     Las filas que ya existen se quedan con user_id NULL a propósito: no
  //     hay forma de saber a quién pertenecían, y adivinar sería peor que
  //     descartarlas. Las consultas filtran por user_id, así que quedan
  //     inertes.
  const cartCols = db.prepare("PRAGMA table_info('cart')").all();
  if (!cartCols.some(c => c.name === 'user_id')) {
    db.exec(`ALTER TABLE cart ADD COLUMN user_id TEXT`);
  }
  // Un producto aparece una sola vez por carrito: la cantidad vive en la
  // fila. El índice es parcial (WHERE user_id IS NOT NULL) para que las
  // filas huérfanas de la migración no choquen entre sí.
  db.exec(`
    CREATE UNIQUE INDEX IF NOT EXISTS idx_cart_user_product
      ON cart(user_id, productId) WHERE user_id IS NOT NULL;
  `);

  // 30. Pagos con Mercado Pago (split payments / marketplace).
  //
  //     Ver backend/src/payments/ para la lógica. Notas de esquema:
  //
  //     - `orders` es la primera tabla de dinero del proyecto; no había
  //       ninguna tabla de órdenes/pedidos/transacciones que extender.
  //     - Comprador y vendedor son ambos filas de `sellers`: esa tabla hace
  //       de tabla de usuarios en este proyecto (el `sub` del JWT es un
  //       `sellers.id`, ver auth.js).
  //     - Los importes van en REAL de pesos (no centavos) por consistencia
  //       con `products.priceNum`, y se redondean a 2 decimales al escribir.
  //     - Los tokens de Mercado Pago del vendedor se guardan CIFRADOS
  //       (AES-256-GCM, ver payments/crypto.js). Las columnas llevan el
  //       sufijo `_enc` justamente para que un SELECT en producción deje
  //       claro que ese contenido no es utilizable tal cual.
  //     - NUNCA se guarda número completo de tarjeta, CVV ni card_token.
  //       `saved_cards` solo tiene la referencia opaca de MP y los últimos
  //       cuatro dígitos, que es lo que la UI necesita pintar.
  db.exec(`
    CREATE TABLE IF NOT EXISTS orders (
      id TEXT PRIMARY KEY,
      buyer_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      vendor_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      amount REAL NOT NULL,
      application_fee REAL NOT NULL DEFAULT 0,
      currency TEXT NOT NULL DEFAULT 'MXN',
      status TEXT NOT NULL DEFAULT 'pending'
        CHECK(status IN ('pending','paid','cancelled','requires_other_method')),
      payment_status TEXT
        CHECK(payment_status IS NULL OR payment_status IN
          ('pending','in_process','approved','authorized','in_mediation',
           'rejected','refunded','cancelled','charged_back')),
      -- Cómo se acordó pagar esta orden. Solo 'tarjeta' se cobra dentro de la
      -- app; el resto son acuerdos entre las partes que la app únicamente
      -- registra. El CHECK es defensa en profundidad: la autorización real
      -- (¿este vendedor puede cobrar con tarjeta?) se valida en el servidor
      -- al crear la orden y otra vez antes de cobrar.
      payment_method TEXT
        CHECK(payment_method IS NULL OR payment_method IN
          ('efectivo','paypal','cripto','tarjeta')),
      mp_payment_id TEXT UNIQUE,
      origin TEXT NOT NULL DEFAULT 'direct' CHECK(origin IN ('direct','cart')),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_orders_buyer ON orders(buyer_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_orders_vendor ON orders(vendor_id, created_at DESC);
  `);

  // 30b. Migrar orders. Cubre tres cambios que solo se pueden aplicar
  //      recreando la tabla, porque SQLite no permite alterar un CHECK:
  //
  //      1. payment_status no aceptaba 'authorized' ni 'in_mediation' —
  //         estados reales de MP cuando el cobro YA se hizo (retención en
  //         pago diferido, disputa abierta). Sin esto el UPDATE truena y el
  //         mp_payment_id nunca se guarda: dinero cobrado sin registrar.
  //      2. Falta la columna payment_method.
  //      3. status no aceptaba 'requires_other_method', el estado al que va
  //         una orden cuyo vendedor perdió la conexión con MP entre que se
  //         creó y que se intentó cobrar. Sin un estado propio, esa orden se
  //         queda como 'pending' y nadie sabe que hay que hacer algo con ella.
  const ordersSql = db.prepare(
    `SELECT sql FROM sqlite_master WHERE type='table' AND name='orders'`,
  ).get();
  const ordersDesactualizada = ordersSql && (
    !ordersSql.sql.includes('authorized')
    || !ordersSql.sql.includes('payment_method')
    || !ordersSql.sql.includes('requires_other_method')
  );
  if (ordersDesactualizada) {
    db.pragma('foreign_keys = OFF');
    // `legacy_alter_table = ON` es lo que impide que el RENAME de abajo
    // corrompa OTRAS tablas.
    //
    // En SQLite moderno, `ALTER TABLE orders RENAME TO orders_legacy` no
    // solo renombra: reescribe las claves foráneas que apuntan a `orders`
    // desde otras tablas, para que sigan apuntando "a la misma" tabla. Aquí
    // eso es justo lo contrario de lo que queremos: `order_items` acababa
    // referenciando "orders_legacy", que tres líneas más abajo se borra, y
    // se quedaba con una FK colgando. Resultado: TODO INSERT en order_items
    // muere con `no such table: main.orders_legacy` y no se puede crear
    // ninguna orden.
    //
    // `foreign_keys = OFF` NO evita esa reescritura — son pragmas distintos.
    db.pragma('legacy_alter_table = ON');
    try {
      const migrateOrders = db.transaction(() => {
        db.exec(`
          ALTER TABLE orders RENAME TO orders_legacy;

          CREATE TABLE orders (
            id TEXT PRIMARY KEY,
            buyer_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
            vendor_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
            amount REAL NOT NULL,
            application_fee REAL NOT NULL DEFAULT 0,
            currency TEXT NOT NULL DEFAULT 'MXN',
            status TEXT NOT NULL DEFAULT 'pending'
              CHECK(status IN ('pending','paid','cancelled','requires_other_method')),
            payment_status TEXT
              CHECK(payment_status IS NULL OR payment_status IN
                ('pending','in_process','approved','authorized','in_mediation',
                 'rejected','refunded','cancelled','charged_back')),
            payment_method TEXT
              CHECK(payment_method IS NULL OR payment_method IN
                ('efectivo','paypal','cripto','tarjeta')),
            mp_payment_id TEXT UNIQUE,
            origin TEXT NOT NULL DEFAULT 'direct' CHECK(origin IN ('direct','cart')),
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
          );

          -- Columnas explícitas y NO 'SELECT *': la tabla nueva tiene una
          -- columna más que la vieja, así que un SELECT * desalinearía los
          -- valores o fallaría por número de columnas. Las órdenes
          -- históricas se quedan con payment_method NULL, que es la verdad:
          -- se crearon antes de que el método se registrara.
          INSERT INTO orders
            (id, buyer_id, vendor_id, amount, application_fee, currency,
             status, payment_status, mp_payment_id, origin, created_at, updated_at)
          SELECT
             id, buyer_id, vendor_id, amount, application_fee, currency,
             status, payment_status, mp_payment_id, origin, created_at, updated_at
          FROM orders_legacy;

          DROP TABLE orders_legacy;

          CREATE INDEX IF NOT EXISTS idx_orders_buyer ON orders(buyer_id, created_at DESC);
          CREATE INDEX IF NOT EXISTS idx_orders_vendor ON orders(vendor_id, created_at DESC);
        `);
      });
      migrateOrders();
    } finally {
      db.pragma('legacy_alter_table = OFF');
      db.pragma('foreign_keys = ON');
    }
  }

  db.exec(`
    -- Precio y título CONGELADOS al crear la orden. Si se leyeran de
    -- products en vez de copiarse, un vendedor que edite el precio después
    -- reescribiría el histórico de algo que alguien ya pagó.
    CREATE TABLE IF NOT EXISTS order_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      product_id TEXT NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 1,
      unit_price REAL NOT NULL,
      title_snapshot TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);

    -- Cuenta de Mercado Pago del VENDEDOR, vinculada por OAuth. Su
    -- access_token es lo que permite cobrar en su nombre quedándonos la
    -- comisión (application_fee).
    -- La columna provider existe para que añadir otra pasarela a futuro no
    -- obligue a rehacer la tabla: el UNIQUE es (seller_id, provider), así
    -- que un mismo vendedor puede llegar a tener una cuenta por proveedor.
    --
    -- El estado conectado/desconectado NO tiene columna propia: es
    -- revoked_at IS NULL. Una segunda columna que dijera lo mismo se
    -- desincroniza en cuanto un camino actualice una y no la otra. La API
    -- expone un campo status derivado de aquí.
    CREATE TABLE IF NOT EXISTS vendor_payment_accounts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      seller_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      provider TEXT NOT NULL DEFAULT 'mercadopago',
      mp_user_id TEXT NOT NULL,
      mp_access_token_enc TEXT NOT NULL,
      mp_refresh_token_enc TEXT,
      mp_token_expires_at TEXT,
      mp_public_key TEXT,
      connected_at TEXT NOT NULL DEFAULT (datetime('now')),
      revoked_at TEXT,
      -- Por qué se desconectó y quién lo detectó ('user' | 'webhook' |
      -- 'token_check'). Sin esto, un vendedor desconectado por revocación
      -- externa es indistinguible de uno que se desconectó a propósito, y el
      -- mensaje que se le muestra no puede ser el correcto.
      disconnect_reason TEXT,
      disconnected_by TEXT
        CHECK(disconnected_by IS NULL OR disconnected_by IN ('user','webhook','token_check')),
      UNIQUE(seller_id, provider)
    );

    -- Customer de MP del COMPRADOR: el contenedor al que se le cuelgan las
    -- tarjetas guardadas.
    --
    -- Es por (comprador, VENDEDOR), no por comprador: en el modo marketplace
    -- de MP el Customer y sus tarjetas viven dentro de la cuenta del
    -- vendedor que los creó, y el token de otro vendedor no puede cobrarlos
    -- (devuelve "Card Token not found"). Por eso un comprador registra su
    -- tarjeta una vez por cada vendedor al que le compra.
    CREATE TABLE IF NOT EXISTS buyer_mp_customers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      seller_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      vendor_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      mp_customer_id TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(seller_id, vendor_id)
    );

    CREATE TABLE IF NOT EXISTS saved_cards (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      seller_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      vendor_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      mp_card_id TEXT NOT NULL,
      last_four_digits TEXT,
      payment_method TEXT,
      expiration_month INTEGER,
      expiration_year INTEGER,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(seller_id, vendor_id, mp_card_id)
    );
    CREATE INDEX IF NOT EXISTS idx_saved_cards_seller
      ON saved_cards(seller_id, vendor_id);

    -- Idempotencia del webhook: MP reintenta la misma notificación varias
    -- veces (y ante un timeout, muchas). El UNIQUE sobre event_id es lo que
    -- hace que el segundo intento no vuelva a aplicar efectos.
    CREATE TABLE IF NOT EXISTS mp_webhook_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event_id TEXT NOT NULL UNIQUE,
      topic TEXT,
      resource_id TEXT,
      received_at TEXT NOT NULL DEFAULT (datetime('now')),
      processed_at TEXT
    );

    -- Parámetro "state" del OAuth de MP: protección CSRF. Sin él, alguien
    -- podría hacer que el callback vincule SU cuenta de Mercado Pago al
    -- vendedor equivocado, desviando los cobros.
    CREATE TABLE IF NOT EXISTS payment_oauth_states (
      state TEXT PRIMARY KEY,
      seller_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      used_at TEXT
    );
  `);

  const tieneColumna = (tabla, columna) =>
    db.prepare(`PRAGMA table_info('${tabla}')`).all().some(c => c.name === columna);

  /** Recrea una tabla (única vía en SQLite para tocar UNIQUE o CHECK). */
  const recrear = (nombre, ddl) => {
    db.pragma('foreign_keys = OFF');
    try {
      db.transaction(() => db.exec(ddl))();
    } finally {
      db.pragma('foreign_keys = ON');
    }
  };

  // 30c. vendor_payment_accounts: añadir `provider` y el motivo de
  //      desconexión, y pasar el UNIQUE de (seller_id) a (seller_id,
  //      provider). Las cuentas ya conectadas se conservan tal cual y se
  //      etiquetan como 'mercadopago', que es lo único que había.
  if (!tieneColumna('vendor_payment_accounts', 'provider')) {
    recrear('vendor_payment_accounts', `
      ALTER TABLE vendor_payment_accounts RENAME TO vpa_legacy;

      CREATE TABLE vendor_payment_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seller_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
        provider TEXT NOT NULL DEFAULT 'mercadopago',
        mp_user_id TEXT NOT NULL,
        mp_access_token_enc TEXT NOT NULL,
        mp_refresh_token_enc TEXT,
        mp_token_expires_at TEXT,
        mp_public_key TEXT,
        connected_at TEXT NOT NULL DEFAULT (datetime('now')),
        revoked_at TEXT,
        disconnect_reason TEXT,
        disconnected_by TEXT
          CHECK(disconnected_by IS NULL OR disconnected_by IN ('user','webhook','token_check')),
        UNIQUE(seller_id, provider)
      );

      INSERT INTO vendor_payment_accounts
        (id, seller_id, provider, mp_user_id, mp_access_token_enc,
         mp_refresh_token_enc, mp_token_expires_at, mp_public_key,
         connected_at, revoked_at)
      SELECT
         id, seller_id, 'mercadopago', mp_user_id, mp_access_token_enc,
         mp_refresh_token_enc, mp_token_expires_at, mp_public_key,
         connected_at, revoked_at
      FROM vpa_legacy;

      DROP TABLE vpa_legacy;
    `);
  }

  // 30d y 30e. buyer_mp_customers y saved_cards pasan a ser por (comprador,
  //      vendedor).
  //
  //      Las filas existentes NO se migran, se descartan. No es negligencia:
  //      esos Customers y esas tarjetas se crearon bajo la cuenta de la
  //      PLATAFORMA, y en el modo marketplace de MP el token de un vendedor
  //      no puede cobrar una tarjeta que vive en otra cuenta — devuelve
  //      "Card Token not found". Son datos que ya no sirven para cobrar
  //      nada, así que arrastrarlos con un vendor_id inventado solo
  //      produciría fallos en el momento del pago. Los compradores vuelven a
  //      registrar su tarjeta la primera vez que le compren a cada vendedor.
  //      Del lado de MP los Customers siguen existiendo; limpiarlos allá es
  //      opcional y no afecta a la app.
  if (!tieneColumna('buyer_mp_customers', 'vendor_id')) {
    recrear('buyer_mp_customers', `
      DROP TABLE buyer_mp_customers;
      CREATE TABLE buyer_mp_customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seller_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
        vendor_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
        mp_customer_id TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(seller_id, vendor_id)
      );
    `);
  }

  if (!tieneColumna('saved_cards', 'vendor_id')) {
    recrear('saved_cards', `
      DROP TABLE saved_cards;
      CREATE TABLE saved_cards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seller_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
        vendor_id TEXT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
        mp_card_id TEXT NOT NULL,
        last_four_digits TEXT,
        payment_method TEXT,
        expiration_month INTEGER,
        expiration_year INTEGER,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(seller_id, vendor_id, mp_card_id)
      );
      CREATE INDEX IF NOT EXISTS idx_saved_cards_seller
        ON saved_cards(seller_id, vendor_id);
    `);
  }

  // 30f. 'transferencia' sale del catálogo de métodos de pago.
  purgarMetodoDePago(db, 'transferencia');

  // 31. Responder a un mensaje concreto del chat (estilo WhatsApp).
  //     Nullable: la enorme mayoría de los mensajes no son respuesta.
  //     ON DELETE SET NULL y no CASCADE: si el mensaje citado desapareciera,
  //     la respuesta debe sobrevivir sin cita, no borrarse con él. En la
  //     práctica el borrado del chat es lógico (se reemplaza el texto por
  //     '[Mensaje eliminado]'), así que la cita sigue existiendo y muestra
  //     ese placeholder, igual que la burbuja original.
  const msgColsReply = db.prepare("PRAGMA table_info('messages')").all();
  const hasReplyTo = msgColsReply.some(c => c.name === 'reply_to_message_id');
  if (!hasReplyTo) {
    db.exec(`
      ALTER TABLE messages ADD COLUMN reply_to_message_id TEXT DEFAULT NULL
        REFERENCES messages(id) ON DELETE SET NULL
    `);
  }

  // 32. `identidad_confirmada_en`: cuándo se demostró la identidad (OTP de
  //     correo o SMS confirmado), independientemente de si la verificación
  //     llegó a completarse.
  //
  //     Hace falta porque conectar Mercado Pago pasó a ser requisito de la
  //     verificación para TODOS los tipos de cuenta, y conectarlo obliga a
  //     salir al navegador y volver — un viaje que dura más que los 10
  //     minutos de vida del código. Sin esta columna, quien va a conectar su
  //     cuenta vuelve con el código ya expirado y tiene que pedir otro, que
  //     es exactamente el bucle que hace que la gente abandone.
  //
  //     También es lo que autoriza a conectar Mercado Pago antes de estar
  //     verificado (ver `puedeVender` en payments/routes.js): sin ella la
  //     regla sería circular —no te verificas sin conectar, no conectas sin
  //     estar verificado— y nadie podría completar ninguna de las dos.
  const verifColsIdentidad = db.prepare("PRAGMA table_info('verificaciones')").all();
  if (!verifColsIdentidad.some(c => c.name === 'identidad_confirmada_en')) {
    db.exec(`ALTER TABLE verificaciones ADD COLUMN identidad_confirmada_en TEXT`);
    // Quien ya está verificado demostró su identidad por definición. Sin
    // este relleno, un verificado que se desverificara quedaría con la
    // columna en NULL y tendría que repetir el OTP sin motivo.
    db.exec(`
      UPDATE verificaciones SET identidad_confirmada_en = COALESCE(fecha_verificacion, creado_en)
      WHERE identidad_confirmada_en IS NULL AND estado = 'verificado'
    `);
  }

  // 33. Reparar `order_items` con la FK colgando hacia `orders_legacy`.
  //
  //     La migración 30b la rompió en todo despliegue que venía de la versión
  //     anterior (ver el comentario ahí). Arreglar 30b evita el daño nuevo,
  //     pero no cura las bases ya dañadas: ahí `order_items` sigue con
  //     `REFERENCES "orders_legacy"` y no se puede crear ninguna orden.
  //
  //     No se puede alterar una FK en SQLite, así que toca reconstruir la
  //     tabla — copiando las filas, que son ventas reales.
  const orderItemsSql = db.prepare(
    `SELECT sql FROM sqlite_master WHERE type='table' AND name='order_items'`,
  ).get();
  if (orderItemsSql && orderItemsSql.sql.includes('orders_legacy')) {
    console.warn('[db] Reparando order_items: su FK apuntaba a orders_legacy');
    db.pragma('foreign_keys = OFF');
    // Igual que en 30b: sin esto, el RENAME final reescribiría referencias
    // ajenas y volveríamos a dejar el mismo desastre en otra tabla.
    db.pragma('legacy_alter_table = ON');
    try {
      db.transaction(() => {
        db.exec(`
          CREATE TABLE order_items_reparada (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
            product_id TEXT NOT NULL,
            quantity INTEGER NOT NULL DEFAULT 1,
            unit_price REAL NOT NULL,
            title_snapshot TEXT
          );

          -- Columnas explícitas: un SELECT * se rompería en silencio si el
          -- orden de columnas de la tabla vieja no fuera exactamente éste.
          INSERT INTO order_items_reparada
            (id, order_id, product_id, quantity, unit_price, title_snapshot)
          SELECT id, order_id, product_id, quantity, unit_price, title_snapshot
          FROM order_items;

          DROP TABLE order_items;
          ALTER TABLE order_items_reparada RENAME TO order_items;

          CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
        `);
      })();
    } finally {
      db.pragma('legacy_alter_table = OFF');
      db.pragma('foreign_keys = ON');
    }
  }

  // 34. Redes sociales del negocio (Facebook, Instagram, WhatsApp, TikTok,
  //     X/Twitter): todas opcionales, solo tienen sentido cuando isBusiness.
  //     whatsapp_number guarda dígitos crudos con código de país (no la URL
  //     wa.me completa) para que la validación sea un regex simple y el
  //     cliente arme el link de forma determinista: https://wa.me/<número>.
  //     Ver docs/superpowers/specs/2026-08-08-business-social-links-design.md.
  const sellerColsSocial = db.prepare("PRAGMA table_info('sellers')").all();
  const socialColumns = ['facebook_url', 'instagram_url', 'whatsapp_number', 'tiktok_url', 'twitter_url'];
  for (const column of socialColumns) {
    if (!sellerColsSocial.some(c => c.name === column)) {
      db.exec(`ALTER TABLE sellers ADD COLUMN ${column} TEXT`);
    }
  }

  // 35. Preferencia de Mercado Pago viva de una orden.
  //
  //     Existe para impedir un COBRO DUPLICADO REAL. Con dos carriles de
  //     pago sobre la misma orden —tarjeta dentro de la app y la cuenta de
  //     Mercado Pago del comprador— aparece una ventana peligrosa: crear una
  //     preferencia no cobra nada y deja la orden en 'pending', así que las
  //     guardas de "esta orden ya fue procesada" no la ven. Mientras tanto
  //     esa preferencia está viva y es pagable en Mercado Pago.
  //
  //     El escenario no necesita mala fe: alguien empieza a pagar con su
  //     cuenta, se sale sin terminar, paga con tarjeta, y más tarde vuelve a
  //     la pestaña de Mercado Pago que dejó abierta y la completa. Dos
  //     cargos reales. El segundo ni siquiera queda registrado — el webhook
  //     se niega a pisar un pago ya aprobado— así que el dinero desaparece
  //     de nuestra vista.
  //
  //     Guardando la preferencia y hasta cuándo es pagable, el cobro con
  //     tarjeta puede negarse mientras exista, y una segunda petición de
  //     wallet devuelve LA MISMA preferencia en vez de crear otra.
  const orderColsPref = db.prepare("PRAGMA table_info('orders')").all();
  for (const [columna, tipo] of [
    ['mp_preference_id', 'TEXT'],
    ['mp_preference_init_point', 'TEXT'],
    // ISO 8601. Se guarda con un margen por encima de la caducidad que se le
    // pide a Mercado Pago: el bloqueo tiene que durar MÁS que la ventana en
    // la que la preferencia se puede pagar, nunca menos.
    ['mp_preference_expires_at', 'TEXT'],
  ]) {
    if (!orderColsPref.some(c => c.name === columna)) {
      db.exec(`ALTER TABLE orders ADD COLUMN ${columna} ${tipo}`);
    }
  }

  // 36. Preguntas dinámicas por categoría (`atributos_categoria`).
  //
  //     Las respuestas viven como UN JSON en una columna del producto y no
  //     en una tabla `product_attributes(product_id, key, value)`. Tres
  //     razones concretas de este proyecto, no una preferencia de estilo:
  //
  //     a) La búsqueda de hoy no es SQL. `GET /api/products?search=` filtra
  //        el array en memoria de data.js con Array.filter, así que un
  //        filtro por atributo va a ser un predicado JS sobre un objeto ya
  //        parseado. Un JOIN no ahorraría nada; solo obligaría a hidratar
  //        el N:M por separado.
  //
  //     b) `saveData()` recorre TODOS los productos y hace upsert de cada
  //        uno. Con tabla hija, cada guardado implicaría borrar y reinsertar
  //        los atributos de todo el catálogo — exactamente el patrón que ya
  //        costó caro con product_ratings (ver insertProduct) y con el
  //        carrito global.
  //
  //     c) Los atributos siempre se leen completos, junto al producto. No
  //        existe la consulta "dame solo la talla de este producto".
  //
  //     Además es el patrón que ya usan `images`, `extras`, `availableDays`
  //     y `paymentMethods`: un modelo mixto sería la única inconsistencia.
  //
  //     El costo asumido es que no se puede indexar en SQL. Cuando la
  //     búsqueda migre a consultas reales, SQLite permite montar un índice
  //     de expresión sobre json_extract(atributos_categoria, '$.talla') sin
  //     cambiar el esquema ni migrar datos.
  //
  //     NULL (no '{}') es el valor de "no contestó nada": es lo que ya
  //     tienen las filas existentes y ahorra guardar una cadena inútil en
  //     cada producto del histórico. rowToProduct lo traduce a {}.
  const colsAtributos = db.prepare("PRAGMA table_info('products')").all();
  if (!colsAtributos.some(c => c.name === 'atributos_categoria')) {
    db.exec(`ALTER TABLE products ADD COLUMN atributos_categoria TEXT DEFAULT NULL`);
  }

  // 37. Presencia ("en línea" / "activo hace X").
  //
  //     Solo dos columnas, y NINGUNA de ellas es `is_online`. Quién está
  //     conectado ahora mismo se sabe por los sockets abiertos (ver
  //     presence.js): persistirlo dejaría a todo el mundo marcado en línea
  //     si el proceso muere sin llegar a escribir el `false`.
  //
  //     `last_active` se escribe UNA vez, al cerrarse el último socket del
  //     usuario — no en cada latido. NULL significa "nunca se ha registrado
  //     una desconexión", que es lo correcto para las filas ya existentes.
  //
  //     `show_online_status` arranca en 1 (compartir) porque es el
  //     comportamiento que la función anuncia; quien no lo quiera lo apaga
  //     en Configuración → Privacidad, y entonces deja de emitirse su
  //     estado y también de recibir el ajeno (ver presenciaVisible).
  const sellerColsPresencia = db.prepare("PRAGMA table_info('sellers')").all();
  if (!sellerColsPresencia.some(c => c.name === 'last_active')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN last_active TEXT`);
  }
  if (!sellerColsPresencia.some(c => c.name === 'show_online_status')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN show_online_status INTEGER NOT NULL DEFAULT 1`);
  }

  // 38. Iniciar sesión con Google.
  //
  //     `auth_provider` dice CÓMO entra esa cuenta: 'password' (correo y
  //     contraseña, lo de siempre) o 'google'. No se deduce de que
  //     `password_hash` esté vacío, y esa distinción es justamente lo que
  //     cierra un agujero real: /api/auth/register trata una fila sin
  //     password_hash como "cuenta legacy" y le rellena la contraseña que le
  //     manden (migración 21). Sin esta columna, saber el correo de alguien
  //     que entró con Google bastaría para ponerle contraseña y quedarse con
  //     su cuenta. El DEFAULT 'password' deja a todas las filas existentes
  //     exactamente como estaban.
  //
  //     `google_sub` es el identificador estable que Google da a una cuenta.
  //     Se guarda además del correo porque el correo SÍ puede cambiar: quien
  //     cambia su dirección en Google debe seguir entrando a la misma cuenta
  //     de aquí. El índice es UNIQUE parcial (WHERE NOT NULL) para que las
  //     miles de filas sin `sub` no choquen entre sí.
  //
  //     `avatarUrl` es la foto de perfil que devuelve Google. Es distinta de
  //     `logoUrl`, que es el logo que un negocio sube a este servidor: aquí
  //     se guarda una URL remota de Google, no un archivo nuestro.
  const sellerColsGoogle = db.prepare("PRAGMA table_info('sellers')").all();
  if (!sellerColsGoogle.some(c => c.name === 'auth_provider')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN auth_provider TEXT NOT NULL DEFAULT 'password'`);
  }
  if (!sellerColsGoogle.some(c => c.name === 'google_sub')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN google_sub TEXT`);
  }
  if (!sellerColsGoogle.some(c => c.name === 'avatarUrl')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN avatarUrl TEXT`);
  }
  db.exec(`
    CREATE UNIQUE INDEX IF NOT EXISTS idx_sellers_google_sub
      ON sellers(google_sub) WHERE google_sub IS NOT NULL;
  `);

  // 39. Trending searches: agrupar por término real, no por cadena exacta.
  //
  //     Antes se agrupaba por `query_text` tal cual, así que "cálculo",
  //     "calculo" y "calculos" eran tres términos distintos con un voto cada
  //     uno y ninguno llegaba al top. `query_key` es la forma canónica
  //     (searchQueryKey) y es la columna por la que se agrupa ahora.
  //
  //     `device_id` deja contar dispositivos distintos en vez de tecleos.
  //     Las filas viejas se quedan en NULL a propósito: cada una cuenta como
  //     una unidad suelta, que es exactamente lo que valían antes.
  const searchCols = db.prepare("PRAGMA table_info('search_queries')").all();
  if (!searchCols.some(c => c.name === 'query_key')) {
    db.exec(`ALTER TABLE search_queries ADD COLUMN query_key TEXT`);
  }
  if (!searchCols.some(c => c.name === 'device_id')) {
    db.exec(`ALTER TABLE search_queries ADD COLUMN device_id TEXT`);
  }
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_search_queries_key
      ON search_queries(query_key, created_at);
  `);
  // Backfill: la clave se calcula en JS (quitar acentos no se puede en SQL
  // puro), pero solo sobre las filas dentro de la ventana que el ranking
  // mira. Rellenar años de historial que nadie va a consultar sería trabajo
  // de arranque tirado a la basura.
  const sinClave = db.prepare(`
    SELECT id, query_text FROM search_queries
    WHERE query_key IS NULL AND created_at >= datetime('now', '-30 days')
  `).all();
  if (sinClave.length > 0) {
    const setClave = db.prepare('UPDATE search_queries SET query_key = ? WHERE id = ?');
    db.transaction(filas => {
      for (const fila of filas) setClave.run(searchQueryKey(fila.query_text), fila.id);
    })(sinClave);
  }

  // 40. Interés por categoría: admitir el evento `categoria` (el usuario
  //     entró a navegar una categoría, sin abrir ningún producto).
  //
  //     Exige reconstruir la tabla, no un ALTER: hay que relajar el CHECK de
  //     `tipo` y quitar el NOT NULL de `product_id` (ver una categoría no
  //     tiene producto asociado), y SQLite no permite alterar constraints in
  //     place. Se copian las filas existentes tal cual.
  const interCols = db.prepare("PRAGMA table_info('interacciones_dispositivo')").all();
  const productIdNulable = interCols.find(c => c.name === 'product_id')?.notnull === 0;
  if (interCols.length > 0 && !productIdNulable) {
    db.exec(`
      PRAGMA foreign_keys = OFF;

      CREATE TABLE interacciones_dispositivo_nueva (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        user_id TEXT,
        product_id TEXT,
        category TEXT NOT NULL,
        tipo TEXT NOT NULL CHECK(tipo IN ('vista', 'favorito', 'contacto', 'categoria')),
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      );

      INSERT INTO interacciones_dispositivo_nueva
        (id, device_id, user_id, product_id, category, tipo, created_at)
        SELECT id, device_id, user_id, product_id, category, tipo, created_at
        FROM interacciones_dispositivo;

      DROP TABLE interacciones_dispositivo;
      ALTER TABLE interacciones_dispositivo_nueva RENAME TO interacciones_dispositivo;

      CREATE INDEX IF NOT EXISTS idx_interacciones_device ON interacciones_dispositivo(device_id, created_at);
      CREATE INDEX IF NOT EXISTS idx_interacciones_user ON interacciones_dispositivo(user_id, created_at);
      CREATE INDEX IF NOT EXISTS idx_interacciones_producto_tipo ON interacciones_dispositivo(product_id, tipo);
      CREATE INDEX IF NOT EXISTS idx_interacciones_device_categoria ON interacciones_dispositivo(device_id, category, created_at);
      CREATE INDEX IF NOT EXISTS idx_interacciones_user_categoria ON interacciones_dispositivo(user_id, category, created_at);

      PRAGMA foreign_keys = ON;
    `);
  }

  // 41. Borrado de conversaciones por participante.
  //
  //     Una conversación pertenece a dos personas, por lo que borrarla de
  //     la bandeja de una no debe destruir el historial de la otra. Se guarda
  //     el id del último mensaje que esa persona decidió retirar: así, si
  //     después llega uno nuevo, el chat reaparece pero el historial borrado
  //     no vuelve a mostrársele. El corte se resuelve a rowid al consultar (en
  //     vez de persistir el rowid), porque SQLite puede renumerarlos al hacer
  //     VACUUM mientras que el id del mensaje sí es estable.
  //
  //     La tabla se crea aquí (después de la migración 10 que reconstruye
  //     conversations) para que una base muy antigua no termine con una FK
  //     reescrita hacia conversations_legacy durante aquella migración.
  db.exec(`
    CREATE TABLE IF NOT EXISTS conversation_deletions (
      conversation_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      deleted_through_message_id TEXT DEFAULT NULL,
      deleted_at TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (conversation_id, user_id),
      FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_conversation_deletions_user
      ON conversation_deletions(user_id, conversation_id);
  `);

  // 42. Preferencias de seguridad entre dos cuentas.
  //
  //     Cada dirección se guarda por separado: Ana puede silenciar a Beto
  //     sin que Beto la silencie a ella. Un bloqueo, en cambio, se consulta
  //     en ambos sentidos al enviar porque una persona bloqueada no debe
  //     poder seguir contactando al bloqueador ni recibir mensajes suyos por
  //     accidente hasta que este lo desbloquee.
  //
  //     No hay FK hacia sellers: el chat también admite ids de sesiones
  //     anónimas y las tablas messages/conversations siguen esa misma regla.
  db.exec(`
    CREATE TABLE IF NOT EXISTS chat_user_settings (
      owner_id TEXT NOT NULL,
      target_id TEXT NOT NULL,
      blocked INTEGER NOT NULL DEFAULT 0,
      muted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (owner_id, target_id),
      CHECK(owner_id != target_id)
    );

    CREATE INDEX IF NOT EXISTS idx_chat_user_settings_target
      ON chat_user_settings(target_id, owner_id);
  `);

  // Reportes reales: dejan de ser mensajes perdidos en un chat de soporte y
  // pasan a una cola moderable con estado, historial mínimo y trazabilidad.
  db.exec(`
    CREATE TABLE IF NOT EXISTS reports (
      id TEXT PRIMARY KEY,
      reporter_id TEXT NOT NULL,
      target_type TEXT NOT NULL CHECK(target_type IN ('user', 'product', 'wanted', 'chat')),
      target_id TEXT NOT NULL,
      target_user_id TEXT,
      reason TEXT NOT NULL,
      details TEXT DEFAULT '',
      status TEXT NOT NULL DEFAULT 'received'
        CHECK(status IN ('received', 'reviewing', 'resolved', 'dismissed')),
      admin_note TEXT DEFAULT '',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      resolved_at TEXT,
      resolved_by_admin_id INTEGER,
      FOREIGN KEY (resolved_by_admin_id) REFERENCES admins(id) ON DELETE SET NULL
    );

    CREATE INDEX IF NOT EXISTS idx_reports_status_created
      ON reports(status, created_at DESC, id DESC);
    CREATE INDEX IF NOT EXISTS idx_reports_reporter
      ON reports(reporter_id, created_at DESC, id DESC);
    CREATE INDEX IF NOT EXISTS idx_reports_target
      ON reports(target_type, target_id, created_at DESC, id DESC);
  `);

  // Insignia verde "Socio Fundador": columna nueva en `sellers`, para bases
  // que ya existían antes de agregarla al CREATE TABLE de arriba.
  const sellerColsSocio = db.prepare("PRAGMA table_info('sellers')").all();
  if (!sellerColsSocio.some(c => c.name === 'socio_fundador')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN socio_fundador INTEGER DEFAULT 0`);
  }

  // 42. Fecha de alta de la cuenta (ver CREATE TABLE de arriba), para bases
  //     que ya existían antes de agregarla. SQLite no acepta un default
  //     no-constante (como datetime('now')) en un ADD COLUMN, así que se
  //     agrega sin default y se rellena aparte: las cuentas ya existentes
  //     quedan con la fecha de esta migración (lo más cerca de su alta real
  //     que se puede reconstruir sin haberlo guardado antes). Las cuentas
  //     nuevas no dependen de un default de columna — data.js, authGoogle.js
  //     e insertSeller mandan `datetime('now')` explícito en su INSERT.
  const sellerColsCreatedAt = db.prepare("PRAGMA table_info('sellers')").all();
  if (!sellerColsCreatedAt.some(c => c.name === 'created_at')) {
    db.exec(`
      ALTER TABLE sellers ADD COLUMN created_at TEXT;
      UPDATE sellers SET created_at = datetime('now') WHERE created_at IS NULL;
    `);
  }

  // 43. Qué insignias muestra el perfil público.
  //
  //     Se guardan las OCULTAS (JSON array de claves), no las visibles, y
  //     eso no es un detalle de forma: con la lista de visibles, toda cuenta
  //     existente arrancaría con lista vacía —perfil sin insignias— y cada
  //     logro nuevo nacería invisible hasta que su dueño fuera a marcarlo.
  //     Con las ocultas, NULL significa "muéstralas todas", que es el
  //     comportamiento que había antes de este ajuste, y una insignia recién
  //     ganada aparece sola.
  //
  //     Sin CHECK de contenido: las claves válidas son un catálogo de
  //     producto (validation/insignias.js) que cambia cada vez que se añade
  //     una insignia, y un CHECK obligaría a migrar el schema por cada una.
  //     La puerta real es el PATCH, que rechaza cualquier clave desconocida.
  const sellerColsInsignias = db.prepare("PRAGMA table_info('sellers')").all();
  if (!sellerColsInsignias.some(c => c.name === 'insignias_ocultas')) {
    db.exec(`ALTER TABLE sellers ADD COLUMN insignias_ocultas TEXT`);
  }

  // 44. Insignias ya ganadas que no se pueden perder.
  //
  //     "Leyenda del Mercadito" pasó de 50 a 100 ventas confirmadas. La
  //     insignia se calcula al vuelo en cada carga del perfil, así que sin
  //     esto el cambio de umbral se la habría quitado de golpe a todo el que
  //     la tenía entre 50 y 99 ventas: gente que la ganó cumpliendo la regla
  //     que había, y que no hizo nada para perderla.
  //
  //     La tabla se crea aquí y no en el CREATE TABLE de initDatabase porque
  //     el rescate de abajo tiene que correr UNA sola vez, y lo único que
  //     distingue "primer arranque con esto" de los siguientes es que la
  //     tabla todavía no exista. Si se sembrara en cada arranque, quien
  //     llegara a 50 ventas MAÑANA quedaría condecorado también, y el umbral
  //     nuevo no serviría de nada.
  const tablaOtorgadas = db.prepare(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='insignias_otorgadas'",
  ).get();
  db.exec(`
    CREATE TABLE IF NOT EXISTS insignias_otorgadas (
      seller_id   TEXT NOT NULL,
      clave       TEXT NOT NULL,
      otorgada_en TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (seller_id, clave),
      FOREIGN KEY (seller_id) REFERENCES sellers(id) ON DELETE CASCADE
    );
  `);
  if (!tablaOtorgadas) {
    // Los umbrales van escritos a mano y no leídos de FEED_WEIGHTS: son los
    // que estaban VIGENTES el día de este cambio, un dato histórico. Leerlos
    // de la config haría que el rescate se moviera solo con el próximo
    // ajuste, que es justo lo contrario de lo que hace falta.
    const VENTAS_VIEJO = 50;      // umbral de Leyenda antes de subirlo a 100
    const ORO_VIGENTE = 100000;   // MXN facturados
    const CINCOS_VIGENTE = 100;   // calificaciones de 5 estrellas
    // Oro y Centenario no cambiaron de umbral, así que hoy esto no le da la
    // insignia a nadie que no la tuviera ya. Se siembran igual para que el
    // día que SÍ se muevan, quien las tenga hoy ya esté cubierto sin otra
    // migración de rescate.
    db.exec(`
      INSERT OR IGNORE INTO insignias_otorgadas (seller_id, clave)
        SELECT vendor_id, 'leyenda' FROM orders WHERE status = 'paid'
         GROUP BY vendor_id HAVING COUNT(*) >= ${VENTAS_VIEJO};

      INSERT OR IGNORE INTO insignias_otorgadas (seller_id, clave)
        SELECT vendor_id, 'vendedor_de_oro' FROM orders WHERE status = 'paid'
         GROUP BY vendor_id HAVING COALESCE(SUM(amount), 0) >= ${ORO_VIGENTE};

      INSERT OR IGNORE INTO insignias_otorgadas (seller_id, clave)
        SELECT p.seller, 'centenario'
          FROM product_ratings pr JOIN products p ON p.id = pr.product_id
         WHERE pr.stars = 5
         GROUP BY p.seller HAVING COUNT(*) >= ${CINCOS_VIGENTE};
    `);
    const rescatadas = db.prepare(
      'SELECT COUNT(*) AS n FROM insignias_otorgadas',
    ).get().n;
    if (rescatadas > 0) {
      console.log(`🎖️  ${rescatadas} insignia(s) ya ganadas quedan registradas de por vida`);
    }
  }

  // 45. Datos propios del flujo manual de verificación de negocios.
  // El responsable queda en la solicitud (no en el perfil público) y el hash
  // hace idempotentes las evidencias: reenviar el mismo archivo no crea otra
  // fila aunque la app se haya cerrado entre un intento y el siguiente.
  const verificacionColsManual = db
    .prepare("PRAGMA table_info('verificaciones')")
    .all();
  if (!verificacionColsManual.some(c => c.name === 'responsable_negocio')) {
    db.exec('ALTER TABLE verificaciones ADD COLUMN responsable_negocio TEXT');
  }
  if (!verificacionColsManual.some(c => c.name === 'solicitud_json')) {
    db.exec('ALTER TABLE verificaciones ADD COLUMN solicitud_json TEXT');
  }

  const documentoColsHash = db
    .prepare("PRAGMA table_info('verification_documents')")
    .all();
  if (!documentoColsHash.some(c => c.name === 'content_hash')) {
    db.exec('ALTER TABLE verification_documents ADD COLUMN content_hash TEXT');
  }

  const documentosSinHash = db.prepare(
    'SELECT id, file_url FROM verification_documents WHERE content_hash IS NULL',
  ).all();
  const guardarHashDocumento = db.prepare(
    'UPDATE verification_documents SET content_hash = ? WHERE id = ?',
  );
  for (const documento of documentosSinHash) {
    const archivo = path.join(
      __dirname,
      '..',
      'uploads',
      path.basename(documento.file_url),
    );
    try {
      const hash = crypto
        .createHash('sha256')
        .update(fs.readFileSync(archivo))
        .digest('hex');
      guardarHashDocumento.run(hash, documento.id);
    } catch {
      // Un archivo histórico ausente no debe impedir que arranque el backend.
    }
  }
  db.exec(
    'CREATE INDEX IF NOT EXISTS idx_verification_documents_hash '
      + 'ON verification_documents(usuario_id, doc_type, content_hash)',
  );
  // Los archivos de verificacion se bloquean en /uploads y solo se sirven por
  // el endpoint privado del panel. Este indice evita recorrer toda la tabla en
  // cada foto publica para decidir si la ruta corresponde a una evidencia.
  db.exec(
    'CREATE INDEX IF NOT EXISTS idx_verification_documents_file_url '
      + 'ON verification_documents(file_url)',
  );

  // 46. Historial inmutable de decisiones del panel privado. La tabla
  // `verificaciones` conserva solo el estado actual; este log mantiene cada
  // aprobación, rechazo y retiro con la instantánea del negocio.
  // No lleva FK: el historial sobrevive aunque la cuenta sea eliminada.
  db.exec(`
    CREATE TABLE IF NOT EXISTS verification_review_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id TEXT NOT NULL,
      accion TEXT NOT NULL CHECK(accion IN ('approved','rejected','revoked','restored')),
      motivo TEXT,
      nombre_negocio TEXT NOT NULL,
      categoria_negocio TEXT,
      responsable_negocio TEXT,
      decidido_en TEXT NOT NULL,
      solicitud_json TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_verification_review_log_date
      ON verification_review_log(decidido_en DESC, id DESC);
    CREATE INDEX IF NOT EXISTS idx_verification_review_log_user
      ON verification_review_log(usuario_id, id DESC);
  `);

  // SQLite no permite ampliar un CHECK con ALTER TABLE. Las instalaciones
  // que ya tenían el historial se reconstruyen dentro de una transacción,
  // conservando ids y decisiones. `solicitud_json` congela el expediente
  // exacto desde que el negocio lo envía; no lleva FK para que sus datos
  // sigan auditables aunque después cambie o desaparezca la cuenta.
  const tablaHistorial = db.prepare(
    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'verification_review_log'",
  ).get();
  if (tablaHistorial?.sql && !tablaHistorial.sql.includes("'restored'")) {
    const columnasHistorial = db
      .prepare("PRAGMA table_info('verification_review_log')")
      .all();
    const teniaSolicitudJson = columnasHistorial.some(
      columna => columna.name === 'solicitud_json',
    );
    db.transaction(() => {
      db.exec(`
        DROP INDEX IF EXISTS idx_verification_review_log_date;
        DROP INDEX IF EXISTS idx_verification_review_log_user;
        ALTER TABLE verification_review_log RENAME TO verification_review_log_anterior;
        CREATE TABLE verification_review_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          usuario_id TEXT NOT NULL,
          accion TEXT NOT NULL CHECK(accion IN ('approved','rejected','revoked','restored')),
          motivo TEXT,
          nombre_negocio TEXT NOT NULL,
          categoria_negocio TEXT,
          responsable_negocio TEXT,
          decidido_en TEXT NOT NULL,
          solicitud_json TEXT
        );
        INSERT INTO verification_review_log (
          id, usuario_id, accion, motivo, nombre_negocio, categoria_negocio,
          responsable_negocio, decidido_en, solicitud_json
        )
        SELECT id, usuario_id, accion, motivo, nombre_negocio,
          categoria_negocio, responsable_negocio, decidido_en,
          ${teniaSolicitudJson ? 'solicitud_json' : 'NULL'}
        FROM verification_review_log_anterior;
        DROP TABLE verification_review_log_anterior;
        CREATE INDEX idx_verification_review_log_date
          ON verification_review_log(decidido_en DESC, id DESC);
        CREATE INDEX idx_verification_review_log_user
          ON verification_review_log(usuario_id, id DESC);
      `);
    })();
  }

  const columnasHistorialActual = db
    .prepare("PRAGMA table_info('verification_review_log')")
    .all();
  if (!columnasHistorialActual.some(columna => columna.name === 'solicitud_json')) {
    db.exec('ALTER TABLE verification_review_log ADD COLUMN solicitud_json TEXT');
  }

  // Registra una instantánea del último estado conocido de cada negocio
  // anterior a esta migración. Así las cuentas ya verificadas aparecen en el
  // historial y pueden retirarse desde el panel desde el primer arranque.
  db.exec(`
    INSERT INTO verification_review_log (
      usuario_id, accion, motivo, nombre_negocio, categoria_negocio,
      responsable_negocio, decidido_en
    )
    SELECT
      v.usuario_id,
      CASE v.estado WHEN 'verificado' THEN 'approved' ELSE 'rejected' END,
      CASE WHEN v.estado = 'rechazado' THEN v.motivo_rechazo ELSE NULL END,
      COALESCE(NULLIF(s.name, ''), NULLIF(v.nombre_negocio, ''), v.usuario_id),
      s.businessCategory,
      v.responsable_negocio,
      COALESCE(v.fecha_verificacion, v.creado_en, datetime('now'))
    FROM verificaciones v
    JOIN sellers s ON s.id = v.usuario_id
    WHERE v.tipo_cuenta = 'negocio'
      AND v.responsable_negocio IS NOT NULL
      AND v.estado IN ('verificado', 'rechazado')
      AND NOT EXISTS (
        SELECT 1 FROM verification_review_log h
        WHERE h.usuario_id = v.usuario_id
      )
  `);

  // 47. Bitacora dedicada a los cambios de palomita desde el padron de
  // cuentas. No lleva FK para que la auditoria sobreviva si la cuenta se
  // elimina. request_id hace idempotente cada accion del panel: un reintento
  // de red no puede aplicar ni registrar dos veces el mismo cambio.
  db.exec(`
    CREATE TABLE IF NOT EXISTS verification_admin_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      request_id TEXT NOT NULL UNIQUE,
      usuario_id TEXT NOT NULL,
      account_name TEXT NOT NULL,
      account_type TEXT NOT NULL
        CHECK(account_type IN ('negocio','estudiante','empleado')),
      action TEXT NOT NULL CHECK(action IN ('verified','unverified')),
      previous_verified INTEGER NOT NULL CHECK(previous_verified IN (0,1)),
      new_verified INTEGER NOT NULL CHECK(new_verified IN (0,1)),
      reason TEXT NOT NULL CHECK(length(reason) BETWEEN 10 AND 500),
      actor TEXT NOT NULL,
      decided_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_verification_admin_log_user_date
      ON verification_admin_log(usuario_id, decided_at DESC, id DESC);
    CREATE INDEX IF NOT EXISTS idx_verification_admin_log_date
      ON verification_admin_log(decided_at DESC, id DESC);
    CREATE INDEX IF NOT EXISTS idx_sellers_verification_admin
      ON sellers(tipo_cuenta, verified, created_at DESC, id);
  `);

  // JWT revocados antes de su expiracion (logout, telefono perdido). Solo se
  // guarda el identificador aleatorio jti, nunca el token completo.
  db.exec(`
    CREATE TABLE IF NOT EXISTS revoked_sessions (
      jti TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      expires_at INTEGER NOT NULL,
      revoked_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_revoked_sessions_expiry ON revoked_sessions(expires_at);
    DELETE FROM revoked_sessions WHERE expires_at <= unixepoch();
  `);

  // Sesiones persistentes. El cliente conserva el secreto en Keychain /
  // Android Keystore y aquí solo vive su hash SHA-256. No tienen caducidad:
  // siguen vigentes hasta que el usuario cierre sesión o se revoquen.
  // El JWT de acceso sí caduca y se vuelve a emitir con esta credencial.
  db.exec(`
    CREATE TABLE IF NOT EXISTS refresh_sessions (
      token_hash TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_used_at TEXT NOT NULL DEFAULT (datetime('now')),
      revoked_at TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_refresh_sessions_user
      ON refresh_sessions(user_id, revoked_at);
  `);

  // 48. Moderacion administrativa de cuentas. Se migra con columnas
  // aditivas para conservar todas las cuentas y sesiones existentes.
  // auth_invalid_before usa epoch en milisegundos: el iat estandar de JWT
  // solo tiene precision de segundos y dejaria una ventana de reutilizacion
  // al suspender una cuenta en el mismo segundo en que obtuvo su token.
  const sellerColsModeration = db.prepare("PRAGMA table_info('sellers')").all();
  if (!sellerColsModeration.some(column => column.name === 'admin_status')) {
    db.exec(`
      ALTER TABLE sellers ADD COLUMN admin_status TEXT NOT NULL DEFAULT 'active'
        CHECK(admin_status IN ('active', 'suspended', 'banned'))
    `);
  }
  if (!sellerColsModeration.some(column => column.name === 'admin_status_reason')) {
    db.exec('ALTER TABLE sellers ADD COLUMN admin_status_reason TEXT');
  }
  if (!sellerColsModeration.some(column => column.name === 'admin_status_until')) {
    db.exec('ALTER TABLE sellers ADD COLUMN admin_status_until TEXT');
  }
  if (!sellerColsModeration.some(column => column.name === 'auth_invalid_before')) {
    db.exec(`
      ALTER TABLE sellers ADD COLUMN auth_invalid_before INTEGER NOT NULL DEFAULT 0
        CHECK(auth_invalid_before >= 0)
    `);
  }
  if (!sellerColsModeration.some(column => column.name === 'deleted_at')) {
    db.exec('ALTER TABLE sellers ADD COLUMN deleted_at TEXT');
  }
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_sellers_admin_status
      ON sellers(admin_status, admin_status_until, id)
  `);

  // 49. Identidades administrativas separadas de las cuentas del marketplace.
  // El secreto TOTP se cifra en la capa de autenticacion antes de persistirlo;
  // nunca se guarda el JWT ni la contrasena en texto plano. token_version
  // permite invalidar de inmediato todas las sesiones de un admin.
  db.exec(`
    CREATE TABLE IF NOT EXISTS admins (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL COLLATE NOCASE UNIQUE
        CHECK(length(username) BETWEEN 3 AND 64),
      password_hash TEXT NOT NULL,
      totp_secret_encrypted TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1)),
      token_version INTEGER NOT NULL DEFAULT 0,
      last_totp_step INTEGER,
      last_login_at TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_admins_active ON admins(active, id);

    CREATE TABLE IF NOT EXISTS admin_revoked_tokens (
      jti TEXT PRIMARY KEY,
      admin_id INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      revoked_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (admin_id) REFERENCES admins(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_admin_revoked_tokens_expiry
      ON admin_revoked_tokens(expires_at);
    DELETE FROM admin_revoked_tokens WHERE expires_at <= unixepoch();

    -- Bitacora transversal de acciones administrativas. A diferencia de los
    -- historiales de dominio, conserva la identidad autenticada que ejecuto
    -- cada cambio. No se hace backfill: solo registra acciones nuevas.
    CREATE TABLE IF NOT EXISTS admin_audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      admin_id INTEGER NOT NULL,
      action TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      details_json TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (admin_id) REFERENCES admins(id) ON DELETE RESTRICT
    );
    CREATE INDEX IF NOT EXISTS idx_admin_audit_log_admin_date
      ON admin_audit_log(admin_id, created_at DESC, id DESC);
    CREATE INDEX IF NOT EXISTS idx_admin_audit_log_entity_date
      ON admin_audit_log(entity_type, entity_id, created_at DESC, id DESC);
    CREATE INDEX IF NOT EXISTS idx_admin_audit_log_date
      ON admin_audit_log(created_at DESC, id DESC);

    -- Cinco niveles fijos de limites de publicacion. Los valores efectivos
    -- viven aqui; el codigo solo conserva sus defaults para seed/reset y para
    -- tests que deliberadamente no inicializan SQLite.
    CREATE TABLE IF NOT EXISTS config (
      key TEXT PRIMARY KEY CHECK(key IN (
        'negocio_verificado',
        'negocio_sin_verificar',
        'um_verificado',
        'um_sin_verificar',
        'externo'
      )),
      products_active INTEGER NOT NULL
        CHECK(products_active BETWEEN ${PUBLICATION_POLICY_RANGES.productsActive.min}
          AND ${PUBLICATION_POLICY_RANGES.productsActive.max}),
      products_daily INTEGER NOT NULL
        CHECK(products_daily BETWEEN ${PUBLICATION_POLICY_RANGES.productsDaily.min}
          AND ${PUBLICATION_POLICY_RANGES.productsDaily.max}),
      wanted_active INTEGER NOT NULL
        CHECK(wanted_active BETWEEN ${PUBLICATION_POLICY_RANGES.wantedActive.min}
          AND ${PUBLICATION_POLICY_RANGES.wantedActive.max}),
      wanted_daily INTEGER NOT NULL
        CHECK(wanted_daily BETWEEN ${PUBLICATION_POLICY_RANGES.wantedDaily.min}
          AND ${PUBLICATION_POLICY_RANGES.wantedDaily.max}),
      duration_days INTEGER NOT NULL
        CHECK(duration_days BETWEEN ${PUBLICATION_POLICY_RANGES.durationDays.min}
          AND ${PUBLICATION_POLICY_RANGES.durationDays.max}),
      updated_by_admin_id INTEGER,
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (updated_by_admin_id) REFERENCES admins(id) ON DELETE SET NULL
    );
  `);

  const insertDefaultConfig = db.prepare(
    `INSERT OR IGNORE INTO config (
       key, products_active, products_daily, wanted_active, wanted_daily,
       duration_days
     ) VALUES (?, ?, ?, ?, ?, ?)`,
  );
  db.transaction(entries => {
    for (const [key, policy] of entries) {
      insertDefaultConfig.run(
        key,
        policy.productsActive,
        policy.productsDaily,
        policy.wantedActive,
        policy.wantedDaily,
        policy.durationDays,
      );
    }
  })(Object.entries(DEFAULT_PUBLICATION_POLICIES));

  // 50. Moderacion no destructiva de publicaciones y cortes administrativos
  // de cupos diarios. Las filas moderadas permanecen como evidencia, pero
  // todas las lecturas publicas las excluyen.
  const productModerationCols = db.prepare("PRAGMA table_info('products')").all();
  if (!productModerationCols.some(column => column.name === 'moderation_status')) {
    db.exec(`ALTER TABLE products ADD COLUMN moderation_status TEXT NOT NULL DEFAULT 'visible'
      CHECK(moderation_status IN ('visible', 'removed', 'spam'))`);
  }
  if (!productModerationCols.some(column => column.name === 'moderation_reason')) {
    db.exec('ALTER TABLE products ADD COLUMN moderation_reason TEXT');
  }
  if (!productModerationCols.some(column => column.name === 'moderated_at')) {
    db.exec('ALTER TABLE products ADD COLUMN moderated_at TEXT');
  }
  if (!productModerationCols.some(column => column.name === 'moderated_by_admin_id')) {
    db.exec('ALTER TABLE products ADD COLUMN moderated_by_admin_id INTEGER REFERENCES admins(id)');
  }

  const wantedModerationCols = db.prepare("PRAGMA table_info('wanted_posts')").all();
  if (!wantedModerationCols.some(column => column.name === 'moderation_status')) {
    db.exec(`ALTER TABLE wanted_posts ADD COLUMN moderation_status TEXT NOT NULL DEFAULT 'visible'
      CHECK(moderation_status IN ('visible', 'removed', 'spam'))`);
  }
  if (!wantedModerationCols.some(column => column.name === 'moderation_reason')) {
    db.exec('ALTER TABLE wanted_posts ADD COLUMN moderation_reason TEXT');
  }
  if (!wantedModerationCols.some(column => column.name === 'moderated_at')) {
    db.exec('ALTER TABLE wanted_posts ADD COLUMN moderated_at TEXT');
  }
  if (!wantedModerationCols.some(column => column.name === 'moderated_by_admin_id')) {
    db.exec('ALTER TABLE wanted_posts ADD COLUMN moderated_by_admin_id INTEGER REFERENCES admins(id)');
  }

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_products_moderation_created
      ON products(moderation_status, created_at DESC, id DESC);
    CREATE INDEX IF NOT EXISTS idx_wanted_moderation_created
      ON wanted_posts(moderation_status, created_at DESC, id DESC);

    CREATE TABLE IF NOT EXISTS publication_limit_resets (
      user_id TEXT PRIMARY KEY,
      products_reset_at TEXT,
      wanted_reset_at TEXT,
      updated_by_admin_id INTEGER NOT NULL,
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (updated_by_admin_id) REFERENCES admins(id) ON DELETE RESTRICT
    );
  `);

  // Recoge estadisticas para que SQLite pueda elegir los indices nuevos desde
  // el primer arranque posterior al despliegue.
  db.pragma('optimize');

  console.log('🔄 Migración de schema completada');
}

// ─── Presencia ───────────────────────────────────────────────

/**
 * Marca cuándo se desconectó el usuario. Se llama una sola vez por sesión
 * (al cerrarse su último socket), no periódicamente.
 */
function setUltimaActividad(userId, iso) {
  getDb().prepare('UPDATE sellers SET last_active = ? WHERE id = ?').run(iso, userId);
}

/** Enciende o apaga "mostrar mi estado en línea" para el usuario. */
function setMostrarEstadoEnLinea(userId, comparte) {
  getDb()
    .prepare('UPDATE sellers SET show_online_status = ? WHERE id = ?')
    .run(comparte ? 1 : 0, userId);
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
function getPresencia(userId) {
  const fila = getDb()
    .prepare('SELECT last_active, show_online_status FROM sellers WHERE id = ?')
    .get(userId);
  if (!fila) return { lastActive: null, comparteEstado: false };
  return {
    lastActive: fila.last_active || null,
    comparteEstado: fila.show_online_status !== 0,
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
function purgarMetodoDePago(conexion, metodo) {
  const tocadas = { sellers: 0, products: 0, wanted: 0 };

  const purgarTabla = (tabla, columnaId, siQuedaVacio) => {
    const existe = conexion.prepare(
      `SELECT name FROM sqlite_master WHERE type='table' AND name=?`,
    ).get(tabla);
    if (!existe) return 0;

    const filas = conexion.prepare(
      `SELECT ${columnaId} AS id, paymentMethods FROM ${tabla}
       WHERE paymentMethods IS NOT NULL AND paymentMethods LIKE ?`,
    ).all(`%${metodo}%`);

    const actualizar = conexion.prepare(
      `UPDATE ${tabla} SET paymentMethods = ? WHERE ${columnaId} = ?`,
    );

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
      actualizar.run(valor, fila.id);
      n++;
    }
    return n;
  };

  conexion.transaction(() => {
    tocadas.sellers = purgarTabla('sellers', 'id', JSON.stringify(['efectivo']));
    tocadas.products = purgarTabla('products', 'id', null);
    tocadas.wanted = purgarTabla('wanted_posts', 'id', null);
  })();

  if (tocadas.sellers || tocadas.products || tocadas.wanted) {
    console.log(
      `🔄 Método de pago '${metodo}' retirado: ${tocadas.sellers} vendedores, `
      + `${tocadas.products} productos, ${tocadas.wanted} búsquedas`,
    );
  }
  return tocadas;
}

// ─── helpers para convertir filas a objetos y viceversa ─────

function rowToProduct(row) {
  if (!row) return null;
  const priceNum = row.priceNum !== null && row.priceNum !== undefined
    ? row.priceNum
    : parseFloat(String(row.price || '0').replace(/[^0-9.]/g, '')) || 0;

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
    atributos: parseAtributosCategoria(row.atributos_categoria),
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
  const priceNum = typeof product.price === 'number'
    ? product.price
    : parseFloat(String(product.price || '0').replace(/[^0-9.]/g, '')) || 0;

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
    atributos_categoria:
      product.atributos && Object.keys(product.atributos).length > 0
        ? JSON.stringify(product.atributos)
        : null,
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
    moderationStatus: row.moderation_status || 'visible',
  };
}

// ─── API de datos ──────────────────────────────────────────

function getCategories() {
  return db.prepare('SELECT * FROM categories ORDER BY id').all();
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
const CORREOS_DUENO = new Set([
  'cesar4herrera@gmail.com',
  '1220326@alumno.um.edu.mx',
  'cesar8herrera@gmail.com',
]);

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
function refrescarCuentasDueno() {
  const correos = [...CORREOS_DUENO];
  const marcadores = correos.map(() => '?').join(', ');
  const filas = db
    .prepare(
      `SELECT id FROM sellers WHERE lower(trim(email)) IN (${marcadores})
       UNION
       SELECT usuario_id AS id FROM verificaciones
        WHERE estado = 'verificado'
          AND lower(trim(correo_institucional)) IN (${marcadores})`,
    )
    .all(...correos, ...correos);
  _cuentasDuenoIds = new Set(filas.map(f => f.id));
  _cuentasDuenoAt = Date.now();
  return _cuentasDuenoIds;
}

/** Fuerza NULL como método de pago para las cuentas oficiales del dueño. */
function anularMetodosPagoCuentasDueno() {
  const ids = [...refrescarCuentasDueno()];
  if (ids.length === 0) return 0;
  const marcadores = ids.map(() => '?').join(', ');
  return db.prepare(
    `UPDATE sellers SET paymentMethods = NULL
     WHERE id IN (${marcadores}) AND paymentMethods IS NOT NULL`,
  ).run(...ids).changes;
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
    refrescarCuentasDueno();
  }
  return _cuentasDuenoIds.has(usuarioId);
}

function rowToSeller(row) {
  if (!row) return null;
  const todosLosBadges =
    esUsuarioTodosLosBadges(row.id) || esCuentaTodosLosBadges(row.email);
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
    profileViews: row.profile_views ?? 0,
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
    createdAt: row.created_at,
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
function getCuentasSoporte() {
  return CORREOS_SOPORTE.map(correo =>
    db.prepare('SELECT * FROM sellers WHERE lower(trim(email)) = ?').get(correo),
  )
    .filter(Boolean)
    .map(rowToSeller);
}

/**
 * ¿`userId` participa en `conversationId`?
 *
 * Es la comprobación que decide quién puede LEER una conversación, y por eso
 * vive aquí y no repetida en cada llamador: la usan la ruta REST de mensajes,
 * el borrado y la sala de Socket.IO, y si las tres divergieran bastaría con
 * que una se quedara corta para reabrir la fuga.
 */
function esParticipanteDeConversacion(conversationId, userId) {
  if (!conversationId || !userId) return false;
  const fila = db
    .prepare(
      'SELECT 1 FROM conversations WHERE id = ? AND (buyer_id = ? OR seller_id = ?)',
    )
    .get(conversationId, userId, userId);
  return !!fila;
}

function getSellers() {
  const rows = db.prepare('SELECT * FROM sellers ORDER BY id').all();
  return rows.map(rowToSeller);
}

function insertSeller(seller) {
  db.prepare(`
    INSERT OR IGNORE INTO sellers (id, name, avatarInitials, major, isBusiness, logoUrl, rating, reviews, verified, created_at)
    VALUES (@id, @name, @avatarInitials, @major, @isBusiness, @logoUrl, @rating, @reviews, @verified, datetime('now'))
  `).run({
    ...seller,
    isBusiness: seller.isBusiness ? 1 : 0,
    verified: seller.verified ? 1 : 0,
    rating: seller.rating ?? 0,
    reviews: seller.reviews ?? 0,
    logoUrl: seller.logoUrl || null,
  });
}

function getHighlightPlans() {
  return db.prepare(
    "SELECT * FROM highlight_plans ORDER BY " +
    "CASE id WHEN 'd1' THEN 1 WHEN 'd3' THEN 2 WHEN 'd7' THEN 3 WHEN 'm1' THEN 4 ELSE 5 END"
  ).all();
}

function getAllProducts() {
  const rows = db.prepare("SELECT * FROM products WHERE moderation_status = 'visible'").all();
  return rows.map(rowToProduct);
}

function getProductById(id) {
  const row = db.prepare(`SELECT * FROM products p
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

function isSellerPubliclyActive(userId) {
  return !!db.prepare(`SELECT 1 FROM sellers
    WHERE id = ? AND (
      admin_status = 'active'
      OR (admin_status = 'suspended' AND admin_status_until IS NOT NULL
        AND datetime(admin_status_until) <= datetime('now'))
    )`).get(userId);
}

function getPublicationLimitSince(userId, kind, fallbackIso) {
  if (!['products', 'wanted'].includes(kind)) return fallbackIso;
  const column = kind === 'products' ? 'products_reset_at' : 'wanted_reset_at';
  const row = db.prepare(`SELECT ${column} AS reset_at
    FROM publication_limit_resets WHERE user_id = ?`).get(userId);
  return row?.reset_at && row.reset_at > fallbackIso ? row.reset_at : fallbackIso;
}

function countProductsSince(userId, isoTimestamp) {
  return db.prepare(
    'SELECT COUNT(*) AS count FROM products WHERE seller = ? AND created_at >= ?',
  ).get(userId, isoTimestamp)?.count ?? 0;
}

function insertProduct(product) {
  const row = productToRow(product);
  // NUNCA usar INSERT OR REPLACE: en SQLite eso hace un DELETE + INSERT de la
  // fila existente, y con foreign_keys=ON eso dispara el ON DELETE CASCADE de
  // product_ratings (y cualquier otra tabla hija), borrando datos relacionados
  // cada vez que se guarda un producto ya existente. Un upsert real (ON
  // CONFLICT DO UPDATE) modifica la fila in place sin disparar cascadas.
  db.prepare(`
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

function updateProduct(id, updates) {
  const existing = getProductById(id);
  if (!existing) return null;
  const merged = { ...existing, ...updates };
  const row = productToRow(merged);
  db.prepare(`
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
  return getProductById(id);
}

function deleteProduct(id) {
  db.prepare('DELETE FROM products WHERE id = ?').run(id);
}

function incrementProductViews(id) {
  db.prepare('UPDATE products SET views = views + 3 WHERE id = ?').run(id);
}

/** Suma una apertura ajena al perfil, independiente de publicaciones. */
function incrementSellerProfileViews(id) {
  db.prepare('UPDATE sellers SET profile_views = profile_views + 1 WHERE id = ?').run(id);
}

// ─── Carrito ────────────────────────────────────────────────
//
// Todas las operaciones van acotadas por `userId`. Las firmas piden el
// usuario como primer argumento a propósito: así es imposible escribir por
// descuido una consulta de carrito que no filtre por dueño, que es
// exactamente el bug que tenía la versión anterior de estas funciones.

function getCartItems(userId) {
  return db.prepare('SELECT * FROM cart WHERE user_id = ?').all(userId);
}

function getCartItem(userId, id) {
  return db.prepare('SELECT * FROM cart WHERE id = ? AND user_id = ?').get(id, userId);
}

/** Agrega o suma cantidad si el producto ya está en el carrito del usuario. */
function upsertCartItem(userId, { id, productId, quantity, meetingPoint }) {
  const existing = db
    .prepare('SELECT * FROM cart WHERE user_id = ? AND productId = ?')
    .get(userId, productId);

  if (existing) {
    db.prepare(
      `UPDATE cart SET quantity = quantity + ?,
       meetingPoint = COALESCE(?, meetingPoint) WHERE id = ?`,
    ).run(quantity, meetingPoint || null, existing.id);
    return existing.id;
  }

  db.prepare(`
    INSERT INTO cart (id, user_id, productId, quantity, meetingPoint)
    VALUES (?, ?, ?, ?, ?)
  `).run(id, userId, productId, quantity, meetingPoint || 'Por definir');
  return id;
}

function updateCartItem(userId, id, { quantity, meetingPoint }) {
  const item = getCartItem(userId, id);
  if (!item) return false;
  db.prepare(
    `UPDATE cart SET quantity = COALESCE(?, quantity),
     meetingPoint = COALESCE(?, meetingPoint) WHERE id = ? AND user_id = ?`,
  ).run(quantity ?? null, meetingPoint ?? null, id, userId);
  return true;
}

function deleteCartItem(userId, id) {
  return db.prepare('DELETE FROM cart WHERE id = ? AND user_id = ?').run(id, userId).changes > 0;
}

function clearCartItems(userId, productIds) {
  if (!productIds || productIds.length === 0) return;
  const placeholders = productIds.map(() => '?').join(',');
  db.prepare(
    `DELETE FROM cart WHERE user_id = ? AND productId IN (${placeholders})`,
  ).run(userId, ...productIds);
}

function getAllListings() {
  return db.prepare('SELECT * FROM listings').all();
}

function addListing(listing) {
  db.prepare('INSERT INTO listings (id, productId) VALUES (?, ?)').run(listing.id, listing.productId);
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
function getHighestPriceInLastDays(productId, days = 30) {
  const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  const row = db.prepare(`
    SELECT MAX(price) as highest FROM price_history
    WHERE product_id = ? AND changed_at >= ?
  `).get(productId, cutoff);
  return row?.highest ?? null;
}

/**
 * Obtiene el precio más bajo registrado para un producto en los últimos [days] días,
 * considerando el precio actual y todo el historial.
 */
function getLowestPriceInLastDays(productId, currentPrice, days = 30) {
  const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  const row = db.prepare(`
    SELECT MIN(min_price) as lowest FROM (
      SELECT price as min_price FROM price_history
        WHERE product_id = ? AND changed_at >= ?
      UNION ALL
      SELECT ? as min_price
    )
  `).get(productId, cutoff, currentPrice ?? 0);

  const lowest = row?.lowest;
  return typeof lowest === 'number' && lowest > 0 ? lowest : (currentPrice ?? 0);
}

/**
 * Obtiene el cambio de precio más reciente para verificar el cooldown de 72h.
 */
function getLastPriceChange(productId) {
  return db.prepare(`
    SELECT * FROM price_history
    WHERE product_id = ?
    ORDER BY changed_at DESC
    LIMIT 1
  `).get(productId);
}

/**
 * Obtiene el listado de historial de precios de los últimos [days] días.
 */
function getPriceHistoryList(productId, days = 30) {
  const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  return db.prepare(`
    SELECT price, changed_at
    FROM price_history
    WHERE product_id = ? AND changed_at >= ?
    ORDER BY changed_at ASC
  `).all(productId, cutoff);
}

/**
 * Cuenta cuántas ediciones de precio hubo para un producto en la última hora.
 */
function countPriceEditsLastHour(productId) {
  const cutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const row = db.prepare(`
    SELECT COUNT(*) as count FROM price_history
    WHERE product_id = ? AND changed_at >= ?
  `).get(productId, cutoff);
  return row?.count ?? 0;
}

/**
 * Inserta un registro en price_history con el precio anterior.
 */
function insertPriceHistory(productId, price) {
  db.prepare(`
    INSERT INTO price_history (product_id, price, changed_at)
    VALUES (?, ?, datetime('now'))
  `).run(productId, price);
}

/**
 * Limpia ofertas expiradas (offerExpiresAt ya pasó o status = 'sold').
 * Se llama al iniciar y al editar precios.
 */
function expireStaleOffers() {
  const now = new Date().toISOString();
  db.prepare(`
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

function upsertProductRating(productId, userId, stars) {
  const existing = db.prepare(
    'SELECT * FROM product_ratings WHERE product_id = ? AND user_id = ?'
  ).get(productId, userId);

  if (existing) {
    db.prepare(`
      UPDATE product_ratings SET stars = ?, updated_at = datetime('now')
      WHERE product_id = ? AND user_id = ?
    `).run(stars, productId, userId);
  } else {
    db.prepare(`
      INSERT INTO product_ratings (product_id, user_id, stars, created_at, updated_at)
      VALUES (?, ?, ?, datetime('now'), datetime('now'))
    `).run(productId, userId, stars);
  }
}

function getProductRatingStats(productId) {
  const row = db.prepare(`
    SELECT
      COALESCE(AVG(CAST(stars AS REAL)), 0) as average,
      COUNT(*) as count
    FROM product_ratings
    WHERE product_id = ?
  `).get(productId);
  return { average: Math.round((row.average || 0) * 10) / 10, count: row.count || 0 };
}

function getUserProductRating(productId, userId) {
  const row = db.prepare(
    'SELECT stars FROM product_ratings WHERE product_id = ? AND user_id = ?'
  ).get(productId, userId);
  return row ? row.stars : null;
}

function getSellerRatingStats(sellerId) {
  const row = db.prepare(`
    SELECT
      COALESCE(AVG(CAST(pr.stars AS REAL)), 0) as average,
      COUNT(*) as count
    FROM product_ratings pr
    JOIN products p ON p.id = pr.product_id
    WHERE p.seller = ?
  `).get(sellerId);
  return {
    rating: Math.round((row.average || 0) * 10) / 10,
    reviews: row.count || 0,
  };
}

// `sellers.rating`/`sellers.reviews` son un caché denormalizado de la query de
// arriba. No es opcional mantenerlo: el scoring del feed lo lee dentro de SQL
// (`COALESCE(s.rating, 0)` en getRankedFeed), así que no basta con calcular el
// promedio al vuelo en las rutas. Estas dos funciones son el único camino por
// el que ese caché debe escribirse.

function syncSellerRating(sellerId) {
  const stats = getSellerRatingStats(sellerId);
  db.prepare('UPDATE sellers SET rating = ?, reviews = ? WHERE id = ?')
    .run(stats.rating, stats.reviews, sellerId);
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
function getResponseDeltasMinutes(sellerId) {
  const rows = db.prepare(`
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
  return ordenados.length % 2 === 1
    ? ordenados[medio]
    : (ordenados[medio - 1] + ordenados[medio]) / 2;
}

/// Recalcula y cachea la mediana de respuesta del vendedor. Devuelve los
/// minutos, o null si todavía no hay respuestas suficientes.
function syncSellerResponseTime(sellerId) {
  const deltas = getResponseDeltasMinutes(sellerId);
  const mediana = deltas.length >= MIN_RESPUESTAS_PARA_MEDIANA
    ? Math.round(medianOf(deltas))
    : null;
  db.prepare('UPDATE sellers SET median_response_minutes = ? WHERE id = ?')
    .run(mediana, sellerId);
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
function computeRachaPublicaciones(sellerId) {
  const ventanas = new Set(db.prepare(`
    SELECT DISTINCT
      CAST((julianday('now') - julianday(created_at)) / 7 AS INTEGER) AS ventana
    FROM products
    WHERE seller = ?
  `).all(sellerId).map(r => r.ventana));

  let racha = 0;
  while (ventanas.has(racha)) racha += 1;
  return racha;
}

// Ventas confirmadas de un vendedor: órdenes con status = 'paid', el único
// estado que significa que el cobro se completó (ver CHECK de la tabla
// orders). 'pending'/'cancelled'/'requires_other_method' no cuentan como
// venta, son intentos que no llegaron a buen puerto.
function countVentasConfirmadas(sellerId) {
  const row = db.prepare(
    `SELECT COUNT(*) AS n FROM orders WHERE vendor_id = ? AND status = 'paid'`,
  ).get(sellerId);
  return row ? row.n : 0;
}

/**
 * Qué insignias permanentes tiene registradas este vendedor.
 *
 * Devuelve un Set de claves del catálogo (`validation/insignias.js`), vacío
 * si no tiene ninguna. Es lo que hace que subir un umbral no le quite la
 * insignia a quien ya la había ganado con el umbral anterior.
 */
function getInsigniasOtorgadas(sellerId) {
  const filas = db.prepare(
    'SELECT clave FROM insignias_otorgadas WHERE seller_id = ?',
  ).all(sellerId);
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
function registrarInsigniaOtorgada(sellerId, clave) {
  db.prepare(
    'INSERT OR IGNORE INTO insignias_otorgadas (seller_id, clave) VALUES (?, ?)',
  ).run(sellerId, clave);
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
function sumarVentasConfirmadas(sellerId) {
  const row = db.prepare(
    `SELECT COALESCE(SUM(amount), 0) AS total
       FROM orders WHERE vendor_id = ? AND status = 'paid'`,
  ).get(sellerId);
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
function getEstadisticasCalificaciones(sellerId) {
  const row = db.prepare(`
    SELECT
      COUNT(*) AS total,
      COALESCE(SUM(CASE WHEN pr.stars = 5 THEN 1 ELSE 0 END), 0) AS cincos
    FROM product_ratings pr
    JOIN products p ON p.id = pr.product_id
    WHERE p.seller = ?
  `).get(sellerId);
  return { total: row ? row.total : 0, cincos: row ? row.cincos : 0 };
}

/**
 * Preguntas recibidas y respondidas, para la insignia "Siempre responde".
 *
 * Una sola consulta por `seller_id` (índice idx_product_questions_seller) en
 * vez de dos: el perfil ya hace varias agregaciones al vuelo y esta se pide
 * en cada visita.
 */
function getEstadisticasPreguntasVendedor(sellerId) {
  const row = db.prepare(`
    SELECT
      COUNT(*) AS total,
      COALESCE(SUM(CASE WHEN status = 'answered' THEN 1 ELSE 0 END), 0) AS respondidas
    FROM product_questions
    WHERE seller_id = ?
  `).get(sellerId);
  return { total: row ? row.total : 0, respondidas: row ? row.respondidas : 0 };
}

// Recalcula el caché de TODOS los vendedores desde product_ratings. Corre al
// arrancar: es lo que repara las filas que quedaron con valores inventados
// (semilla) o desactualizados por escrituras que solo tocaban memoria.
function recomputeAllSellerRatings() {
  const stmt = db.prepare(`
    UPDATE sellers SET
      rating = COALESCE((
        SELECT ROUND(AVG(CAST(pr.stars AS REAL)), 1)
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
  const info = stmt.run();
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
      socioFundador:
        esUsuarioTodosLosBadges(row.userId) || !!row.autorSocioFundador,
      tipoCuenta: row.autorTipoCuenta || 'particular',
      carrera: row.autorCarrera || null,
      tipoVerificacion: row.autorTipoVerificacion || null,
    },
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
function paginarComentarios(sqlBase, params, limite) {
  const filas = db.prepare(`${sqlBase} LIMIT ?`).all(...params, limite + 1);
  const hayMas = filas.length > limite;
  const pagina = hayMas ? filas.slice(0, limite) : filas;
  const ultima = pagina[pagina.length - 1];
  return {
    filas: pagina,
    // El cursor apunta a la última fila entregada.
    nextCursor: hayMas && ultima ? `${ultima.createdAtRaw}|${ultima.id}` : null,
  };
}

/** Parte un cursor `<created_at>|<id>` en sus dos componentes, o null. */
function parseCursorComentario(cursor) {
  if (typeof cursor !== 'string' || !cursor.includes('|')) return null;
  const separador = cursor.indexOf('|');
  const createdAt = cursor.slice(0, separador);
  const id = cursor.slice(separador + 1);
  if (!createdAt || !id) return null;
  return { createdAt, id };
}

/**
 * Hilo de comentarios de un producto, del más reciente al más antiguo.
 * Excluye los borrados lógicamente.
 */
function getProductComments(productId, { limit, cursor } = {}) {
  const limite = normalizarLimiteComentarios(limit);
  const desde = parseCursorComentario(cursor);

  const where = desde
    ? `WHERE c.product_id = ? AND c.deleted_at IS NULL
         AND (c.created_at < ? OR (c.created_at = ? AND c.id < ?))`
    : `WHERE c.product_id = ? AND c.deleted_at IS NULL`;
  const params = desde
    ? [productId, desde.createdAt, desde.createdAt, desde.id]
    : [productId];

  const { filas, nextCursor } = paginarComentarios(
    `${SELECT_COMENTARIO} ${where} ORDER BY c.created_at DESC, c.id DESC`,
    params,
    limite,
  );

  return { comments: filas.map(rowToProductComment), nextCursor };
}

/** Cuántos comentarios vivos tiene un producto (el contador del header). */
function countProductComments(productId) {
  const row = db.prepare(
    'SELECT COUNT(*) AS total FROM product_comments WHERE product_id = ? AND deleted_at IS NULL',
  ).get(productId);
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
function getCommentsReceivedBySeller(sellerId, { limit, cursor } = {}) {
  const limite = normalizarLimiteComentarios(limit);
  const desde = parseCursorComentario(cursor);

  const filtroCursor = desde
    ? `AND (c.created_at < ? OR (c.created_at = ? AND c.id < ?))`
    : '';
  const params = desde
    ? [sellerId, sellerId, desde.createdAt, desde.createdAt, desde.id]
    : [sellerId, sellerId];

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

  const { filas, nextCursor } = paginarComentarios(sql, params, limite);

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
        image: Array.isArray(fotos) && fotos.length > 0 ? fotos[0] : null,
      },
    };
  });

  return { comments, nextCursor };
}

/** Cuántos comentarios vivos recibió [sellerId] en sus publicaciones. */
function countCommentsReceivedBySeller(sellerId) {
  const row = db.prepare(`
    SELECT COUNT(*) AS total
    FROM product_comments c
    JOIN products p ON p.id = c.product_id AND p.seller = ?
    WHERE c.deleted_at IS NULL AND c.user_id != ?
  `).get(sellerId, sellerId);
  return row ? row.total : 0;
}

/** Fila cruda de un comentario (incluye los borrados). Para permisos. */
function getProductCommentRow(commentId) {
  return db.prepare('SELECT * FROM product_comments WHERE id = ?').get(commentId);
}

/** Comentario ya en forma de API, por id. Usado tras insertar. */
function getProductCommentById(commentId) {
  const fila = db.prepare(`${SELECT_COMENTARIO} WHERE c.id = ?`).get(commentId);
  return rowToProductComment(fila);
}

/** Inserta un comentario y devuelve su forma de API, autor incluido. */
function createProductComment(id, productId, userId, texto) {
  db.prepare(
    'INSERT INTO product_comments (id, product_id, user_id, texto) VALUES (?, ?, ?, ?)',
  ).run(id, productId, userId, texto);
  return getProductCommentById(id);
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
function segundosDesdeUltimoComentario(userId) {
  const row = db.prepare(`
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
function softDeleteProductComment(commentId, actorId) {
  const info = db.prepare(`
    UPDATE product_comments
    SET deleted_at = datetime('now'), deleted_by = ?
    WHERE id = ? AND deleted_at IS NULL
  `).run(actorId, commentId);
  return info.changes > 0;
}

// ─── Enigma escondido ───────────────────────────────────────────

/** Fila de `secret_solves` de un usuario, o undefined si no lo ha resuelto. */
function getResolucionEnigma(userId) {
  return db
    .prepare('SELECT user_id, posicion, solved_at FROM secret_solves WHERE user_id = ?')
    .get(userId);
}

/** Cuánta gente lo ha resuelto ya. */
function contarResolucionesEnigma() {
  return db.prepare('SELECT COUNT(*) AS c FROM secret_solves').get().c;
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
function registrarResolucionEnigma(userId) {
  // La transacción se arma aquí y no en una constante de módulo porque `db`
  // no existe hasta initDatabase(): envolverla al cargar el archivo
  // reventaría el require.
  return db.transaction(() => {
    const previa = getResolucionEnigma(userId);
    if (previa) {
      return { posicion: previa.posicion, solvedAt: previa.solved_at, repetida: true };
    }

    const posicion = contarResolucionesEnigma() + 1;
    db.prepare('INSERT INTO secret_solves (user_id, posicion) VALUES (?, ?)').run(
      userId,
      posicion,
    );
    return { posicion, solvedAt: getResolucionEnigma(userId).solved_at, repetida: false };
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
      socioFundador:
        esUsuarioTodosLosBadges(row.askedBy) || !!row.autorSocioFundador,
      tipoCuenta: row.autorTipoCuenta || 'particular',
      carrera: row.autorCarrera || null,
      tipoVerificacion: row.autorTipoVerificacion || null,
    },
  };
}

function normalizarLimitePreguntas(limite) {
  const n = parseInt(limite, 10);
  if (!Number.isFinite(n) || n < 1) return PREGUNTAS_POR_PAGINA;
  return Math.min(n, PREGUNTAS_MAX_POR_PAGINA);
}

function getProductQuestionById(id) {
  return rowToProductQuestion(
    db.prepare(`${SELECT_PREGUNTA} WHERE q.id = ?`).get(id),
  );
}

/** Fila cruda, para las validaciones de permiso de la ruta (seller_id). */
function getProductQuestionRow(id) {
  return db.prepare('SELECT * FROM product_questions WHERE id = ?').get(id);
}

function createProductQuestion(id, productId, sellerId, askedBy, texto) {
  db.prepare(`
    INSERT INTO product_questions (id, product_id, seller_id, asked_by, question_text)
    VALUES (?, ?, ?, ?, ?)
  `).run(id, productId, sellerId, askedBy, texto);
  return getProductQuestionById(id);
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
function answerProductQuestion(id, texto) {
  db.prepare(`
    UPDATE product_questions
    SET answer_text = ?, status = 'answered', answered_at = datetime('now')
    WHERE id = ?
  `).run(texto, id);
  return getProductQuestionById(id);
}

/**
 * Elimina una pregunta completa del hilo.
 *
 * A diferencia de comentarios, las preguntas no tienen columna de borrado
 * lógico ni se muestran como prueba social en otro perfil. Si se borra una
 * pregunta, desaparece junto con su respuesta y los contadores se recalculan
 * sobre las filas vivas.
 */
function deleteProductQuestion(id) {
  const result = db.prepare('DELETE FROM product_questions WHERE id = ?').run(id);
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
function getProductQuestions(productId, { limit, cursor, filter } = {}) {
  const limite = normalizarLimitePreguntas(limit);
  const desde = parseCursorComentario(cursor);

  const condiciones = ['q.product_id = ?'];
  const params = [productId];

  if (filter === 'pending') condiciones.push("q.status = 'pending'");
  if (desde) {
    condiciones.push('(q.created_at < ? OR (q.created_at = ? AND q.id < ?))');
    params.push(desde.createdAt, desde.createdAt, desde.id);
  }

  const { filas, nextCursor } = paginarComentarios(
    `${SELECT_PREGUNTA} WHERE ${condiciones.join(' AND ')}
     ORDER BY q.created_at DESC, q.id DESC`,
    params,
    limite,
  );

  return { questions: filas.map(rowToProductQuestion), nextCursor };
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
function getProductQuestionsPreview(productId, { limit = PREGUNTAS_PREVIEW } = {}) {
  const filas = db.prepare(`
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
function countProductQuestions(productId) {
  const row = db.prepare(
    'SELECT COUNT(*) AS total FROM product_questions WHERE product_id = ?',
  ).get(productId);
  return row ? row.total : 0;
}

/** Cuántas están sin responder — el chip del dueño. */
function countPendingProductQuestions(productId) {
  const row = db.prepare(
    "SELECT COUNT(*) AS total FROM product_questions WHERE product_id = ? AND status = 'pending'",
  ).get(productId);
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
function segundosDesdeUltimaPregunta(userId) {
  const row = db.prepare(`
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
function contarPreguntasRecientes(userId, productId, horas) {
  const row = db.prepare(`
    SELECT COUNT(*) AS total FROM product_questions
    WHERE asked_by = ? AND product_id = ?
      AND created_at >= datetime('now', '-' || ? || ' hours')
  `).get(userId, productId, horas);
  return row ? row.total : 0;
}

// ─── Category Interests ─────────────────────────────────────────

function addCategoryInterest(userId, categoryId) {
  db.prepare(
    'INSERT OR IGNORE INTO category_interests (user_id, category_id) VALUES (?, ?)'
  ).run(userId, categoryId);
}

function removeCategoryInterest(userId, categoryId) {
  db.prepare(
    'DELETE FROM category_interests WHERE user_id = ? AND category_id = ?'
  ).run(userId, categoryId);
}

function getCategoryInterests(userId) {
  return db.prepare(
    'SELECT category_id FROM category_interests WHERE user_id = ?'
  ).all(userId).map(r => r.category_id);
}

function getUsersInterestedInCategory(categoryId) {
  return db.prepare(
    'SELECT user_id FROM category_interests WHERE category_id = ?'
  ).all(categoryId).map(r => r.user_id);
}

// ─── Notifications ──────────────────────────────────────────────

function createNotification(id, userId, type, title, body, data) {
  db.prepare(`
    INSERT INTO notifications (id, user_id, type, title, body, data, read, created_at)
    VALUES (?, ?, ?, ?, ?, ?, 0, datetime('now'))
  `).run(id, userId, type, title, body, JSON.stringify(data || {}));
}

function getNotifications(userId) {
  return db.prepare(
    'SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 50'
  ).all(userId).map(row => ({
    id: row.id,
    userId: row.user_id,
    type: row.type,
    title: row.title,
    body: row.body,
    data: JSON.parse(row.data || '{}'),
    read: !!row.read,
    createdAt: row.created_at,
  }));
}

function markNotificationRead(notificationId, userId) {
  return db.prepare('UPDATE notifications SET read = 1 WHERE id = ? AND user_id = ?')
    .run(notificationId, userId).changes > 0;
}

function markAllNotificationsRead(userId) {
  db.prepare('UPDATE notifications SET read = 1 WHERE user_id = ? AND read = 0').run(userId);
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
function markNotificationsReadForConversation(userId, conversationId) {
  const info = db.prepare(`
    UPDATE notifications SET read = 1
    WHERE user_id = ?
      AND read = 0
      AND json_extract(data, '$.conversationId') = ?
  `).run(userId, conversationId);
  return info.changes;
}

function getUnreadNotificationCount(userId) {
  const row = db.prepare(
    'SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND read = 0'
  ).get(userId);
  return row?.count ?? 0;
}

// ─── Conversations ──────────────────────────────────────────────

function createConversation(id, productId, buyerId, sellerId) {
  db.prepare(`
    INSERT INTO conversations (id, product_id, buyer_id, seller_id, created_at, last_message_at, last_message_preview)
    VALUES (?, ?, ?, ?, datetime('now'), datetime('now'), '')
  `).run(id, productId, buyerId, sellerId);
}

function findConversation(productId, buyerId, sellerId) {
  return db.prepare(
    'SELECT * FROM conversations WHERE product_id = ? AND buyer_id = ? AND seller_id = ?'
  ).get(productId, buyerId, sellerId);
}

/** Chat directo entre dos personas, sin producto ni "se busca" de por medio:
 *  el que abre el botón "Contactar por chat" del perfil público. */
function createDirectConversation(id, buyerId, sellerId) {
  db.prepare(`
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
function findDirectConversation(unoId, otroId) {
  return db.prepare(`
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
function getChatRelationship(ownerId, targetId) {
  if (!ownerId || !targetId || ownerId === targetId) {
    return {
      blockedByMe: false,
      blockedMe: false,
      mutedByMe: false,
      accepted: true,
      awaitingReply: false,
      firstContactLimit: MENSAJES_PRIMER_CONTACTO,
      remainingMessages: null,
      canSend: ownerId === targetId ? false : true,
    };
  }

  const mine = db.prepare(`
    SELECT blocked, muted FROM chat_user_settings
    WHERE owner_id = ? AND target_id = ?
  `).get(ownerId, targetId);
  const theirs = db.prepare(`
    SELECT blocked FROM chat_user_settings
    WHERE owner_id = ? AND target_id = ?
  `).get(targetId, ownerId);

  const counts = db.prepare(`
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
  const remainingMessages = accepted
    ? null
    : Math.max(0, MENSAJES_PRIMER_CONTACTO - sentByMe);
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
    canSend: !blocked && (accepted || sentByMe < MENSAJES_PRIMER_CONTACTO),
  };
}

function setChatUserSetting(ownerId, targetId, setting, enabled) {
  if (!ownerId || !targetId || ownerId === targetId) return false;
  if (setting !== 'blocked' && setting !== 'muted') return false;
  db.prepare(`
    INSERT INTO chat_user_settings (owner_id, target_id, ${setting}, updated_at)
    VALUES (?, ?, ?, datetime('now'))
    ON CONFLICT(owner_id, target_id) DO UPDATE SET
      ${setting} = excluded.${setting},
      updated_at = excluded.updated_at
  `).run(ownerId, targetId, enabled ? 1 : 0);
  return true;
}

function areUsersBlocked(oneId, otherId) {
  if (!oneId || !otherId) return false;
  const row = db.prepare(`
    SELECT 1 FROM chat_user_settings
    WHERE ((owner_id = ? AND target_id = ?)
        OR (owner_id = ? AND target_id = ?))
      AND blocked = 1
    LIMIT 1
  `).get(oneId, otherId, otherId, oneId);
  return !!row;
}

function isChatUserMuted(ownerId, targetId) {
  const row = db.prepare(`
    SELECT muted FROM chat_user_settings
    WHERE owner_id = ? AND target_id = ?
  `).get(ownerId, targetId);
  return !!row?.muted;
}

function getChatSafetySettings(ownerId) {
  if (!ownerId) return [];
  return db.prepare(`
    SELECT s.target_id AS userId, s.blocked, s.muted, s.updated_at AS updatedAt,
           COALESCE(u.name, s.target_id) AS name,
           u.avatarInitials, u.logoUrl, u.verified, u.isBusiness,
           u.socio_fundador AS socioFundador
      FROM chat_user_settings s
      LEFT JOIN sellers u ON u.id = s.target_id
     WHERE s.owner_id = ? AND (s.blocked = 1 OR s.muted = 1)
     ORDER BY s.updated_at DESC, s.target_id ASC
  `).all(ownerId).map(row => ({
    userId: row.userId,
    name: row.name,
    avatarInitials: row.avatarInitials || '',
    logoUrl: row.logoUrl || null,
    verified: !!row.verified,
    isBusiness: !!row.isBusiness,
    socioFundador: !!row.socioFundador,
    blocked: !!row.blocked,
    muted: !!row.muted,
    updatedAt: row.updatedAt,
  }));
}

const REPORT_TARGET_TYPES = new Set(['user', 'product', 'wanted', 'chat']);
const REPORT_STATUSES = new Set(['received', 'reviewing', 'resolved', 'dismissed']);

function createReport({ reporterId, targetType, targetId, targetUserId = null, reason, details = '' }) {
  if (!REPORT_TARGET_TYPES.has(targetType)) throw new Error('Tipo de reporte invalido.');
  const safeReason = String(reason || '').trim();
  const safeDetails = String(details || '').trim();
  if (safeReason.length < 3 || safeReason.length > 120) throw new Error('Motivo invalido.');
  if (!targetId || String(targetId).length > 180) throw new Error('Objetivo invalido.');
  if (safeDetails.length > 1000) throw new Error('Detalle invalido.');
  const id = `rep_${Date.now()}_${crypto.randomBytes(6).toString('hex')}`;
  db.prepare(`
    INSERT INTO reports (
      id, reporter_id, target_type, target_id, target_user_id, reason, details,
      status, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 'received', datetime('now'), datetime('now'))
  `).run(id, reporterId, targetType, String(targetId), targetUserId || null, safeReason, safeDetails);
  return getReportById(id);
}

function getReportById(id) {
  return db.prepare(`
    SELECT r.*, reporter.name AS reporterName, target.name AS targetUserName
      FROM reports r
      LEFT JOIN sellers reporter ON reporter.id = r.reporter_id
      LEFT JOIN sellers target ON target.id = r.target_user_id
     WHERE r.id = ?
  `).get(id);
}

function listReports({ status = 'all', targetType = 'all', limit = 50, offset = 0 } = {}) {
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
  const total = db.prepare(`SELECT COUNT(*) AS total FROM reports r ${clause}`).get(...params).total;
  const reports = db.prepare(`
    SELECT r.*, reporter.name AS reporterName, target.name AS targetUserName
      FROM reports r
      LEFT JOIN sellers reporter ON reporter.id = r.reporter_id
      LEFT JOIN sellers target ON target.id = r.target_user_id
      ${clause}
     ORDER BY r.created_at DESC, r.id DESC
     LIMIT ? OFFSET ?
  `).all(...params, limit, offset);
  return { reports, total };
}

function updateReportStatus({ id, status, adminNote = '', adminId }) {
  if (!REPORT_STATUSES.has(status)) return null;
  const before = getReportById(id);
  if (!before) return null;
  const resolved = status === 'resolved' || status === 'dismissed';
  db.prepare(`
    UPDATE reports
       SET status = ?, admin_note = ?, updated_at = datetime('now'),
           resolved_at = CASE WHEN ? THEN datetime('now') ELSE NULL END,
           resolved_by_admin_id = CASE WHEN ? THEN ? ELSE NULL END
     WHERE id = ?
  `).run(status, String(adminNote || '').trim().slice(0, 1000), resolved ? 1 : 0, resolved ? 1 : 0, adminId, id);
  return { before, after: getReportById(id) };
}

function anonymizeSellerAccount(userId) {
  const seller = db.prepare('SELECT * FROM sellers WHERE id = ?').get(userId);
  if (!seller) return null;
  const now = new Date().toISOString();
  db.transaction(() => {
    db.prepare('DELETE FROM push_tokens WHERE user_id = ?').run(userId);
    db.prepare('UPDATE refresh_sessions SET revoked_at = datetime(\'now\') WHERE user_id = ? AND revoked_at IS NULL').run(userId);
    db.prepare('DELETE FROM category_interests WHERE user_id = ?').run(userId);
    db.prepare('DELETE FROM chat_user_settings WHERE owner_id = ? OR target_id = ?').run(userId, userId);
    db.prepare('DELETE FROM verification_documents WHERE usuario_id = ?').run(userId);
    db.prepare('DELETE FROM verificaciones WHERE usuario_id = ?').run(userId);
    db.prepare("UPDATE products SET manual_status = 'paused', moderation_status = 'removed', moderation_reason = 'Cuenta eliminada por el usuario', updated_at = datetime('now') WHERE seller = ?").run(userId);
    db.prepare("UPDATE wanted_posts SET status = 'cerrada', moderation_status = 'removed', moderation_reason = 'Cuenta eliminada por el usuario' WHERE user_id = ?").run(userId);
    db.prepare(`
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
  return { id: userId, deletedAt: now };
}

function getConversationsForUser(userId) {
  return db.prepare(`
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
  `).all(userId, userId, userId).map(row => ({
    id: row.id,
    productId: row.product_id,
    wantedPostId: row.wanted_post_id,
    buyerId: row.buyer_id,
    sellerId: row.seller_id,
    createdAt: row.created_at,
    lastMessageAt: row.last_message_at,
    lastMessagePreview: row.last_message_preview || '',
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
function deleteConversationForUser(conversationId, userId) {
  const conversation = db.prepare(`
    SELECT id FROM conversations
    WHERE id = ? AND (buyer_id = ? OR seller_id = ?)
  `).get(conversationId, userId, userId);
  if (!conversation) return false;

  db.transaction(() => {
    const ultimo = db.prepare(`
      SELECT id FROM messages
      WHERE conversation_id = ?
      ORDER BY rowid DESC
      LIMIT 1
    `).get(conversationId);

    db.prepare(`
      INSERT INTO conversation_deletions
        (conversation_id, user_id, deleted_through_message_id, deleted_at)
      VALUES (?, ?, ?, datetime('now'))
      ON CONFLICT(conversation_id, user_id) DO UPDATE SET
        deleted_through_message_id = excluded.deleted_through_message_id,
        deleted_at = excluded.deleted_at
    `).run(conversationId, userId, ultimo?.id ?? null);

    db.prepare(`
      UPDATE messages SET read = 1
      WHERE conversation_id = ? AND sender_id != ? AND read = 0
    `).run(conversationId, userId);

    markNotificationsReadForConversation(userId, conversationId);
  })();

  return true;
}

function updateConversationPreview(conversationId, previewText) {
  db.prepare(`
    UPDATE conversations SET last_message_at = datetime('now'), last_message_preview = ? WHERE id = ?
  `).run(previewText, conversationId);
}

function getUnreadMessageCount(userId) {
  const row = db.prepare(`
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

function createWantedPost(post) {
  db.prepare(`
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
    expires_at: post.expiresAt || null,
  });
  return getWantedPostById(post.id);
}

function getWantedPostById(id) {
  const row = db.prepare(`SELECT * FROM wanted_posts w
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

function listWantedPosts({ categoryId, status, type } = {}) {
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
  return db.prepare(query).all(...params).map(rowToWantedPost);
}

function incrementWantedPostViews(id) {
  db.prepare('UPDATE wanted_posts SET views = views + 1 WHERE id = ?').run(id);
}

/**
 * Edita una publicación "se busca" existente. Solo actualiza los campos
 * de contenido (title/description/categoryId/type/priceMin/priceMax);
 * no toca user_id, status, resolved_with_user_id, created_at ni resolved_at.
 */
function updateWantedPost(id, updates) {
  db.prepare(`
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
    paymentMethods: updates.paymentMethods ? JSON.stringify(updates.paymentMethods) : null,
  });
  return getWantedPostById(id);
}

function resolveWantedPost(id, resolvedWithUserId) {
  db.prepare(`
    UPDATE wanted_posts SET status = 'resuelta', resolved_with_user_id = ?, resolved_at = datetime('now')
    WHERE id = ?
  `).run(resolvedWithUserId || null, id);
  return getWantedPostById(id);
}

function countWantedPostsSince(userId, isoTimestamp) {
  const row = db.prepare(
    'SELECT COUNT(*) as count FROM wanted_posts WHERE user_id = ? AND created_at >= ?'
  ).get(userId, isoTimestamp);
  return row?.count ?? 0;
}

function countActiveWantedPosts(userId) {
  return db.prepare(`SELECT COUNT(*) AS count FROM wanted_posts
    WHERE user_id = ? AND status = 'abierta'
      AND moderation_status = 'visible'
      AND (expires_at IS NULL OR datetime(expires_at) > datetime('now'))`).get(userId)?.count ?? 0;
}

function createWantedConversation(id, wantedPostId, buyerId, sellerId) {
  db.prepare(`
    INSERT INTO conversations (id, product_id, wanted_post_id, buyer_id, seller_id, created_at, last_message_at, last_message_preview)
    VALUES (?, NULL, ?, ?, ?, datetime('now'), datetime('now'), '')
  `).run(id, wantedPostId, buyerId, sellerId);
}

function findWantedConversation(wantedPostId, buyerId, sellerId) {
  return db.prepare(
    'SELECT * FROM conversations WHERE wanted_post_id = ? AND buyer_id = ? AND seller_id = ?'
  ).get(wantedPostId, buyerId, sellerId);
}

// ─── Push Tokens (FCM) ────────────────────────────────────────────

function registerPushToken(userId, playerId, platform) {
  db.prepare(`
    INSERT OR IGNORE INTO push_tokens (user_id, player_id, platform, created_at)
    VALUES (?, ?, ?, datetime('now'))
  `).run(userId, playerId, platform || 'unknown');
}

function unregisterPushToken(userId, playerId) {
  db.prepare(
    'DELETE FROM push_tokens WHERE user_id = ? AND player_id = ?'
  ).run(userId, playerId);
}

function getPushTokensForUser(userId) {
  return db.prepare(
    'SELECT player_id FROM push_tokens WHERE user_id = ?'
  ).all(userId).map(r => r.player_id);
}

function unregisterAllPushTokensForUser(userId) {
  db.prepare('DELETE FROM push_tokens WHERE user_id = ?').run(userId);
}

// ─── Messages ───────────────────────────────────────────────────

function createMessage(id, conversationId, senderId, text, imageUrl = null, replyToMessageId = null) {
  db.prepare(`
    INSERT INTO messages (id, conversation_id, sender_id, text, image_url, reply_to_message_id, created_at, read)
    VALUES (?, ?, ?, ?, ?, ?, datetime('now'), 0)
  `).run(id, conversationId, senderId, text, imageUrl, replyToMessageId);
  updateConversationPreview(conversationId, imageUrl ? '📷 Foto' : text);

  // El recálculo va aquí y no en la ruta para que valga también para los
  // mensajes con imagen y para cualquier call site futuro. Solo corre cuando
  // quien escribe es el vendedor: un mensaje del comprador abre una espera,
  // no la cierra, y no puede cambiar la mediana.
  const conv = db.prepare('SELECT seller_id FROM conversations WHERE id = ?').get(conversationId);
  if (conv && conv.seller_id === senderId) {
    syncSellerResponseTime(senderId);
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
    replyTo: replyTo !== undefined
      ? replyTo
      : (row.reply_id
        ? {
            id: row.reply_id,
            senderId: row.reply_sender_id,
            text: row.reply_text,
            imageUrl: row.reply_image_url || null,
          }
        : null),
  };
}

function getMessages(conversationId, userId = null) {
  const deletion = userId
    ? db.prepare(`
        SELECT deleted_through_message_id FROM conversation_deletions
        WHERE conversation_id = ? AND user_id = ?
      `).get(conversationId, userId)
    : null;
  const deletedThroughRowid = deletion?.deleted_through_message_id
    ? db.prepare('SELECT rowid FROM messages WHERE id = ?')
        .get(deletion.deleted_through_message_id)?.rowid ?? 0
    : 0;

  // LEFT JOIN y no una consulta por mensaje: un chat de 200 mensajes con
  // respuestas haría 200 SELECT extra.
  return db.prepare(`
    SELECT m.*,
           r.id         AS reply_id,
           r.sender_id  AS reply_sender_id,
           r.text       AS reply_text,
           r.image_url  AS reply_image_url
    FROM messages m
    LEFT JOIN messages r ON r.id = m.reply_to_message_id
    WHERE m.conversation_id = ? AND m.rowid > ?
    ORDER BY m.created_at ASC
  `).all(conversationId, deletedThroughRowid).map(row => rowToMessage(row));
}

/** Devuelve el resumen del mensaje citado, o null si no existe. */
function getRepliedMessage(messageId) {
  if (!messageId) return null;
  const row = db.prepare(
    'SELECT id, sender_id, text, image_url FROM messages WHERE id = ?'
  ).get(messageId);
  if (!row) return null;
  return {
    id: row.id,
    senderId: row.sender_id,
    text: row.text,
    imageUrl: row.image_url || null,
  };
}

/** ¿Este mensaje existe y pertenece a esta conversación?
 *
 *  Sirve para rechazar una respuesta que cite un mensaje de otro chat: sin
 *  esta comprobación, un cliente podría filtrar el texto de una conversación
 *  ajena haciendo que se pinte como cita dentro de la suya. */
function messageBelongsToConversation(messageId, conversationId) {
  const row = db.prepare(
    'SELECT 1 AS ok FROM messages WHERE id = ? AND conversation_id = ?'
  ).get(messageId, conversationId);
  return !!row;
}

function markConversationMessagesRead(conversationId, userId) {
  db.prepare(`
    UPDATE messages SET read = 1
    WHERE conversation_id = ? AND sender_id != ? AND read = 0
  `).run(conversationId, userId);
}

/** Soft-delete: reemplaza el texto del mensaje por un placeholder.
 *  Solo el sender puede borrar su propio mensaje.
 *  Retorna true si se eliminó, false si no existía. */
function deleteMessage(messageId, userId) {
  const msg = db.prepare('SELECT * FROM messages WHERE id = ?').get(messageId);
  if (!msg) return false;
  if (msg.sender_id !== userId) return false; // solo el dueño
  db.prepare("UPDATE messages SET text = '[Mensaje eliminado]', image_url = NULL WHERE id = ?").run(messageId);
  return true;
}

// ─── Feed Ranking ───────────────────────────────────────────────

// Pesos y parámetros de la fórmula de score. Viven aquí (no en el SQL crudo
// de las rutas) para que ajustar el ranking no implique tocar la consulta.
const FEED_WEIGHTS = {
  RECENCY_BASE: 100,           // puntos iniciales de un producto recién publicado
  RECENCY_DECAY_PER_DAY: 2,    // puntos que pierde por cada día de antigüedad
  W_VIEWS: 0.5,                // peso por vista
  W_FAVORITOS: 3,              // peso por guardado en favoritos
  W_CONTACTOS: 6,              // peso por mensaje enviado al vendedor
  W_ENGAGEMENT: 25,            // peso de (contactos/vistas), calidad del interés
  W_SELLER_RATING: 15,         // bonus máximo por rating de vendedor (5 estrellas)
  W_SELLER_PHOTO: 5,           // bonus por tener foto/logo de perfil
  W_SELLER_FAST_REPLY: 8,      // bonus por responder rápido
  FAST_REPLY_MAX_MINUTES: 60,  // umbral para considerar "responde rápido"
  INSTANT_REPLY_MAX_MINUTES: 10, // umbral, más estricto, para "respuesta instantánea"
  TOP_RATED_MIN_RATING: 4.5,   // rating mínimo para "vendedor confiable"
  TOP_RATED_MIN_REVIEWS: 10,   // reseñas mínimas para que el rating anterior cuente
  NOVATO_MAX_DIAS: 60,         // ventana desde el alta en la que la insignia de Novato puede mostrarse
  // ── Insignias élite ────────────────────────────────────────────
  // Umbrales pensados para que casi nadie las tenga: son el techo del
  // sistema, no un escalón más. Si con el tiempo se vuelven comunes, lo que
  // hay que subir es el número, no añadir otra insignia encima.
  LEYENDA_MIN_VENTAS: 100,       // ventas confirmadas para "Leyenda del Mercadito"
  ORO_MIN_FACTURADO: 100000,     // MXN facturados (órdenes pagadas) para "Vendedor de oro"
  IMPECABLE_MIN_RESENAS: 50,     // reseñas mínimas para que un 5.0 perfecto cuente
  CENTENARIO_MIN_CINCOS: 100,    // calificaciones de 5 estrellas para "Centenario"
  SIEMPRE_RESPONDE_MIN_PREGUNTAS: 20,  // preguntas recibidas mínimas para que la tasa signifique algo
  SIEMPRE_RESPONDE_MIN_TASA: 0.95,     // proporción de preguntas respondidas
  AFFINITY_MULTIPLIER: 1.3,    // multiplicador si la categoría es top-3 del device/usuario
  NO_STOCK_PENALTY_FACTOR: 0.01, // castigo drástico si no hay stock/está vendido
  POPULARITY_WINDOW_DAYS: 180, // ventana de interacciones que cuentan para popularidad
  AFFINITY_WINDOW_DAYS: 90,    // ventana de interacciones que cuentan para afinidad
  AFFINITY_TOP_N: 3,           // top-N categorías más vistas por device/usuario
  INTERACTION_RETENTION_DAYS: 180, // política de limpieza: no guardar más de X días
  INTERACTION_MAX_PER_DEVICE: 500, // ...ni más de N filas por device_id
};

/**
 * Registra una interacción (vista/favorito/contacto) de un device_id
 * (siempre) y, si hay sesión, también del user_id. No requiere cuenta.
 */
function registrarInteraccion({ deviceId, userId, productId, category, tipo }) {
  db.prepare(`
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
function linkDeviceToUser(deviceId, userId) {
  if (!deviceId || !userId) return;
  db.prepare(`
    UPDATE interacciones_dispositivo SET user_id = ? WHERE device_id = ? AND user_id IS NULL
  `).run(userId, deviceId);
}

/**
 * Poda interacciones_dispositivo para no acumular indefinidamente:
 * borra lo más viejo que INTERACTION_RETENTION_DAYS y, por device_id,
 * conserva solo las INTERACTION_MAX_PER_DEVICE filas más recientes.
 * Pensado para llamarse periódicamente (cron/arranque), no en cada request.
 */
function limpiarInteraccionesAntiguas({
  retentionDays = FEED_WEIGHTS.INTERACTION_RETENTION_DAYS,
  maxPerDevice = FEED_WEIGHTS.INTERACTION_MAX_PER_DEVICE,
} = {}) {
  db.prepare(`
    DELETE FROM interacciones_dispositivo
    WHERE created_at < datetime('now', '-' || ? || ' days')
  `).run(retentionDays);

  db.prepare(`
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
function getFeedRanked({ deviceId, userId, limit = 60, offset = 0 }) {
  const w = FEED_WEIGHTS;
  const rows = db.prepare(`
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
          + @wViews * COALESCE(ps.vistas, 0)
          + @wFavoritos * COALESCE(ps.favoritos, 0)
          + @wContactos * COALESCE(ps.contactos, 0)
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
    noStockPenaltyFactor: w.NO_STOCK_PENALTY_FACTOR,
  });

  return rows.map(row => ({
    ...rowToProduct(row),
    vistas: row.vistas,
    favoritos: row.favoritos,
    contactos: row.contactos,
    esCategoriaAfin: !!row.es_categoria_afin,
    score: row.score,
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
  + @wViews * COALESCE(ps.vistas, 0)
  + @wFavoritos * COALESCE(ps.favoritos, 0)
  + @wContactos * COALESCE(ps.contactos, 0)
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
    wContactos: w.W_CONTACTOS,
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
  return [...new Set(
    String(titulo || '')
      .toLowerCase()
      .split(/[^\p{L}\p{N}]+/u)
      .filter(palabra => palabra.length >= LARGO_MINIMO_KEYWORD),
  )].slice(0, MAX_KEYWORDS);
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
function getRelatedProducts(product, { limit = 10 } = {}) {
  if (!product) return [];

  const keywords = palabrasClaveDeTitulo(product.title);
  // Un OR de LIKEs, uno por palabra. Van como parámetros nombrados (@kw0,
  // @kw1...) y no interpolados, para que un título con comillas o con un %
  // no se convierta en inyección ni en un comodín accidental.
  const condicionKeywords = keywords.length
    ? keywords.map((_, i) => `LOWER(p.title) LIKE @kw${i} ESCAPE '\\'`).join(' OR ')
    : '0';
  const paramsKeywords = Object.fromEntries(
    keywords.map((palabra, i) => [`kw${i}`, `%${escaparLike(palabra)}%`]),
  );

  const rows = db.prepare(`
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
    ORDER BY tramoDisponibilidad ASC, tramo ASC, score DESC, p.created_at DESC
    LIMIT @limit
  `).all({
    ...paramsScore(),
    ...paramsKeywords,
    productId: product.id,
    seller: product.seller || null,
    category: product.category || null,
    limit,
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
function getSellerOtherProducts(sellerId, { excludeProductId = null, limit = 10 } = {}) {
  if (!sellerId) return [];

  const rows = db.prepare(`
    SELECT p.* FROM products p
    WHERE p.seller = @sellerId
      AND (@excludeProductId IS NULL OR p.id != @excludeProductId)
      AND ${SQL_PRODUCTO_ACTIVO}
    ORDER BY p.created_at DESC, p.id DESC
    LIMIT @limit
  `).all({ sellerId, excludeProductId, limit });

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
function purgeOldSearchQueries({ days = SEARCH_QUERY_RETENTION_DAYS } = {}) {
  const info = db.prepare(
    "DELETE FROM search_queries WHERE created_at < datetime('now', '-' || ? || ' days')"
  ).run(days);
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
function purgeOldSearchQueriesIfDue() {
  if (Date.now() - ultimaPurgaSearchQueries < SEARCH_PURGE_INTERVAL_MS) return 0;
  return purgeOldSearchQueries();
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
  return normalizeSearchQuery(text)
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')  // marcas de acento sueltas que dejó NFD
    .replace(/[^a-z0-9 ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .split(' ')
    .map(palabra => (palabra.length > 3 && palabra.endsWith('s') ? palabra.slice(0, -1) : palabra))
    .join(' ');
}

/**
 * Registra una búsqueda ejecutada. Descarta ruido (vacía, muy corta/larga) y
 * los reintentos del mismo dispositivo sobre el mismo término dentro de
 * SEARCH_QUERY_DEDUPE_SECONDS.
 *
 * Devuelve true solo si la fila entró (es decir, si el ranking cambió).
 */
function recordSearchQuery(text, deviceId = null) {
  const normalized = normalizeSearchQuery(text);
  if (normalized.length < SEARCH_QUERY_MIN_LEN || normalized.length > SEARCH_QUERY_MAX_LEN) {
    return false;
  }
  const key = searchQueryKey(normalized);
  if (!key) return false;

  purgeOldSearchQueriesIfDue();

  // La deduplicación es por dispositivo: sin deviceId no se puede distinguir
  // "la misma persona insistiendo" de "dos personas buscando lo mismo", y
  // castigar la segunda sería peor que dejar pasar la primera.
  if (deviceId) {
    const reciente = db.prepare(`
      SELECT 1 FROM search_queries
      WHERE device_id = ? AND query_key = ?
        AND created_at >= datetime('now', '-' || ? || ' seconds')
      LIMIT 1
    `).get(deviceId, key, SEARCH_QUERY_DEDUPE_SECONDS);
    if (reciente) return false;
  }

  db.prepare(
    'INSERT INTO search_queries (query_text, query_key, device_id) VALUES (?, ?, ?)'
  ).run(normalized, key, deviceId || null);
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
function getTrendingSearches({ days, limit }) {
  return db.prepare(`
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
  `).all({ days, limit });
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
function getFallbackSearchTerms({ limit }) {
  const w = FEED_WEIGHTS;
  return db.prepare(`
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
        @wViews * COALESCE(ps.vistas, 0)
        + @wFavoritos * COALESCE(ps.favoritos, 0)
        + @wContactos * COALESCE(ps.contactos, 0)
      ) AS score
    FROM products p
    LEFT JOIN product_stats ps ON ps.product_id = p.id
    WHERE ${SQL_PRODUCTO_ACTIVO}
    GROUP BY p.id
    ORDER BY score DESC, p.created_at DESC
    LIMIT @limit
  `).all({
    popularityWindowDays: w.POPULARITY_WINDOW_DAYS,
    wViews: w.W_VIEWS,
    wFavoritos: w.W_FAVORITOS,
    wContactos: w.W_CONTACTOS,
    limit,
  });
}

// ─── Category Engagement (orden dinámico de íconos de categoría) ─────────
// Pesos y ventana viven en un solo lugar para poder tunearlos sin tocar la
// query. Ventana corta a propósito: una categoría popular hace un mes no
// debe seguir arriba si ya nadie la toca.
const CATEGORY_ENGAGEMENT_WEIGHTS = {
  publish: 10,       // señal fuerte: alguien generó oferta real
  product_view: 3,   // señal media: interés en un producto concreto
  icon_tap: 1,        // señal débil: curiosidad/navegación
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
  setImmediate(() => {
    try {
      db.prepare(`
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
function getCategoriesRanked() {
  if (categoriesRankedCache && categoriesRankedCache.expiresAt > Date.now()) {
    return categoriesRankedCache.data;
  }

  const eventTypes = Object.keys(CATEGORY_ENGAGEMENT_WEIGHTS);
  const scoreExpr = eventTypes
    .map(() => `SUM(CASE WHEN e.event_type = ? THEN ? ELSE 0 END)`)
    .join(' + ');
  const weightParams = eventTypes.flatMap((type) => [type, CATEGORY_ENGAGEMENT_WEIGHTS[type]]);

  const rows = db.prepare(`
    SELECT c.id, c.name, c.emoji, c.icon, c.color,
           (${scoreExpr}) AS score
    FROM categories c
    LEFT JOIN category_engagement_events e
      ON e.category_id = c.id
      AND e.created_at >= datetime('now', ?)
    GROUP BY c.id
    ORDER BY score DESC, c.id ASC
  `).all(...weightParams, `-${CATEGORY_ENGAGEMENT_WINDOW_DAYS} days`);

  categoriesRankedCache = { data: rows, expiresAt: Date.now() + CATEGORY_RANKED_CACHE_TTL_MS };
  return rows;
}

/** Solo para tests: fuerza a que la próxima getCategoriesRanked() recalcule. */
function invalidateCategoriesRankedCache() {
  categoriesRankedCache = null;
}

module.exports = {
  initDatabase,
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
  anonymizeSellerAccount,
};
