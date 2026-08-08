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
    // Ubicación solo si el vendedor es un negocio: un particular no debe
    // quedar geolocalizado en una página pública indexable.
    ubicacion:
      vendedor && vendedor.isBusiness && producto.locationLat != null && producto.locationLng != null
        ? { lat: producto.locationLat, lng: producto.locationLng }
        : null,
    vendedor: vendedor
      ? {
          nombre: vendedor.name,
          iniciales: vendedor.avatarInitials || '',
          esNegocio: !!vendedor.isBusiness,
          verificado: !!vendedor.verified,
          tipoCuenta: vendedor.tipoCuenta || null,
          // Mismos dos campos que usa el subtítulo de rol en la app
          // (lib/widgets/user_role.dart), para que la web muestre el mismo
          // texto bajo el nombre y no se desincronicen.
          carrera: vendedor.carrera || null,
          tipoVerificacion: vendedor.tipoVerificacion || null,
        }
      : null,
  };
}

function register(app) {
  const { products } = require('../data');
  const { attachRelations } = require('./products');

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
    res.json({
      productos: products.map(p => ({
        id: p.id,
        actualizado: p.updated_at || p.created_at || null,
      })),
    });
  });

  // GET /api/public/productos/:id
  router.get('/productos/:id', (req, res) => {
    const producto = products.find(p => p.id === req.params.id);
    // Un producto borrado desaparece del array (no hay soft delete), así que
    // "no existe" y "fue eliminado" son el mismo 404 — y debe serlo: decir
    // cuál de los dos es confirmaría que ese id existió.
    if (!producto) {
      return res.status(404).json({ error: 'Producto no encontrado' });
    }

    // attachRelations es lo que resuelve sellerObj, categoryObj y el estado
    // calculado. Se reusa en vez de recalcularlo aquí para que la web no se
    // desincronice de la app cuando cambien las reglas de disponibilidad.
    const completo = attachRelations([producto])[0];
    res.json(aVistaPublica(completo));
  });

  app.use('/api/public', router);
}

module.exports = { register, aVistaPublica };
