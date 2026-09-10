const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const sharp = require('sharp');
const {
  products,
  sellers,
  categories,
  saveData
} = require('../data');
const {
  requireAuth
} = require('../auth');
const db = require('../database');
const {
  sendPush
} = require('../push');
const {
  encolarProducto
} = require('../notifications/retargeting');
const {
  validateLocation,
  validatePaymentMethods
} = require('../validation/sellerProfile');
const {
  validarAtributosCategoria,
  atributosDestacados
} = require('../validation/atributosCategoria');
const {
  validarMetodosPermitidos
} = require('../payments/methods');
const {
  getPublicationPolicy,
  expiresAtFromNow,
  isExpired
} = require('../publicationPolicy');

// Configuración anti-abuso de ofertas
const COOLDOWN_HOURS = 72;

// Tope de cada carrusel del detalle (relacionados y otros del vendedor). Es
// un carrusel horizontal: pasado cierto punto nadie sigue deslizando, y cada
// producto extra es peso en la misma respuesta que el detalle.
const RELACIONADOS_MAX = 10;

// Pisos de longitud del texto que escribe el vendedor. El título y la
// descripción no son solo UI de la app: son literalmente el `og:title` y el
// `og:description` de la vista previa que se dibuja cuando alguien comparte
// el link del producto en WhatsApp (ver `website/app/producto/[id]/page.tsx`).
// Exigir solo "campo no vacío" dejaba entrar títulos como "Jajs", y con eso
// el preview se lee como un link basura al lado de uno de Mercado Libre.
// El mismo piso está en el formulario de la app
// (`lib/screens/publish_product_screen.dart`); acá es donde se hace cumplir,
// porque la validación del cliente se puede saltar.
const MINIMO_TITULO = 10;
const MINIMO_DESCRIPCION = 20;

/**
 * Valida título y descripción contra los pisos de longitud.
 * Devuelve `{ error }` con un mensaje presentable, o `{}` si están bien.
 */
function validarTextos(title, description) {
  if (String(title).trim().length < MINIMO_TITULO) {
    return {
      error: `El título debe tener al menos ${MINIMO_TITULO} caracteres y describir qué vendes`
    };
  }
  if (String(description).trim().length < MINIMO_DESCRIPCION) {
    return {
      error: `La descripción debe tener al menos ${MINIMO_DESCRIPCION} caracteres`
    };
  }
  return {};
}

// ─── Helper para subir imágenes: usa multer directamente ────
const multer = require('multer');
const UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads');
const upload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, UPLOADS_DIR),
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname) || '.jpg';
      cb(null, `product_${Date.now()}_${crypto.randomBytes(12).toString('hex')}${ext}`);
    }
  }),
  limits: {
    fileSize: 10 * 1024 * 1024
  },
  fileFilter: (_req, file, cb) => {
    cb(null, /\.(jpg|jpeg|png|gif|webp)$/i.test(path.extname(file.originalname)));
  }
});

/**
 * Ancho máximo al que se guarda una foto de producto.
 *
 * Convertir a WebP sin redimensionar dejaba las fotos a resolución nativa de
 * cámara: una foto de 12 MP salía como WebP de 1.4 MB para pintarse en una
 * tarjeta de ~180 px de ancho. Con el servidor sirviendo estáticos a ~20 KB/s
 * eso son ~60 s por imagen, y como `Image.network` en Flutter no tiene
 * timeout, la tarjeta se quedaba con el spinner girando ese minuto entero sin
 * caer nunca al placeholder (el 200 OK llega, solo que tardísimo).
 *
 * 1280 px cubre el uso más exigente que tiene hoy una foto de producto — el
 * carrusel a pantalla completa en el detalle — con margen para pantallas a
 * 3x, y recorta el peso en un orden de magnitud. `withoutEnlargement` evita
 * que una foto ya pequeña se estire y termine pesando MÁS que el original.
 */
const MAX_IMAGE_WIDTH = 1280;

/**
 * Convierte una imagen a WebP usando sharp.
 * Borra el archivo original y devuelve la ruta pública del .webp.
 */
async function convertToWebp(filePath) {
  const parsed = path.parse(filePath);
  const webpPath = path.join(parsed.dir, parsed.name + '.webp');
  const publicPath = '/uploads/' + parsed.name + '.webp';
  await sharp(filePath).rotate() // respeta la orientación EXIF antes de redimensionar
  .resize({
    width: MAX_IMAGE_WIDTH,
    withoutEnlargement: true
  }).webp({
    quality: 80
  }).toFile(webpPath);

  // Eliminar el archivo original
  fs.unlinkSync(filePath);
  return publicPath;
}

/**
 * Normaliza el input de extras (crear/editar). Acepta array o JSON string
 * (multipart/form-data manda arrays como string). Filtra entradas sin nombre.
 */
function normalizeExtras(extrasInput) {
  if (typeof extrasInput === 'string') {
    try {
      extrasInput = JSON.parse(extrasInput);
    } catch {
      extrasInput = [];
    }
  }
  return Array.isArray(extrasInput) ? extrasInput.map(e => ({
    name: String(e.name || ''),
    extraPrice: Number(e.extraPrice) || 0
  })).filter(e => e.name) : [];
}

/**
 * Normaliza los días de la semana disponibles (0=lunes .. 6=domingo, mismo
 * índice que Seller.businessHours y que el day picker de Flutter):
 * dedupe, valida rango entero y ordena. Acepta array o JSON string.
 */
function normalizeAvailableDays(daysInput) {
  if (typeof daysInput === 'string') {
    try {
      daysInput = JSON.parse(daysInput);
    } catch {
      daysInput = [];
    }
  }
  return Array.isArray(daysInput) ? [...new Set(daysInput.map(d => Number(d)).filter(d => Number.isInteger(d) && d >= 0 && d <= 6))].sort() : [];
}

// ─── Estados manuales que el vendedor puede activar explícitamente ────
// 'available'/'unavailable' YA NO son valores manuales: son resultados del
// cálculo automático (ver computeProductStatus). Estos 4 son "pegajosos":
// no expiran con el tiempo/inventario/calendario, solo los quita el vendedor
// reactivando (PATCH /status con manual_status: null) o borrando el producto.
const MANUAL_STATUSES = ['sold', 'reserved', 'negotiating', 'paused'];
const DAY_NAMES_ES = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

