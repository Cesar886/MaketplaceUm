const {
  requireAuth
} = require('../auth');
const db = require('../database');
const {
  products,
  sellers,
  categories
} = require('../data');

// El carrito es PRIVADO de cada usuario. Todos los endpoints exigen
// autenticación —incluido el GET— y toda consulta va acotada por
// `req.user.id`.
//
// Antes no era así: la tabla `cart` no tenía `user_id` y `GET /api/cart`
// devolvía el array completo sin pedir token, así que todo el mundo veía y
// modificaba el mismo carrito. Los helpers de database.js piden ahora el
// userId como primer argumento para que ese descuido no pueda repetirse.

function register(app) {
  function enrichProduct(p) {
    if (!p) return null;
    return {
      ...p,
      sellerObj: sellers.find(s => s.id === p.seller) || null,
      categoryObj: categories.find(c => c.id === p.category) || null
    };
  }
  async function cartOf(userId) {
    return (await db.getCartItems(userId)).map(item => ({
      id: item.id,
      productId: item.productId,
      quantity: item.quantity,
      meetingPoint: item.meetingPoint,
      product: enrichProduct(products.find(p => p.id === item.productId) || null)
    }));
  }

  // GET /api/cart — solo el carrito de quien pregunta.
  app.get('/api/cart', requireAuth, async (req, res) => {
    res.json(await cartOf(req.user.id));
  });

  // POST /api/cart – agregar item
  app.post('/api/cart', requireAuth, async (req, res) => {
    const {
      productId,
      quantity,
      meetingPoint
    } = req.body;
    if (!productId || !quantity) {
      return res.status(400).json({
        error: 'productId y quantity son requeridos'
      });
    }
    const cantidad = Number(quantity);
    if (!Number.isInteger(cantidad) || cantidad < 1) {
      return res.status(400).json({
        error: 'La cantidad debe ser un número entero mayor a cero.'
      });
    }
    if (!products.some(p => p.id === productId)) {
      return res.status(404).json({
        error: 'Producto no encontrado'
      });
    }
    await db.upsertCartItem(req.user.id, {
      id: `c${Date.now()}`,
      productId,
      quantity: cantidad,
      meetingPoint
    });
    res.status(201).json(await cartOf(req.user.id));
  });

  // PUT /api/cart/:id
  app.put('/api/cart/:id', requireAuth, async (req, res) => {
    const {
      quantity,
      meetingPoint
    } = req.body;
    if (quantity != null) {
      const cantidad = Number(quantity);
      if (!Number.isInteger(cantidad) || cantidad < 1) {
        return res.status(400).json({
          error: 'La cantidad debe ser un número entero mayor a cero.'
        });
      }
    }

    // Un item que no es del usuario responde 404, no 403: confirmar que
    // existe pero es de otra persona ya filtra información.
    const ok = await db.updateCartItem(req.user.id, req.params.id, {
      quantity: quantity != null ? Number(quantity) : null,
      meetingPoint: meetingPoint ?? null
    });
    if (!ok) return res.status(404).json({
      error: 'Item no encontrado'
    });
    res.json(await cartOf(req.user.id));
  });

  // DELETE /api/cart/:id
  app.delete('/api/cart/:id', requireAuth, async (req, res) => {
    if (!(await db.deleteCartItem(req.user.id, req.params.id))) {
      return res.status(404).json({
        error: 'Item no encontrado'
      });
    }
    res.json({
      ok: true
    });
  });
}
module.exports = {
  register
};
