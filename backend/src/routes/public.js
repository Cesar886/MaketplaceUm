// API pública de solo lectura — la consume el sitio web (carpeta /website),
// que renderiza la vista de un producto para quien abre un link compartido
// SIN tener la app instalada.
//
// Existe aparte de `GET /api/products/:id` a propósito, y no es duplicación:
// ese endpoint devuelve el producto entero con `sellerObj` completo, y
// `rowToSeller` incluye el TELÉFONO del vendedor deliberadamente (para el
// botón de WhatsApp dentro de la app, ver database.js). Publicar eso en una
// página indexable convertiría el catálogo en un directorio de teléfonos
// raspable. Aquí se arma la respuesta con una LISTA BLANCA de campos: lo que
// no se nombra explícitamente no sale, así que agregar mañana una columna
// nueva a `products` o a `sellers` no la filtra sola.

const express = require('express');
const rateLimit = require('express-rate-limit');

// El sitio hace una petición por visita de producto, desde el servidor de
// Vercel. Ese fetch sale de un puñado de IPs compartidas, así que el límite
// se cuenta por IP pero con margen: lo que se busca frenar es el raspado del
// catálogo entero, no el tráfico normal de varias visitas simultáneas.
const VENTANA_MINUTOS = 1;
const MAX_PETICIONES = 60;

/**
 * Proyección pública de un producto. Solo estos campos salen a la web.
 *
 * Deliberadamente FUERA: teléfono, correo y cualquier dato de contacto del
 * vendedor (se reservan para dentro de la app), y también `views`, los
 * contadores internos y el historial de precios.
 */
function aVistaPublica(producto) {
  const vendedor = producto.sellerObj;

  return {
    // Discrimina la forma de la respuesta. Productos y búsquedas comparten la
    // URL /producto/:id (el botón de compartir de la app es el mismo para
    // ambos), así que el sitio necesita saber cuál de las dos recibió antes
    // de intentar leer `precio` o `fotos`.
    tipo: 'producto',
    id: producto.id,
    titulo: producto.title,
    descripcion: producto.description,
    precio: producto.price,
    precioAnterior: producto.previousPrice ?? null,
    etiquetaDescuento: producto.discountLabel ?? null,
    categoria: producto.categoryObj
      ? { id: producto.categoryObj.id, nombre: producto.categoryObj.name }
      : null,
    // Rutas relativas tal como las guarda el backend ('/uploads/x.webp'). El
    // sitio las vuelve absolutas con su propia URL de API — así este endpoint
    // no tiene que saber bajo qué dominio se le está sirviendo.
    fotos: Array.isArray(producto.images) ? producto.images : [],
    // Estado ya calculado por computeProductStatus (jerarquía de 5 niveles).
    // El sitio solo lo pinta; no reimplementa la lógica.
    estado: producto.computed_status,
    estadoDetalle: producto.computed_status_detail ?? null,
    disponible: !!producto.is_available,
    publicadoHace: producto.publishedAgo ?? null,
    ubicacion: aUbicacionPublica(producto, vendedor),
    vendedor: aVendedorPublico(vendedor),
  };
}

/**
 * Ubicación solo si quien publica es un negocio: un particular no debe quedar
 * geolocalizado en una página pública indexable.
 */
function aUbicacionPublica(publicacion, vendedor) {
  const tieneCoordenadas =
    publicacion.locationLat != null && publicacion.locationLng != null;

  if (!vendedor || !vendedor.isBusiness || !tieneCoordenadas) return null;
  return { lat: publicacion.locationLat, lng: publicacion.locationLng };
}

/**
 * Lista blanca de quien publica. Deliberadamente FUERA: `id` (identifica la
 * cuenta y permite cruzarla entre publicaciones), teléfono y correo.
 */
function aVendedorPublico(vendedor) {
  if (!vendedor) return null;

  return {
    nombre: vendedor.name,
    iniciales: vendedor.avatarInitials || '',
    // Ruta relativa igual que `fotos` en `aVistaPublica` ('/uploads/x.webp'):
    // el sitio la vuelve absoluta con `urlFoto`, no con la URL interna de la
    // API. Mismo campo que `logoUrl` usa la app para el avatar circular.
    avatarUrl: vendedor.logoUrl || null,
    esNegocio: !!vendedor.isBusiness,
    verificado: !!vendedor.verified,
    tipoCuenta: vendedor.tipoCuenta || null,
    // Mismos dos campos que usa el subtítulo de rol en la app
    // (lib/widgets/user_role.dart), para que la web muestre el mismo texto
    // bajo el nombre y no se desincronicen.
    carrera: vendedor.carrera || null,
    tipoVerificacion: vendedor.tipoVerificacion || null,
  };
}