/**
 * Calcula el badge de disponibilidad de un producto en tiempo real,
 * evaluando en orden de más estricto a más flexible y deteniéndose en el
 * primer nivel que aplique:
 *   1. manual_status (vendido/apartado/en negociación/pausado) — sobreescribe todo.
 *   2. Inventario agotado (stock_quantity <= 0, solo si usa stock limitado).
 *   3. Días disponibles: si el vendedor marcó al menos un día y hoy no es
 *      uno de ellos → "disponible el [próximo día marcado]". 0 días marcados
 *      significa "sin restricción de calendario", no "nunca disponible".
 *   4. Horario del negocio (solo vendedores tipo negocio con businessHours
 *      configurado): fuera de horario → "cerrado"/"abre a las [hora]".
 *   5. Happy path: "disponible".
 * Devuelve { computed_status, computed_status_detail } — nunca persiste en
 * la base de datos, se recalcula en cada lectura.
 */
function computeProductStatus(product, seller) {
  if (product.manual_status && MANUAL_STATUSES.includes(product.manual_status)) {
    return {
      computed_status: product.manual_status,
      computed_status_detail: {}
    };
  }
  const usesLimitedStock = product.stock_quantity !== null && product.stock_quantity !== undefined;
  if (usesLimitedStock && product.stock_quantity <= 0) {
    return {
      computed_status: 'sold_out',
      computed_status_detail: {}
    };
  }
  const now = new Date();
  const todayIdx = (now.getDay() + 6) % 7; // JS getDay(): 0=domingo..6=sábado → 0=lunes..6=domingo

  const availableDays = Array.isArray(product.availableDays) ? product.availableDays : [];
  if (availableDays.length > 0 && !availableDays.includes(todayIdx)) {
    let nextDay = null;
    for (let offset = 1; offset <= 7; offset++) {
      const candidate = (todayIdx + offset) % 7;
      if (availableDays.includes(candidate)) {
        nextDay = candidate;
        break;
      }
    }
    return {
      computed_status: 'available_other_day',
      computed_status_detail: {
        next_available_day: nextDay !== null ? DAY_NAMES_ES[nextDay] : null
      }
    };
  }
  if (seller && seller.isBusiness && seller.businessHours && Object.keys(seller.businessHours).length > 0) {
    const range = seller.businessHours[String(todayIdx)] || seller.businessHours[todayIdx];
    if (!range) {
      return {
        computed_status: 'closed',
        computed_status_detail: {}
      };
    }
    const [openH, openM] = String(range.open).split(':').map(Number);
    const [closeH, closeM] = String(range.close).split(':').map(Number);
    const nowMinutes = now.getHours() * 60 + now.getMinutes();
    const openMinutes = openH * 60 + openM;
    const closeMinutes = closeH * 60 + closeM;
    if (nowMinutes < openMinutes) {
      return {
        computed_status: 'closed',
        computed_status_detail: {
          opens_at: range.open
        }
      };
    }
    if (nowMinutes >= closeMinutes) {
      return {
        computed_status: 'closed',
        computed_status_detail: {}
      };
    }
  }
  return {
    computed_status: 'available',
    computed_status_detail: {}
  };
}

/**
 * Lee el parámetro `?atributos=` de la búsqueda. Devuelve null (= no filtrar)
 * si viene mal armado; ver la nota en GET /api/products sobre por qué no es
 * un 400.
 */
function parseFiltroAtributos(raw) {
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
    return Object.keys(parsed).length > 0 ? parsed : null;
  } catch {
    return null;
  }
}

/**
 * ¿Las respuestas de un producto satisfacen todos los criterios pedidos?
 *
 * Semántica: AND entre keys distintas, OR dentro de una key con varios
 * valores (?atributos={"estado_libro":["Nuevo","Como nuevo"]}), que es cómo
 * se comporta una barra de facetas. Si el atributo del producto es una lista
 * (multiselect), basta con que contenga alguno de los valores pedidos.
 *
 * Un producto sin la key pedida NO pasa el filtro. Es deliberado: "muestra
 * solo lo que acepta mascotas" no debe incluir publicaciones que jamás
 * respondieron esa pregunta, aunque eso castigue a quien no llenó el
 * formulario.
 */
