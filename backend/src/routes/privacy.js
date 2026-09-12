// Ajustes de privacidad del propio usuario.
//
// Hoy solo vive aquí "mostrar mi estado en línea", pero el prefijo /api/me
// y el nombre del archivo dejan sitio para los que vengan sin volver a
// mover rutas de sitio.

const db = require('../database');
const {
  requireAuth
} = require('../auth');
function register(app) {
  app.get('/api/me/privacy', requireAuth, async (req, res) => {
    res.json({
      showOnlineStatus: (await db.getPresencia(req.user.id)).comparteEstado
    });
  });
  app.patch('/api/me/privacy', requireAuth, async (req, res) => {
    const {
      showOnlineStatus
    } = req.body || {};
    // Sin esta validación un `"false"` de un cliente descuidado se guardaría
    // como verdadero (toda cadena no vacía es truthy) y el usuario creería
    // haber apagado algo que sigue encendido.
    if (typeof showOnlineStatus !== 'boolean') {
      return res.status(400).json({
        error: 'showOnlineStatus debe ser booleano'
      });
    }
    await db.setMostrarEstadoEnLinea(req.user.id, showOnlineStatus);
    res.json({
      showOnlineStatus
    });
  });
  app.get('/api/me/security', requireAuth, async (req, res) => {
    if (req.user.anon) return res.json({
      users: []
    });
    res.json({
      users: await db.getChatSafetySettings(req.user.id)
    });
  });
  app.delete('/api/me/account', requireAuth, async (req, res) => {
    if (req.user.anon) return res.status(403).json({
      error: 'Cuenta requerida.'
    });
    const result = await db.anonymizeSellerAccount(req.user.id);
    if (!result) return res.status(404).json({
      error: 'Cuenta no encontrada.'
    });
    const io = req.app.get('io');
    if (io?.in) io.in(`user:${req.user.id}`).disconnectSockets(true);
    res.json({
      deleted: true,
      deletedAt: result.deletedAt
    });
  });
}
module.exports = {
  register
};
