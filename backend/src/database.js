const Database = require('better-sqlite3');
const path = require('path');

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
      verified INTEGER DEFAULT 0,
      businessDescription TEXT,
      businessCategory TEXT,
      businessHours TEXT
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
      manual_status TEXT DEFAULT NULL
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
      resolved_at TEXT
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
      product_id TEXT NOT NULL,
      category TEXT NOT NULL,
      tipo TEXT NOT NULL CHECK(tipo IN ('vista', 'favorito', 'contacto')),
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
    -- por tecla). Agregado estadístico puro para alimentar "trending
    -- searches": solo texto + timestamp, sin device_id/user_id.
    CREATE TABLE IF NOT EXISTS search_queries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      query_text TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_search_queries_created ON search_queries(created_at);
    CREATE INDEX IF NOT EXISTS idx_search_queries_text ON search_queries(query_text, created_at);

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
      ubicacion_lat REAL,
      ubicacion_lng REAL,
      link_red_social TEXT,

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

  console.log('🔄 Migración de schema completada');
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
    availableDays: JSON.parse(row.availableDays || '[]'),
    updated_at: row.updated_at || null,
    locationLat: row.location_lat ?? null,
    locationLng: row.location_lng ?? null,
    paymentMethods: row.paymentMethods ? JSON.parse(row.paymentMethods) : null,
    views: row.views ?? 0,
  };
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
  };
}

// ─── API de datos ──────────────────────────────────────────

function getCategories() {
  return db.prepare('SELECT * FROM categories ORDER BY id').all();
}

function rowToSeller(row) {
  if (!row) return null;
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
    verified: !!row.verified,
    // Determina el color/etiqueta de la insignia de verificación en la app.
    // 'particular' es lo que la UI llama "externo".
    tipoCuenta: row.tipo_cuenta || 'particular',
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
    // Mediana en minutos entre el mensaje de un comprador y la respuesta del
    // vendedor. null = todavía no hay respuestas suficientes para calcularla.
    medianResponseMinutes: row.median_response_minutes ?? null,
    facebookUrl: row.facebook_url || null,
    instagramUrl: row.instagram_url || null,
    whatsappNumber: row.whatsapp_number || null,
    tiktokUrl: row.tiktok_url || null,
    twitterUrl: row.twitter_url || null,
  };
}

function getSellers() {
  const rows = db.prepare('SELECT * FROM sellers ORDER BY id').all();
  return rows.map(rowToSeller);
}

function insertSeller(seller) {
  db.prepare(`
    INSERT OR IGNORE INTO sellers (id, name, avatarInitials, major, isBusiness, logoUrl, rating, reviews, verified)
    VALUES (@id, @name, @avatarInitials, @major, @isBusiness, @logoUrl, @rating, @reviews, @verified)
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
  const rows = db.prepare('SELECT * FROM products').all();
  return rows.map(rowToProduct);
}

function getProductById(id) {
  const row = db.prepare('SELECT * FROM products WHERE id = ?').get(id);
  return rowToProduct(row);
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
      location_lat, location_lng, paymentMethods)
    VALUES (@id, @title, @price, @priceNum, @category, @description, @publishedAgo, @seller,
      @images, @imageIcon, @imageColor, @previousPrice, @discountLabel,
      @isFeatured, @isOffer, @isFavorite, @status, @manual_status, @offerExpiresAt, @extras,
      @stock_quantity, @stock_reset_daily, @stock_initial, @stock_updated_at, @created_at, @availableDays, @updated_at,
      @location_lat, @location_lng, @paymentMethods)
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
      availableDays = excluded.availableDays, updated_at = excluded.updated_at,
      location_lat = excluded.location_lat, location_lng = excluded.location_lng,
      paymentMethods = excluded.paymentMethods
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
      paymentMethods = @paymentMethods
    WHERE id = ?
  `).run(row, id);
  return getProductById(id);
}

function deleteProduct(id) {
  db.prepare('DELETE FROM products WHERE id = ?').run(id);
}

