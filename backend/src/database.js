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
      verified INTEGER DEFAULT 0
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
      stock_updated_at TEXT
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

  // 8. Migrar conversations: permitir wanted_post_id y relajar product_id a NULL
  //    (SQLite no permite quitar NOT NULL con ALTER TABLE, así que se recrea la
  //    tabla preservando los datos existentes). También se recrea messages para
  //    arreglar la FK que SQLite reescribe al renombrar conversations.
  const convCols = db.prepare("PRAGMA table_info('conversations')").all();
  const hasWantedPostId = convCols.some(c => c.name === 'wanted_post_id');
  if (!hasWantedPostId) {
    db.pragma('foreign_keys = OFF');
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
    db.pragma('foreign_keys = ON');
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
    offerExpiresAt: row.offerExpiresAt || null,
    extras: JSON.parse(row.extras || '[]'),
    stock_quantity: row.stock_quantity ?? null,
    stock_reset_daily: !!row.stock_reset_daily,
    stock_initial: row.stock_initial ?? null,
    stock_updated_at: row.stock_updated_at || null,
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
    offerExpiresAt: product.offerExpiresAt || null,
    extras: JSON.stringify(product.extras || []),
    stock_quantity: product.stock_quantity ?? null,
    stock_reset_daily: product.stock_reset_daily ? 1 : 0,
    stock_initial: product.stock_initial ?? null,
    stock_updated_at: product.stock_updated_at || null,
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
    avatarInitials: row.avatarInitials || '',
    major: row.major || '',
    isBusiness: !!row.isBusiness,
    logoUrl: row.logoUrl || null,
    rating: row.rating ?? 0,
    reviews: row.reviews ?? 0,
    verified: !!row.verified,
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
  db.prepare(`
    INSERT OR REPLACE INTO products (id, title, price, priceNum, category, description, publishedAgo, seller,
      images, imageIcon, imageColor, previousPrice, discountLabel,
      isFeatured, isOffer, isFavorite, status, offerExpiresAt, extras,
      stock_quantity, stock_reset_daily, stock_initial, stock_updated_at)
    VALUES (@id, @title, @price, @priceNum, @category, @description, @publishedAgo, @seller,
      @images, @imageIcon, @imageColor, @previousPrice, @discountLabel,
      @isFeatured, @isOffer, @isFavorite, @status, @offerExpiresAt, @extras,
      @stock_quantity, @stock_reset_daily, @stock_initial, @stock_updated_at)
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
      status = @status, offerExpiresAt = @offerExpiresAt, extras = @extras,
      stock_quantity = @stock_quantity, stock_reset_daily = @stock_reset_daily,
      stock_initial = @stock_initial, stock_updated_at = @stock_updated_at
    WHERE id = ?
  `).run(row, id);
  return getProductById(id);
}

function deleteProduct(id) {
  db.prepare('DELETE FROM products WHERE id = ?').run(id);
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
    INSERT INTO wanted_posts (id, user_id, title, description, category_id, type, price_min, price_max, status, created_at)
    VALUES (@id, @userId, @title, @description, @categoryId, @type, @priceMin, @priceMax, 'abierta', datetime('now'))
  `).run({
    id: post.id,
    userId: post.userId,
    title: post.title,
    description: post.description || null,
    categoryId: post.categoryId,
    type: post.type,
    priceMin: post.priceMin ?? null,
    priceMax: post.priceMax ?? null,
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

function createMessage(id, conversationId, senderId, text) {
  db.prepare(`
    INSERT INTO messages (id, conversation_id, sender_id, text, created_at, read)
    VALUES (?, ?, ?, ?, datetime('now'), 0)
  `).run(id, conversationId, senderId, text);
  updateConversationPreview(conversationId, text);
}

function getMessages(conversationId) {
  return db.prepare(
    'SELECT * FROM messages WHERE conversation_id = ? ORDER BY created_at ASC'
  ).all(conversationId).map(row => ({
    id: row.id,
    conversationId: row.conversation_id,
    senderId: row.sender_id,
    text: row.text,
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
  db.prepare("UPDATE messages SET text = '[Mensaje eliminado]' WHERE id = ?").run(messageId);
  return true;
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
};
