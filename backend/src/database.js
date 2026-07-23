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
      extras TEXT DEFAULT '[]'
    );

    CREATE TABLE IF NOT EXISTS price_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id TEXT NOT NULL,
      old_price REAL NOT NULL,
      new_price REAL NOT NULL,
      changed_by TEXT NOT NULL,
      changed_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
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

  // 4. price_history ya se crea con CREATE TABLE IF NOT EXISTS arriba

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
      isFeatured, isOffer, isFavorite, status, offerExpiresAt, extras)
    VALUES (@id, @title, @price, @priceNum, @category, @description, @publishedAgo, @seller,
      @images, @imageIcon, @imageColor, @previousPrice, @discountLabel,
      @isFeatured, @isOffer, @isFavorite, @status, @offerExpiresAt, @extras)
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
      status = @status, offerExpiresAt = @offerExpiresAt, extras = @extras
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
 * según su historial de precios (old_price y new_price).
 */
function getHighestPriceInLastDays(productId, days = 30) {
  const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  const row = db.prepare(`
    SELECT MAX(max_price) as highest FROM (
      SELECT old_price as max_price FROM price_history
        WHERE product_id = ? AND changed_at >= ?
      UNION ALL
      SELECT new_price FROM price_history
        WHERE product_id = ? AND changed_at >= ?
    )
  `).get(productId, cutoff, productId, cutoff);
  return row?.highest ?? null;
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
 * Inserta un registro en price_history.
 */
function insertPriceHistory(productId, oldPrice, newPrice, changedBy) {
  db.prepare(`
    INSERT INTO price_history (product_id, old_price, new_price, changed_by, changed_at)
    VALUES (?, ?, ?, ?, datetime('now'))
  `).run(productId, oldPrice, newPrice, changedBy);
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
  countPriceEditsLastHour,
  insertPriceHistory,
  expireStaleOffers,
};
