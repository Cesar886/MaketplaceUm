// TODO: Destacar publicaciones pendiente para próxima actualización - no
// eliminar. La app ya no consume este endpoint (ver kDestacarHabilitado en
// lib/features/highlight/destacar_flag.dart), pero se deja registrado y
// funcionando a propósito: las versiones ya instaladas de la app siguen
// pidiendo /api/highlight-plans y romperlo les daría un error en el home.
// Al reactivar la feature no hay nada que cambiar acá.
const { highlightPlans } = require('../data');

function register(app) {
  app.get('/api/highlight-plans', (_req, res) => {
    res.json(highlightPlans);
  });
}

module.exports = { register };
