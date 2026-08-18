// Ajustes de privacidad del propio usuario.
//
// Hoy solo vive aquí "mostrar mi estado en línea", pero el prefijo /api/me
// y el nombre del archivo dejan sitio para los que vengan sin volver a
// mover rutas de sitio.

const db = require('../database');
const { requireAuth } = require('../auth');

function register(app) {
  app.get('/api/me/privacy', requireAuth, (req, res) => {
    res.json({ showOnlineStatus: db.getPresencia(req.user.id).comparteEstado });
  });

  app.patch('/api/me/privacy', requireAuth, (req, res) => {
    const { showOnlineStatus } = req.body || {};
    // Sin esta validación un `"false"` de un cliente descuidado se guardaría
    // como verdadero (toda cadena no vacía es truthy) y el usuario creería
    // haber apagado algo que sigue encendido.
    if (typeof showOnlineStatus !== 'boolean') {
      return res.status(400).json({ error: 'showOnlineStatus debe ser booleano' });
    }

    db.setMostrarEstadoEnLinea(req.user.id, showOnlineStatus);
    res.json({ showOnlineStatus });
  });
}

module.exports = { register };
