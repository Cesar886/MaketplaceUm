const Database = require('better-sqlite3');
const path = require('path');

const DB_PATH = path.join(__dirname, '..', 'mercadito_um.db');

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

  console.log('🔄 Migración de schema completada');
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
    businessDescription: row.businessDescription || null,
    businessCategory: row.businessCategory || null,
    businessHours: JSON.parse(row.businessHours || '{}'),
    locationLat: row.location_lat ?? null,
    locationLng: row.location_lng ?? null,
    paymentMethods: JSON.parse(row.paymentMethods || '[]'),
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

function getAllCartItems() {
  return db.prepare('SELECT * FROM cart').all();
}

function addCartItem(cartItem) {
  db.prepare(`
    INSERT INTO cart (id, productId, quantity, meetingPoint)
    VALUES (@id, @productId, @quantity, @meetingPoint)
  `).run(cartItem);
}

function updateCartItem(id, quantity) {
  db.prepare('UPDATE cart SET quantity = ? WHERE id = ?').run(quantity, id);
}

function deleteCartItem(id) {
  db.prepare('DELETE FROM cart WHERE id = ?').run(id);
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

function createMessage(id, conversationId, senderId, text, imageUrl = null) {
  db.prepare(`
    INSERT INTO messages (id, conversation_id, sender_id, text, image_url, created_at, read)
    VALUES (?, ?, ?, ?, ?, datetime('now'), 0)
  `).run(id, conversationId, senderId, text, imageUrl);
  updateConversationPreview(conversationId, imageUrl ? '📷 Foto' : text);
}

function getMessages(conversationId) {
  return db.prepare(
    'SELECT * FROM messages WHERE conversation_id = ? ORDER BY created_at ASC'
  ).all(conversationId).map(row => ({
    id: row.id,
    conversationId: row.conversation_id,
    senderId: row.sender_id,
    text: row.text,
    imageUrl: row.image_url || null,
    createdAt: row.created_at,
    read: !!row.read,
  }));
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
          + CASE WHEN s.avg_response_minutes IS NOT NULL
                  AND s.avg_response_minutes <= @fastReplyMaxMinutes
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
  getAllCartItems,
  addCartItem,
  updateCartItem,
  deleteCartItem,
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
  markConversationMessagesRead,
  deleteMessage,
  // Feed Ranking
  FEED_WEIGHTS,
  registrarInteraccion,
  limpiarInteraccionesAntiguas,
  linkDeviceToUser,
  getFeedRanked,
};