/**
 * Proyección pública de una publicación "se busca".
 *
 * Es una función aparte y no un `if` dentro de `aVistaPublica` porque los
 * datos no se solapan: una búsqueda no tiene fotos, ni precio único, ni el
 * estado calculado de disponibilidad. Colapsarlas produciría un objeto lleno
 * de campos nulos donde el sitio no podría distinguir "no aplica" de "falta".
 *
 * Deliberadamente FUERA: `userId` y `resolvedWithUserId` (identifican cuentas
 * y publicarlos deja reconstruir desde fuera quién le compró a quién), los
 * métodos de pago y el contador de vistas.
 */
function aVistaPublicaBusqueda(busqueda) {
  const publicante = busqueda.sellerObj;

  return {
    tipo: 'busqueda',
    id: busqueda.id,
    titulo: busqueda.title,
    descripcion: busqueda.description || '',
    // Rango, no precio: es lo que la persona está dispuesta a pagar. Cualquiera
    // de los dos extremos puede faltar (se pide "hasta X" o "desde Y").
    precioMin: busqueda.priceMin ?? null,
    precioMax: busqueda.priceMax ?? null,
    // 'producto' | 'servicio' — cambia el texto de la página ("Busca comprar"
    // vs "Busca contratar").
    busca: busqueda.type,
    categoria: busqueda.categoryObj
      ? { id: busqueda.categoryObj.id, nombre: busqueda.categoryObj.name }
      : null,
    // Una búsqueda resuelta sigue siendo visible (el link compartido no debe
    // romperse), pero la página tiene que dejar claro que ya no está activa.
    abierta: busqueda.status === 'abierta',
    // ISO crudo: a diferencia de `publishedAgo` en productos, que es un texto
    // congelado al crear, aquí la fecha real deja que el sitio calcule la
    // antigüedad al momento de renderizar.
    publicadoEn: busqueda.createdAt ?? null,
    ubicacion: aUbicacionPublica(busqueda, publicante),
    vendedor: aVendedorPublico(publicante),
  };
}

function register(app) {
  const db = require('../database');
  const { products } = require('../data');
  const { attachRelations } = require('./products');
  const { attachWantedRelations } = require('./wanted');

  const router = express.Router();

  router.use(
    rateLimit({
      windowMs: VENTANA_MINUTOS * 60 * 1000,
      limit: MAX_PETICIONES,
      standardHeaders: 'draft-7',
      legacyHeaders: false,
      message: { error: 'Demasiadas peticiones. Inténtalo en un minuto.' },
    }),
  );

  // GET /api/public/productos — SOLO ids y fecha, para el sitemap del sitio.
  //
  // No devuelve el contenido de los productos a propósito: un listado
  // completo y sin paginar es exactamente el volcado de catálogo que el rate
  // limit intenta evitar. Con esto el sitemap se arma sin abrir esa puerta.
  router.get('/productos', (_req, res) => {
    // Las búsquedas van en la misma lista porque comparten la ruta del sitio
    // (/producto/:id): separarlas obligaría al sitemap a pedir dos veces para
    // armar URLs idénticas. Solo las abiertas — una búsqueda ya resuelta no
    // debe empujarse al índice, aunque su link compartido siga funcionando.
    const busquedas = db.listWantedPosts({ status: 'abierta' });

    res.json({
      productos: [
        ...products.map(p => ({
          id: p.id,
          actualizado: p.updated_at || p.created_at || null,
        })),
        ...busquedas.map(b => ({
          id: b.id,
          actualizado: b.updatedAt || b.createdAt || null,
        })),
      ],
    });
  });

  // GET /api/public/productos/:id
  router.get('/productos/:id', (req, res) => {
    const producto = products.find(p => p.id === req.params.id);

    if (producto) {
      // attachRelations es lo que resuelve sellerObj, categoryObj y el estado
      // calculado. Se reusa en vez de recalcularlo aquí para que la web no se
      // desincronice de la app cuando cambien las reglas de disponibilidad.
      const completo = attachRelations([producto])[0];
      return res.json(aVistaPublica(completo));
    }

    // Las publicaciones "se busca" viven en otra tabla, pero comparten esta
    // URL: el botón de compartir de la app es uno solo y genera
    // /producto/:id para ambas. Se consulta después de products porque los
    // productos son el caso mayoritario, y los ids no colisionan entre tablas.
    const busqueda = db.getWantedPostById(req.params.id);
    if (busqueda) {
      return res.json(aVistaPublicaBusqueda(attachWantedRelations(busqueda)));
    }

    // Una publicación borrada desaparece de la tabla (no hay soft delete), así
    // que "no existe" y "fue eliminada" son el mismo 404 — y debe serlo: decir
    // cuál de los dos es confirmaría que ese id existió.
    res.status(404).json({ error: 'Publicación no encontrada' });
  });

  app.use('/api/public', router);
}

module.exports = { register, aVistaPublica, aVistaPublicaBusqueda };
