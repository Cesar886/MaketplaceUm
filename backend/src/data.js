const db = require('./database');

// ─── Inicializar base de datos (se ejecuta al importar) ────
db.initDatabase();

// ─── Exportar datos como arrays (compatible con las rutas existentes) ────

const categories = db.getCategories();
const sellers = db.getSellers();
const highlightPlans = db.getHighlightPlans();

// Cargar products, cart y ownListings desde SQLite
let products = db.getAllProducts();

let cart = db.getAllCartItems().map(row => ({
  id: row.id,
  productId: row.productId,
  quantity: row.quantity,
  meetingPoint: row.meetingPoint,
}));

let ownListings = db.getAllListings().map(row => ({
  id: row.id,
  productId: row.productId,
}));

// ─── Registrar un nuevo vendedor (DB + en memoria) ────────────
function registerSeller(sellerData) {
  // Insertar en SQLite
  db.getDb().prepare(`
    INSERT OR IGNORE INTO sellers (id, name, avatarInitials, major, rating, reviews, verified)
    VALUES (@id, @name, @avatarInitials, @major, @rating, @reviews, @verified)
  `).run({
    ...sellerData,
    verified: sellerData.verified ? 1 : 0,
    rating: sellerData.rating ?? 0,
    reviews: sellerData.reviews ?? 0,
  });
  // Refrescar la lista en memoria desde DB
  sellers.length = 0;
  sellers.push(...db.getSellers());
}

// ─── Persistencia ─────────────────────────────────────────────
function saveData() {
  // products → SQLite (reescribir todos)
  db.getDb().transaction(() => {
    // Eliminar todos los products y re-insertarlos
    db.getDb().prepare('DELETE FROM products').run();
    for (const p of products) {
      db.insertProduct(p);
    }

    // Cart
    db.getDb().prepare('DELETE FROM cart').run();
    for (const c of cart) {
      db.addCartItem(c);
    }

    // Listings
    db.getDb().prepare('DELETE FROM listings').run();
    for (const l of ownListings) {
      db.addListing(l);
    }
  })();
}

module.exports = { categories, sellers, products, cart, ownListings, highlightPlans, saveData, registerSeller };