function incrementProductViews(id) {
  db.prepare('UPDATE products SET views = views + 1 WHERE id = ?').run(id);
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
function insertPriceHistory(productId, price) { console.log("INSERTING PRICE HISTORY:", productId, price);
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
    s.tipo_verificacion   AS autorTipoVerificacion
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
      name: row.autorNombre || 'Usuario',
      avatarInitials: row.autorIniciales || '??',
      logoUrl: row.autorLogo || null,
      major: row.autorMajor || '',
      isBusiness: !!row.autorEsNegocio,
      verified: !!row.autorVerificado,
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
    s.tipo_verificacion AS autorTipoVerificacion
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
      name: row.autorNombre || 'Usuario',
      avatarInitials: row.autorIniciales || '??',
      logoUrl: row.autorLogo || null,
      major: row.autorMajor || '',
      isBusiness: !!row.autorEsNegocio,
      verified: !!row.autorVerificado,
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

function markNotificationRead(notificationId) {
  db.prepare('UPDATE notifications SET read = 1 WHERE id = ?').run(notificationId);
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

function getConversationsForUser(userId) {
  return db.prepare(`
    SELECT * FROM conversations
    WHERE buyer_id = ? OR seller_id = ?
    ORDER BY last_message_at DESC
  `).all(userId, userId).map(row => ({
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

function updateConversationPreview(conversationId, previewText) {
  db.prepare(`
    UPDATE conversations SET last_message_at = datetime('now'), last_message_preview = ? WHERE id = ?
  `).run(previewText, conversationId);
}

function getUnreadMessageCount(userId) {
  const row = db.prepare(`
    SELECT COUNT(*) as count FROM messages m
    JOIN conversations c ON c.id = m.conversation_id
    WHERE (c.buyer_id = ? OR c.seller_id = ?) AND m.sender_id != ? AND m.read = 0
  `).get(userId, userId, userId);
  return row?.count ?? 0;
}

// ─── Wanted Posts ───────────────────────────────────────────────

function createWantedPost(post) {
  db.prepare(`
    INSERT INTO wanted_posts (id, user_id, title, description, category_id, type, price_min, price_max, status, created_at, location_lat, location_lng, paymentMethods)
    VALUES (@id, @userId, @title, @description, @categoryId, @type, @priceMin, @priceMax, 'abierta', datetime('now'), @location_lat, @location_lng, @paymentMethods)
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
  });
  return getWantedPostById(post.id);
}

function getWantedPostById(id) {
  const row = db.prepare('SELECT * FROM wanted_posts WHERE id = ?').get(id);
  return rowToWantedPost(row);
}

function listWantedPosts({ categoryId, status, type } = {}) {
  let query = 'SELECT * FROM wanted_posts WHERE 1=1';
  const params = [];
  if (categoryId) {
    query += ' AND category_id = ?';
    params.push(categoryId);
  }
  query += ' AND status = ?';
  params.push(status || 'abierta');
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

function getMessages(conversationId) {
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
    WHERE m.conversation_id = ?
    ORDER BY m.created_at ASC
  `).all(conversationId).map(row => rowToMessage(row));
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
  (p.manual_status IS NULL OR p.manual_status NOT IN ('sold', 'paused'))
  AND (p.status IS NULL OR p.status != 'sold')
  AND (p.stock_quantity IS NULL OR p.stock_quantity > 0)
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

function normalizeSearchQuery(text) {
  return String(text ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
}

/** Registra una búsqueda ejecutada. Descarta ruido (vacía, muy corta/larga). */
function recordSearchQuery(text) {
  const normalized = normalizeSearchQuery(text);
  if (normalized.length < SEARCH_QUERY_MIN_LEN || normalized.length > SEARCH_QUERY_MAX_LEN) {
    return false;
  }
  db.prepare('INSERT INTO search_queries (query_text) VALUES (?)').run(normalized);
  return true;
}

/** Términos más buscados en los últimos `days` días, de más a menos frecuente. */
function getTrendingSearches({ days, limit }) {
  return db.prepare(`
    SELECT query_text AS queryText, COUNT(*) AS count
    FROM search_queries
    WHERE created_at >= datetime('now', '-' || ? || ' days')
    GROUP BY query_text
    ORDER BY count DESC, MAX(created_at) DESC
    LIMIT ?
  `).all(days, limit);
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
function getFallbackSearchTerms({ limit }) {
  return db.prepare(`
    SELECT c.name AS queryText, COUNT(p.id) AS count
    FROM categories c
    JOIN products p ON p.category = c.id AND ${SQL_PRODUCTO_ACTIVO}
    GROUP BY c.id
    ORDER BY count DESC, c.name ASC
    LIMIT ?
  `).all(limit);
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
  rowToSeller,
  insertSeller,
  getHighlightPlans,
  getAllProducts,
  getProductById,
  insertProduct,
  updateProduct,
  deleteProduct,
  incrementProductViews,
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
  // Preguntas y respuestas
  PREGUNTAS_POR_PAGINA,
  PREGUNTAS_MAX_POR_PAGINA,
  PREGUNTAS_PREVIEW,
  createProductQuestion,
  answerProductQuestion,
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
  getConversationsForUser,
  getUnreadMessageCount,
  // Wanted Posts
  createWantedPost,
  getWantedPostById,
  listWantedPosts,
  updateWantedPost,
  incrementWantedPostViews,
  resolveWantedPost,
  countWantedPostsSince,
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
  recordSearchQuery,
  getTrendingSearches,
  getFallbackSearchTerms,
  // Category engagement (orden dinámico de categorías)
  CATEGORY_ENGAGEMENT_WEIGHTS,
  CATEGORY_ENGAGEMENT_WINDOW_DAYS,
  trackCategoryEngagement,
  getCategoriesRanked,
  invalidateCategoriesRankedCache,
};