function cumpleAtributos(atributos, criterios) {
  const respuestas = atributos && typeof atributos === 'object' ? atributos : {};
  return Object.entries(criterios).every(([key, esperado]) => {
    const actual = respuestas[key];
    if (actual === undefined || actual === null || actual === '') return false;
    const esperados = Array.isArray(esperado) ? esperado : [esperado];
    const actuales = Array.isArray(actual) ? actual : [actual];

    // String(...) para que "true" del query string case con el booleano
    // guardado, y "95" con un número.
    const actualesTexto = actuales.map(v => String(v));
    return esperados.some(v => actualesTexto.includes(String(v)));
  });
}
async function attachRelations(productsList, userId, {
  includeExpired = false
} = {}) {
  let modified = false;
  const todayStr = new Date().toDateString();
  const visibleProducts = (await Promise.all(productsList.map(async p =>
    (includeExpired || !isExpired(p)) && await db.isSellerPubliclyActive(p.seller)
      ? p
      : null))).filter(Boolean);
  const mapped = await Promise.all(visibleProducts.map(async p => {
    // 1. Reset diario de stock si aplica
    if (p.stock_reset_daily && p.stock_updated_at && p.stock_initial !== null) {
      const lastUpdateStr = new Date(p.stock_updated_at).toDateString();
      if (lastUpdateStr !== todayStr) {
        p.stock_quantity = p.stock_initial;
        p.stock_updated_at = new Date().toISOString();
        modified = true;
      }
    }

    // 2. Campo calculado is_available
    const is_available = p.stock_quantity === null || p.stock_quantity > 0;

    // 3. Calificaciones — persisten en product_ratings, no en el propio producto,
    //    así que hay que unirlas aquí para que sobrevivan a un refresh/GET.
    const ratingStats = await db.getProductRatingStats(p.id);
    const userRating = userId ? await db.getUserProductRating(p.id, userId) : null;
    const sellerObj = sellers.find(s => s.id === p.seller) || (p.seller ? {
      id: p.seller,
      name: p.seller,
      avatarInitials: p.seller.slice(0, 2).toUpperCase(),
      major: '',
      isBusiness: false,
      logoUrl: null,
      // Sin fila en `sellers` el agregado no está cacheado, pero sus
      // productos sí pueden tener calificaciones: se calculan al vuelo.
      ...(await db.getSellerRatingStats(p.seller)),
      verified: false,
      carrera: null,
      tipoVerificacion: null
    } : null);
    const {
      computed_status,
      computed_status_detail
    } = computeProductStatus(p, sellerObj);

    // Respuestas a las preguntas dinámicas de la categoría. Van en TODAS las
    // respuestas de producto (lista, búsqueda, detalle y carruseles) porque
    // las tres pantallas comparten este helper: el detalle las pinta enteras
    // y la tarjeta usa solo `atributosDestacados`, que se resuelve aquí para
    // que ninguna pantalla tenga que opinar sobre cuál es el dato clave de
    // un producto de ropa.
    const atributos = p.atributos && typeof p.atributos === 'object' ? p.atributos : {};
    return {
      ...p,
      status: isExpired(p) ? 'expired' : p.status,
      atributos,
      atributosDestacados: atributosDestacados(atributos, p.category),
      postType: 'producto',
      is_available,
      computed_status,
      computed_status_detail,
      productRating: ratingStats.average,
      productReviews: ratingStats.count,
      userRating,
      sellerObj,
      categoryObj: categories.find(c => c.id === p.category) || null
    };
  }));
  if (modified) await saveData();
  return mapped;
}
function register(app) {
  // Listado privado del dueño. Incluye vencidos porque esta es la pantalla
  // desde la que se administran y renuevan; nunca se mezclan con el feed.
  app.get('/api/products/mine', requireAuth, async (req, res) => {
    const mine = products.filter(p => p.seller === req.user.id);
    res.json(await attachRelations(mine, req.user.id, {
      includeExpired: true
    }));
  });

  // GET /api/products – listar con filtros
  app.get('/api/products', async (req, res) => {
    const {
      category,
      featured,
      offer,
      search,
      seller
    } = req.query;
    let filtered = products.filter(p => !isExpired(p));
    if (category) filtered = filtered.filter(p => p.category === category);
    // TODO: Destacar publicaciones pendiente para próxima actualización - no
    // eliminar. La app ya no manda ?featured=true (ver kDestacarHabilitado en
    // lib/features/highlight/destacar_flag.dart); el filtro se mantiene para
    // clientes viejos.
    if (featured === 'true') filtered = filtered.filter(p => p.isFeatured);
    if (offer === 'true') filtered = filtered.filter(p => p.isOffer);
    if (seller) filtered = filtered.filter(p => p.seller === seller);
    if (search) {
      const q = search.toLowerCase();
      filtered = filtered.filter(p => p.title.toLowerCase().includes(q) || p.description.toLowerCase().includes(q));
    }

    // Filtro por respuestas a las preguntas dinámicas: ?atributos={"talla":"M"}.
    // Un filtro con un JSON inválido se ignora en vez de devolver 400: es un
    // refinamiento opcional de la búsqueda, y dejar al usuario sin resultados
    // por un parámetro mal armado es peor que darle la lista sin refinar.
    if (req.query.atributos) {
      const criterios = parseFiltroAtributos(req.query.atributos);
      if (criterios) {
        filtered = filtered.filter(p => cumpleAtributos(p.atributos, criterios));
      }
    }
    res.json(await attachRelations(filtered, req.query.userId));
  });

  // GET /api/products/:id – detalle
  //
  // Devuelve el producto MÁS los dos carruseles que la pantalla de detalle
  // pinta debajo ("También te puede interesar" y "Más de este vendedor"), en
  // la misma respuesta: son parte del detalle, no una carga aparte, y
  // pedirlos en tres viajes solo serviría para que aparecieran tarde y a
  // destiempo. Son dos consultas con LIMIT, no un recorrido por producto.
  //
  // Ambos arrays pasan por `attachRelations`, el mismo helper que sirve al
  // home y al feed, para que el cliente pueda poblar ProductCard con ellos
  // sin mapear nada distinto. Vacío se devuelve como [] (nunca null): la
  // pantalla decide ocultar la sección con un `isEmpty`, sin más chequeos.
  app.get('/api/products/:id', async (req, res) => {
    const product = products.find(p => p.id === req.params.id);
    if (!product) return res.status(404).json({
      error: 'Producto no encontrado'
    });
    if (!(await db.isSellerPubliclyActive(product.seller))) {
      return res.status(404).json({
        error: 'Producto no encontrado'
      });
    }
    if (isExpired(product)) return res.status(410).json({
      error: 'Esta publicación expiró'
    });
    const userId = req.query.userId;
    const detalle = (await attachRelations([product], userId))[0];
    res.json({
      ...detalle,
      relatedProducts: await attachRelations(await db.getRelatedProducts(product, {
        limit: RELACIONADOS_MAX
      }), userId),
      sellerOtherProducts: await attachRelations(await db.getSellerOtherProducts(product.seller, {
        excludeProductId: product.id,
        limit: RELACIONADOS_MAX
      }), userId)
    });
  });

  // POST /api/products/:id/view – registra una vista de detalle. Conteo
  // simple (no vistas únicas): el cliente ya aplica su propio cooldown para
  // no spamear esto en aperturas repetidas. No cuenta si quien pide es el
  // dueño de la publicación, mismo criterio de "userId" ya usado en
  // calificaciones (product.seller === userId, sin exigir JWT).
  app.post('/api/products/:id/view', async (req, res) => {
    const product = products.find(p => p.id === req.params.id);
    if (!product) return res.status(404).json({
      error: 'Producto no encontrado'
    });
    const userId = req.body?.userId;
    if (!userId || product.seller !== userId) {
      await db.incrementProductViews(product.id);
      // GET /api/products/:id lee del array `products` en memoria (no de
      // SQLite directo), así que hay que reflejar el incremento ahí también
      // o quedaría desactualizado hasta el próximo reinicio del servidor.
      product.views = (product.views || 0) + 3;
      await db.trackCategoryEngagement(product.category, 'product_view');
    }
    res.status(204).end();
  });

  // POST /api/products – crear nuevo producto (con imágenes opcionales)
  // Requiere autenticación; el vendedor se obtiene del JWT, no del body
  app.post('/api/products', requireAuth, async (req, res) => {
    // Se valida antes de que multer escriba fotos temporales: una solicitud
    // rechazada por cupo no debe dejar archivos huérfanos en uploads/.
    const sellerId = req.user.id;
    const sellerRecord = sellers.find(s => s.id === sellerId);
    const policy = await getPublicationPolicy(sellerRecord);
    const now = Date.now();
    const activeProducts = products.filter(p => p.seller === sellerId && !isExpired(p, now) && p.manual_status !== 'sold');
    const rollingWindow = new Date(now - 86400000).toISOString();
    const since = await db.getPublicationLimitSince(sellerId, 'products', rollingWindow);
    const productsToday = await db.countProductsSince(sellerId, since);
    if (productsToday >= policy.productsDaily) {
      return res.status(429).json({
        error: `Ya publicaste el máximo de ${policy.productsDaily} productos hoy`,
        code: 'PRODUCT_DAILY_LIMIT',
        limits: policy
      });
    }
    if (activeProducts.length >= policy.productsActive) {
      return res.status(409).json({
        error: `Ya tienes el máximo de ${policy.productsActive} productos activos`,
        code: 'PRODUCT_ACTIVE_LIMIT',
        limits: policy
      });
    }
    upload.any()(req, res, async err => {
      if (err) {
        return res.status(400).json({
          error: 'Error al procesar imágenes: ' + err.message
        });
      }
      const title = req.body?.title;
      const price = req.body?.price;
      const category = req.body?.category;
      const description = req.body?.description;
      if (!title || !price || !category || !description) {
        return res.status(400).json({
          error: 'Faltan campos requeridos (title, price, category, description)'
        });
      }
      const textos = validarTextos(title, description);
      if (textos.error) return res.status(400).json({
        error: textos.error
      });
      const productId = `p${Date.now()}`;

      // Ubicación puntual de la publicación (Nivel 2): solo cuentas de
      // negocio pueden asociarla, sin importar lo que mande el cliente —
      // defensa en profundidad además del control en la UI.
      let productLocation = null;
      if (sellerRecord?.isBusiness) {
        const locationResult = validateLocation(req.body?.locationLat, req.body?.locationLng);
        if (locationResult.error) {
          return res.status(400).json({
            error: locationResult.error
          });
        }
        productLocation = locationResult.value;
      }

      // Inventario obligatorio. `stock_quantity` NULL significaba "sin
      // límite", y esa opción se retira: un producto que se puede pagar
      // dentro de la app necesita una cantidad contra la que descontar, o se
      // acaba vendiendo algo que ya no existe. Se exige al PUBLICAR y se
      // vuelve a exigir al verificar la cuenta, para los que ya estaban.
      const stockCrudo = req.body?.stock_quantity;
      if (stockCrudo === undefined || stockCrudo === null || stockCrudo === '') {
        return res.status(400).json({
          error: 'Indica cuántas unidades tienes disponibles.',
          campo: 'stock_quantity'
        });
      }
      const stockNum = Number(stockCrudo);
      if (!Number.isInteger(stockNum) || stockNum < 0) {
        return res.status(400).json({
          error: 'La cantidad disponible debe ser un número entero de 0 o más.',
          campo: 'stock_quantity'
        });
      }

      // Métodos de pago de esta publicación (opcional): si no se manda,
      // queda null y el cliente usa los del perfil del vendedor.
      const paymentMethodsResult = validatePaymentMethods(req.body?.paymentMethods);
      if (paymentMethodsResult.error) {
        return res.status(400).json({
          error: paymentMethodsResult.error
        });
      }
      const permitidos = await validarMetodosPermitidos(req.user.id, paymentMethodsResult.value);
      if (permitidos.error) return res.status(400).json({
        error: permitidos.error
      });
      const productPaymentMethods = paymentMethodsResult.value;

      // Preguntas dinámicas de la categoría. Se validan contra el catálogo
      // del servidor y NO contra lo que diga el cliente: un valor fuera de
      // las `options` declaradas se rechaza, porque guardarlo dejaría un
      // producto con un dato que ninguna pantalla sabe pintar. Se valida
      // aquí, antes de convertir imágenes, para no dejar archivos escritos
      // en disco por una petición que va a fallar de todos modos.
      const atributosResult = validarAtributosCategoria(req.body?.atributos, category);
      if (atributosResult.error) {
        return res.status(400).json({
          error: atributosResult.error,
          ...(atributosResult.campo ? {
            campo: atributosResult.campo
          } : {})
        });
      }
      const productAtributos = atributosResult.value;

      // Convertir cada imagen a WebP usando Promise.all
      const conversionPromises = (req.files || []).map(async file => {
        return (await convertToWebp(file.path)).catch(convErr => {
          console.error('Error convirtiendo a WebP:', convErr);
          fs.unlink(file.path, () => {});
          throw new Error('Una imagen no tiene un formato válido.');
        });
      });
      Promise.all(conversionPromises).then(async images => {
        // Segunda comprobación después del trabajo asíncrono de imágenes.
        // Dos publicaciones simultáneas pueden pasar juntas el chequeo
        // inicial; esta barrera serial (JS ejecuta este bloque de una en
        // una) impide que ambas rebasen el último lugar disponible.
        const finalNow = Date.now();
        const finalActive = products.filter(p => p.seller === sellerId && !isExpired(p, finalNow) && p.manual_status !== 'sold').length;
        const finalToday = products.filter(p => p.seller === sellerId && new Date(p.created_at || 0).getTime() >= finalNow - 86400000).length;
        if (finalToday >= policy.productsDaily || finalActive >= policy.productsActive) {
          for (const imagePath of images) {
            fs.unlink(path.join(UPLOADS_DIR, path.basename(imagePath)), () => {});
          }
          const dailyReached = finalToday >= policy.productsDaily;
          return res.status(dailyReached ? 429 : 409).json({
            error: dailyReached ? `Ya publicaste el máximo de ${policy.productsDaily} productos hoy` : `Ya tienes el máximo de ${policy.productsActive} productos activos`,
            code: dailyReached ? 'PRODUCT_DAILY_LIMIT' : 'PRODUCT_ACTIVE_LIMIT',
            limits: policy
          });
        }
        const priceNum = Number(price);
        const extrasInput = normalizeExtras(req.body?.extras);
        const availableDays = normalizeAvailableDays(req.body?.availableDays);
        const categoryObj = categories.find(c => c.id === category);
        const newProduct = {
          id: productId,
          title,
          price: !isNaN(priceNum) && priceNum > 0 ? priceNum : 0,
          category,
          description,
          publishedAgo: 'Ahora mismo',
          seller: sellerId,
          images,
          imageIcon: images.length > 0 ? null : categoryObj?.icon || 'category',
          imageColor: categoryObj?.color || '#607D8B',
          manual_status: null,
          extras: extrasInput,
          isFeatured: false,
          isOffer: false,
          isFavorite: false,
          stock_quantity: stockNum,
          stock_reset_daily: req.body?.stock_reset_daily === 'true' || req.body?.stock_reset_daily === true,
          stock_initial: req.body?.stock_initial !== undefined ? Number(req.body.stock_initial) : stockNum,
          stock_updated_at: new Date().toISOString(),
          availableDays,
          locationLat: productLocation ? productLocation.lat : null,
          locationLng: productLocation ? productLocation.lng : null,
          paymentMethods: productPaymentMethods,
          atributos: productAtributos || {},
          created_at: new Date().toISOString(),
          expiresAt: expiresAtFromNow(policy.durationDays)
        };
        products.unshift(newProduct);
        await saveData();
        await db.trackCategoryEngagement(category, 'publish');

        // ─── Retargeting por interés ─────────────────────────────
        // Antes esto notificaba aquí mismo, en el acto y sin ningún
        // límite, a TODOS los seguidores de la categoría. Ahora solo se
        // encola: quién lo recibe y cuándo lo deciden el scoring de
        // interés y las reglas de frecuencia en notifications/retargeting,
        // que además agrupa varias publicaciones seguidas en un solo
        // aviso. Los seguidores explícitos de la categoría siguen
        // entrando, como candidatos permanentes.
        await encolarProducto(productId);
        res.status(201).json((await attachRelations([newProduct]))[0]);
      }).catch(err => {
        console.error('Error en POST /api/products:', err);
        res.status(500).json({
          error: err.message
        });
      });
    });
  });

  // Renovar equivale a una publicación nueva para el cupo diario y la
  // recencia del feed. Solo se permite cuando la vigencia realmente acabó.
  app.post('/api/products/:id/renew', requireAuth, async (req, res) => {
    const product = products.find(p => p.id === req.params.id);
    if (!product) return res.status(404).json({
      error: 'Producto no encontrado'
    });
    if (product.seller !== req.user.id) {
      return res.status(403).json({
        error: 'No tienes permiso para renovar este producto'
      });
    }
    if (!isExpired(product)) {
      return res.status(400).json({
        error: 'Este producto todavía está vigente'
      });
    }
    const seller = sellers.find(s => s.id === req.user.id);
    const policy = await getPublicationPolicy(seller);
    const now = Date.now();
    const active = products.filter(p => p.seller === req.user.id && p.id !== product.id && !isExpired(p, now) && p.manual_status !== 'sold').length;
    const publishedToday = products.filter(p => p.seller === req.user.id && p.id !== product.id && new Date(p.created_at || 0).getTime() >= now - 86400000).length;
    if (publishedToday >= policy.productsDaily) {
      return res.status(429).json({
        error: `Ya alcanzaste el máximo de ${policy.productsDaily} publicaciones nuevas o renovadas hoy`,
        code: 'PRODUCT_DAILY_LIMIT',
        limits: policy
      });
    }
    if (active >= policy.productsActive) {
      return res.status(409).json({
        error: `Ya tienes el máximo de ${policy.productsActive} productos activos`,
        code: 'PRODUCT_ACTIVE_LIMIT',
        limits: policy
      });
    }
    product.created_at = new Date(now).toISOString();
    product.expiresAt = expiresAtFromNow(policy.durationDays);
    product.status = null;
    product.manual_status = null;
    product.publishedAgo = 'Ahora mismo';
    await saveData();
    res.json({
      product: (await attachRelations([product], req.user.id))[0],
      message: `Producto renovado por ${policy.durationDays} días`,
      durationDays: policy.durationDays
    });
  });

  // PUT /api/products/:id – editar campos generales (solo el dueño)
  // title, description, category, images, extras, availableDays.
  // Precio/stock/status/featured siguen editándose por sus propios endpoints,
  // que ya tienen su lógica especial (anti-fraude, reset diario, etc).
  app.put('/api/products/:id', requireAuth, (req, res) => {
    upload.any()(req, res, async err => {
      if (err) {
        return res.status(400).json({
          error: 'Error al procesar imágenes: ' + err.message
        });
      }
      try {
        const product = products.find(p => p.id === req.params.id);
        if (!product) {
          return res.status(404).json({
            error: 'Producto no encontrado'
          });
        }
        if (product.seller !== req.user.id) {
          return res.status(403).json({
            error: 'No tienes permiso para editar este producto'
          });
        }
        const title = req.body?.title;
        const category = req.body?.category;
        const description = req.body?.description;

        // Misma validación que la creación (POST /api/products), salvo precio:
        // el precio NO se toca aquí. Tiene su propio flujo con historial,
        // cooldown de 72h y rate limit en PATCH /api/products/:id, que no
        // queremos poder saltarnos editando el título/descripción a la vez.
        if (!title || !category || !description) {
          return res.status(400).json({
            error: 'Faltan campos requeridos (title, category, description)'
          });
        }
        const textos = validarTextos(title, description);
        if (textos.error) return res.status(400).json({
          error: textos.error
        });
        if (!categories.some(c => c.id === category)) {
          return res.status(400).json({
            error: 'Categoría inválida'
          });
        }
        const categoryObj = categories.find(c => c.id === category);

        // Métodos de pago de esta publicación (opcional): si se manda
        // (incluso como arreglo vacío), reemplaza el override; un arreglo
        // vacío se normaliza a null (vuelve a heredar los del perfil).
        let paymentMethodsUpdate;
        if (req.body.paymentMethods !== undefined) {
          const paymentMethodsResult = validatePaymentMethods(req.body.paymentMethods);
          if (paymentMethodsResult.error) {
            return res.status(400).json({
              error: paymentMethodsResult.error
            });
          }
          const permitidos = await validarMetodosPermitidos(req.user.id, paymentMethodsResult.value);
          if (permitidos.error) return res.status(400).json({
            error: permitidos.error
          });
          paymentMethodsUpdate = paymentMethodsResult.value;
        }

        // Preguntas dinámicas: se validan contra la categoría NUEVA, que es
        // la que va a quedar guardada. Si el vendedor cambió de categoría,
        // las respuestas que solo existían en la anterior se caen solas (la
        // normalización recorre las preguntas de la categoría destino), que
        // es lo correcto: una talla no significa nada en un producto que
        // acaba de volverse "Electrónicos".
        //
        // Como el objeto se reemplaza entero, mandar el campo omitiendo una
        // respuesta la borra; no mandarlo deja los atributos intactos.
        let atributosUpdate;
        if (req.body.atributos !== undefined) {
          const atributosResult = validarAtributosCategoria(req.body.atributos, category);
          if (atributosResult.error) {
            return res.status(400).json({
              error: atributosResult.error,
              ...(atributosResult.campo ? {
                campo: atributosResult.campo
              } : {})
            });
          }
          atributosUpdate = atributosResult.value || {};
        } else if (category !== product.category) {
          // Cambió de categoría sin mandar respuestas nuevas: revalidar las
          // que ya tenía contra el catálogo destino, o quedarían atributos
          // de la categoría vieja colgando en el producto para siempre.
          atributosUpdate = validarAtributosCategoria(product.atributos, category).value || {};
        }

        // ─── Imágenes: existingImages son las URLs que el usuario decide
        // conservar; todo lo que estaba en product.images y no aparece ahí
        // se considera eliminado. Los archivos nuevos vienen en req.files.
        let existingImagesInput = req.body?.existingImages;
        if (typeof existingImagesInput === 'string') {
          try {
            existingImagesInput = JSON.parse(existingImagesInput);
          } catch {
            existingImagesInput = [];
          }
        }
        const keptImages = Array.isArray(existingImagesInput) ? existingImagesInput.filter(url => product.images.includes(url)) : product.images; // si no mandan el campo, no se toca ninguna imagen

        const conversionPromises = (req.files || []).map(async file => {
          return (await convertToWebp(file.path)).catch(convErr => {
            console.error('Error convirtiendo a WebP:', convErr);
            fs.unlink(file.path, () => {});
            throw new Error('Una imagen no tiene un formato válido.');
          });
        });
        Promise.all(conversionPromises).then(async newImages => {
          const finalImages = [...keptImages, ...newImages];
          const removedImages = product.images.filter(url => !finalImages.includes(url));

          // Actualizamos primero el producto (única escritura atómica en
          // SQLite); solo si eso tiene éxito borramos del disco las
          // imágenes viejas. Así, si algo falla antes de guardar, no se
          // pierde ninguna imagen todavía referenciada por el producto.
          product.title = title.trim();
          product.description = description;
          product.category = category;
          product.images = finalImages;
          product.imageIcon = finalImages.length > 0 ? null : categoryObj?.icon || 'category';
          product.imageColor = categoryObj?.color || '#607D8B';
          if (req.body.extras !== undefined) {
            product.extras = normalizeExtras(req.body.extras);
          }
          if (req.body.availableDays !== undefined) {
            product.availableDays = normalizeAvailableDays(req.body.availableDays);
          }
          if (atributosUpdate !== undefined) {
            product.atributos = atributosUpdate;
          }
          if (paymentMethodsUpdate !== undefined) {
            product.paymentMethods = paymentMethodsUpdate;
          }
          product.updated_at = new Date().toISOString().replace('T', ' ').slice(0, 19);
          await saveData();
          for (const imgUrl of removedImages) {
            const filePath = path.join(UPLOADS_DIR, path.basename(imgUrl));
            if (fs.existsSync(filePath)) {
              try {
                fs.unlinkSync(filePath);
              } catch (unlinkErr) {
                console.error('No se pudo borrar imagen huérfana:', imgUrl, unlinkErr);
              }
            }
          }
          res.json((await attachRelations([product]))[0]);
        }).catch(convErr => {
          console.error('Error en PUT /api/products/:id (conversión de imágenes):', convErr);
          res.status(500).json({
            error: 'No se pudieron procesar las imágenes nuevas. Intenta de nuevo.'
          });
        });
      } catch (err) {
        console.error('Error en PUT /api/products/:id:', err);
        res.status(500).json({
          error: 'No se pudo actualizar el producto. Intenta de nuevo en unos minutos.'
        });
      }
    });
  });

  // DELETE /api/products/:id – eliminar producto (solo el dueño)
  app.delete('/api/products/:id', requireAuth, async (req, res) => {
    try {
      const productId = req.params.id;
      const productIndex = products.findIndex(p => p.id === productId);
      if (productIndex === -1) {
        return res.status(404).json({
          error: 'Producto no encontrado'
        });
      }
      const product = products[productIndex];
      if (product.seller !== req.user.id) {
        return res.status(403).json({
          error: 'No tienes permiso para eliminar este producto'
        });
      }

      // Eliminar imágenes del disco
      if (product.images && product.images.length > 0) {
        for (const imgUrl of product.images) {
          const filename = path.basename(imgUrl);
          const filePath = path.join(UPLOADS_DIR, filename);
          if (fs.existsSync(filePath)) {
            fs.unlinkSync(filePath);
          }
        }
      }
      products.splice(productIndex, 1);
      await db.deleteProduct(productId);

      // El CASCADE se llevó las calificaciones de este producto, así que el
      // agregado del vendedor cambió: hay que rehacer el caché o quedaría
      // contando reseñas que ya no existen.
      const sellerStats = await db.syncSellerRating(product.seller);
      const sellerIndex = sellers.findIndex(s => s.id === product.seller);
      if (sellerIndex !== -1) {
        sellers[sellerIndex].rating = sellerStats.rating;
        sellers[sellerIndex].reviews = sellerStats.reviews;
      }
      await saveData();
      res.json({
        success: true,
        message: 'Producto eliminado'
      });
    } catch (err) {
      console.error('Error en DELETE /api/products/:id:', err);
      res.status(500).json({
        error: err.message
      });
    }
  });

  // PATCH /api/products/:id/status – activar/quitar un estado manual (solo dueño).
  // 'available'/'unavailable' ya no son valores aceptados: el badge de
  // "disponible" o "no disponible" es siempre calculado (ver
  // computeProductStatus), nunca una elección manual. Mandar status: null
  // "reactiva" el producto, volviéndolo al cálculo automático.
  app.patch('/api/products/:id/status', requireAuth, async (req, res) => {
    try {
      const product = products.find(p => p.id === req.params.id);
      if (!product) return res.status(404).json({
        error: 'Producto no encontrado'
      });
      if (product.seller !== req.user.id) {
        return res.status(403).json({
          error: 'No tienes permiso para cambiar el estado de este producto'
        });
      }
      const {
        status
      } = req.body;
      if (status !== null && !MANUAL_STATUSES.includes(status)) {
        return res.status(400).json({
          error: 'Estado inválido. Valores válidos: ' + MANUAL_STATUSES.join(', ') + ', o null para reactivar'
        });
      }
      product.manual_status = status;

      // Si se marca como vendido, la oferta expira automáticamente
      if (status === 'sold' && product.isOffer) {
        product.isOffer = false;
        product.previousPrice = null;
        product.discountLabel = null;
        product.offerExpiresAt = null;
      }
      await saveData();
      res.json((await attachRelations([product]))[0]);
    } catch (err) {
      console.error('Error en PATCH /api/products/:id/status:', err);
      res.status(500).json({
        error: err.message
      });
    }
  });

  // PATCH /api/products/:id/stock – ajustar inventario manualmente
  app.patch('/api/products/:id/stock', requireAuth, async (req, res) => {
    try {
      const product = products.find(p => p.id === req.params.id);
      if (!product) return res.status(404).json({
        error: 'Producto no encontrado'
      });
      if (product.seller !== req.user.id) {
        return res.status(403).json({
          error: 'No tienes permiso para cambiar el stock de este producto'
        });
      }
      const {
        decrement,
        set
      } = req.body;
      if (product.stock_quantity === null) {
        // Si era ilimitado pero mandan 'set', lo convertimos a limitado
        if (set !== undefined) {
          product.stock_quantity = Math.max(0, Number(set));
        } else {
          return res.status(400).json({
            error: 'El producto no tiene límite de stock (es NULL)'
          });
        }
      } else {
        if (set !== undefined) {
          product.stock_quantity = Math.max(0, Number(set));
        } else if (decrement !== undefined) {
          product.stock_quantity = Math.max(0, product.stock_quantity - Number(decrement));
        } else {
          return res.status(400).json({
            error: 'Debes enviar "decrement" o "set" en el body'
          });
        }
      }
      if (req.body.stock_reset_daily !== undefined) {
        product.stock_reset_daily = req.body.stock_reset_daily === true || req.body.stock_reset_daily === 'true';
      }
      if (set !== undefined) {
        // Al fijar un nuevo stock manualmente (edición), ese valor pasa a
        // ser también la referencia para el reinicio diario automático.
        product.stock_initial = product.stock_quantity;
      }
      product.stock_updated_at = new Date().toISOString();

      // El badge "Agotado" ya no se persiste en status: se calcula en cada
      // lectura a partir de stock_quantity (ver computeProductStatus). Solo
      // se conserva el efecto secundario de expirar la oferta al agotarse,
      // que es un concepto de precio, no de disponibilidad.
      if (product.stock_quantity === 0 && product.isOffer) {
        product.isOffer = false;
        product.previousPrice = null;
        product.discountLabel = null;
        product.offerExpiresAt = null;
      }
      await saveData();
      res.json((await attachRelations([product]))[0]);
    } catch (err) {
      console.error('Error en PATCH /api/products/:id/stock:', err);
      res.status(500).json({
        error: err.message
      });
    }
  });

  // PATCH /api/products/:id/favorite – toggle favorito
  app.patch('/api/products/:id/favorite', async (req, res) => {
    const product = products.find(p => p.id === req.params.id);
    if (!product) return res.status(404).json({
      error: 'Producto no encontrado'
    });
    product.isFavorite = !product.isFavorite;
    await saveData();
    res.json((await attachRelations([product]))[0]);
  });

  // PATCH /api/products/:id/featured – toggle destacado (solo el dueño)
  //
  // TODO: Destacar publicaciones pendiente para próxima actualización - no
  // eliminar. Ningún cliente actual lo llama (el botón "Destacar" está oculto
  // tras kDestacarHabilitado, ver lib/features/highlight/destacar_flag.dart).
  // Se deja activo porque sigue siendo la única forma de QUITAR el destacado
  // a las publicaciones que ya lo tienen en la base.
  app.patch('/api/products/:id/featured', requireAuth, async (req, res) => {
    const product = products.find(p => p.id === req.params.id);
    if (!product) return res.status(404).json({
      error: 'Producto no encontrado'
    });
    if (product.seller !== req.user.id) {
      return res.status(403).json({
        error: 'No tienes permiso para destacar este producto'
      });
    }
    product.isFeatured = !product.isFeatured;
    await saveData();
    res.json((await attachRelations([product]))[0]);
  });

  // PATCH /api/products/:id/days – editar días disponibles (solo el dueño)
  app.patch('/api/products/:id/days', requireAuth, async (req, res) => {
    const product = products.find(p => p.id === req.params.id);
    if (!product) return res.status(404).json({
      error: 'Producto no encontrado'
    });
    if (product.seller !== req.user.id) {
      return res.status(403).json({
        error: 'No tienes permiso para editar este producto'
      });
    }
    const {
      availableDays
    } = req.body;
    if (!Array.isArray(availableDays)) {
      return res.status(400).json({
        error: 'El campo "availableDays" debe ser un arreglo'
      });
    }
    product.availableDays = normalizeAvailableDays(availableDays);
    await saveData();
    res.json((await attachRelations([product]))[0]);
  });

  // PATCH /api/products/:id – editar precio (solo el dueño)
  // Incluye: historial de precios, umbral mínimo 5%, rate limit, expiración de oferta
  app.patch('/api/products/:id', requireAuth, async (req, res) => {
    try {
      const product = products.find(p => p.id === req.params.id);
      if (!product) return res.status(404).json({
        error: 'Producto no encontrado'
      });
      if (product.seller !== req.user.id) {
        return res.status(403).json({
          error: 'No tienes permiso para editar este producto'
        });
      }
      const {
        price
      } = req.body;

      // Solo procesamos si viene un precio (el endpoint es específico para editar precio)
      if (price === undefined) {
        return res.status(400).json({
          error: 'El campo "price" es requerido'
        });
      }
      const newPrice = Number(price);

      // ─── Validaciones ──────────────────────────────────────
      if (!Number.isFinite(newPrice) || newPrice <= 0) {
        return res.status(400).json({
          error: 'El precio debe ser un número positivo mayor a cero'
        });
      }

      // ─── Extras opcionales ─────────────────────────────────
      if (req.body.extras !== undefined) {
        product.extras = normalizeExtras(req.body.extras);
      }

      // ─── Rate limit: máximo 3 ediciones por hora ────────────
      const editsInLastHour = await db.countPriceEditsLastHour(product.id);
      if (editsInLastHour >= 3) {
        return res.status(429).json({
          error: 'Has alcanzado el límite de ediciones de precio (3 por hora). Intenta más tarde.'
        });
      }
      const oldPrice = typeof product.price === 'number' ? product.price : parseFloat(String(product.price || '0').replace(/[^0-9.]/g, '')) || 0;

      // ─── Cooldown anti-abuso (72 horas) ──────────────────────
      // Revisar cuánto tiempo estuvo activo el precio anterior
      const lastChange = await db.getLastPriceChange(product.id);
      let previousActiveHours = Infinity; // Si es el precio inicial sin historial previo

      if (lastChange && lastChange.changed_at) {
        const lastTime = new Date(lastChange.changed_at).getTime();
        previousActiveHours = (Date.now() - lastTime) / (1000 * 60 * 60);
      }
      const isCooldownPassed = previousActiveHours >= COOLDOWN_HOURS;

      // ─── Registrar en price_history el precio anterior ANTES de aplicar el nuevo ───
      // Si por algún motivo no tenemos un precio anterior numérico válido, omitimos
      // el registro de historial en vez de arriesgar un insert inválido.
      if (Number.isFinite(oldPrice)) {
        await db.insertPriceHistory(product.id, oldPrice);
      } else {
        console.warn(`Omitiendo price_history para ${product.id}: oldPrice no es un número válido (${oldPrice})`);
      }

      // ─── Calcular descuento contra el precio inmediatamente anterior ──────
      // La referencia es `oldPrice` y NADA más. Antes se usaba
      // `Math.max(oldPrice, máximo de los últimos 30 días)`, y ese máximo
      // actuaba como un techo que nunca bajaba: un producto que llegó a
      // $11,000, cayó a $5 y se volvió a subir a $7,500 entraba aquí como
      // "oferta de -32%" — el dueño había SUBIDO el precio. Comparar contra
      // el precio que el producto tenía justo antes de esta edición es lo
      // único que hace que "bajó de precio" signifique lo que dice.
      //
      // El historial sigue alimentando el cooldown y el rate limit de arriba,
      // que son sus usos legítimos.
      const referencePrice = oldPrice;
      if (isCooldownPassed && newPrice < referencePrice && referencePrice > 0) {
        const discountPercent = Math.round((1 - newPrice / referencePrice) * 100);
        if (discountPercent >= 5) {
          // ✅ Activar oferta (cooldown cumplido)
          product.isOffer = true;
          product.previousPrice = referencePrice;
          product.discountLabel = `-${discountPercent}%`;
          const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
          product.offerExpiresAt = expiresAt;
        } else {
          product.isOffer = false;
          product.previousPrice = null;
          product.discountLabel = null;
          product.offerExpiresAt = null;
        }
      } else {
        // Cooldown NO cumplido o precio mayor/igual → no se marca como oferta
        product.isOffer = false;
        product.previousPrice = null;
        product.discountLabel = null;
        product.offerExpiresAt = null;
      }

      // ─── Actualizar precio y stock (si aplica) ─────────────
      product.price = newPrice;
      product.publishedAgo = 'Editado ahora';
      if (req.body.stock_quantity !== undefined) {
        product.stock_quantity = Number(req.body.stock_quantity);
        product.stock_reset_daily = req.body.stock_reset_daily === 'true' || req.body.stock_reset_daily === true;
        product.stock_initial = req.body.stock_initial !== undefined ? Number(req.body.stock_initial) : null;
        product.stock_updated_at = new Date().toISOString();
      }
      await saveData();

      // ─── Notificar push si el producto se marcó como oferta / bajada de precio ───
      if (product.isOffer) {
        const interestedUsers = await db.getUsersInterestedInCategory(product.category);
        const notifyUsers = interestedUsers.filter(u => u !== req.user.id);
        if (notifyUsers.length > 0) {
          const notifTitle = `🔥 Bajó de precio: ${product.title}`;
          const notifBody = `¡Ahora a solo $${newPrice}! ${product.discountLabel || ''}`;
          for (const targetUserId of notifyUsers) {
            const notifId = `notif_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
            await db.createNotification(notifId, targetUserId, 'price_drop', notifTitle, notifBody, {
              productId: product.id
            });
          }
          await sendPush(notifyUsers, notifTitle, notifBody, {
            productId: product.id,
            type: 'price_drop'
          });
        }
      }
      res.json((await attachRelations([product]))[0]);
    } catch (err) {
      console.error('Error en PATCH /api/products/:id:', err);
      res.status(500).json({
        error: 'No se pudo actualizar el producto. Intenta de nuevo en unos minutos.'
      });
    }
  });

  // Cuenta o invitado: en ambos casos la identidad sale del JWT firmado.
  app.post('/api/products/:id/rate', requireAuth, async (req, res) => {
    try {
      const productId = req.params.id;
      const product = products.find(p => p.id === productId);
      if (!product) return res.status(404).json({
        error: 'Producto no encontrado'
      });
      const {
        stars
      } = req.body;
      const userId = req.user.id;
      if (!stars || stars < 1 || stars > 5) {
        return res.status(400).json({
          error: 'stars debe ser un número entre 1 y 5'
        });
      }

      // No puedes calificar tu propio producto
      if (product.seller === userId) {
        return res.status(403).json({
          error: 'No puedes calificar tu propio producto'
        });
      }
      await db.upsertProductRating(productId, userId, stars);

      // Recalcular el agregado del vendedor sobre TODOS sus productos y
      // persistirlo. Escribir solo el array en memoria no basta: saveData() no
      // toca la tabla sellers, así que el promedio se perdía en cada reinicio y
      // toda lectura seguía devolviendo el valor viejo de la columna.
      const sellerStats = await db.syncSellerRating(product.seller);
      const sellerIndex = sellers.findIndex(s => s.id === product.seller);
      if (sellerIndex !== -1) {
        sellers[sellerIndex].rating = sellerStats.rating;
        sellers[sellerIndex].reviews = sellerStats.reviews;
      }

      // Notificar al vendedor de la nueva calificación por push
      if (product.seller && product.seller !== userId) {
        const notifTitle = `⭐ Nueva calificación`;
        const notifBody = `Calificaron tu producto "${product.title}" con ${stars} estrella${stars > 1 ? 's' : ''}`;
        const notifId = `notif_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
        await db.createNotification(notifId, product.seller, 'rating', notifTitle, notifBody, {
          productId: product.id
        });
        await sendPush([product.seller], notifTitle, notifBody, {
          productId: product.id,
          type: 'rating'
        });
      }
      const enriched = (await attachRelations([product], userId))[0];
      await saveData();
      res.json(enriched);
    } catch (err) {
      console.error('Error en POST /api/products/:id/rate:', err);
      res.status(500).json({
        error: err.message
      });
    }
  });

  // GET /api/products/:id/price-history – consultar historial y precio más bajo de 30 días
  app.get('/api/products/:id/price-history', async (req, res) => {
    try {
      const productId = req.params.id;
      const product = products.find(p => p.id === productId);
      if (!product) return res.status(404).json({
        error: 'Producto no encontrado'
      });
      const currentPrice = typeof product.price === 'number' ? product.price : parseFloat(String(product.price || '0').replace(/[^0-9.]/g, '')) || 0;
      const lowest30d = await db.getLowestPriceInLastDays(productId, currentPrice, 30);
      const rawHistory = await db.getPriceHistoryList(productId, 30);
      res.json({
        lowest_30d: lowest30d,
        current_price: currentPrice,
        history: rawHistory.map(h => ({
          price: h.price,
          changed_at: h.changed_at
        }))
      });
    } catch (err) {
      console.error('Error en GET /api/products/:id/price-history:', err);
      res.status(500).json({
        error: 'No se pudo cargar el historial de precios.'
      });
    }
  });
}
module.exports = {
  register,
  attachRelations
};
