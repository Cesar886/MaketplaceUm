function register(app) {
  // POST /api/client-errors — recibe errores técnicos que la app atrapó y le
  // mostró al usuario ya traducidos (ver lib/services/api_error.dart). El
  // usuario nunca ve esto: es para que quede en los logs del servidor y se
  // pueda diagnosticar sin depender de que alguien reporte el problema.
  // Fire-and-forget desde el cliente, así que nunca debe romper nada aquí:
  // siempre responde 204 aunque el cuerpo venga incompleto.
  app.post('/api/client-errors', (req, res) => {
    const { contexto, error, stack, plataforma } = req.body || {};
    console.error(
      `📱 [client-error] ${plataforma || '?'} — ${contexto || 'Error'}: ${error || '(sin detalle)'}`,
    );
    if (stack) console.error(stack);
    res.status(204).end();
  });
}

module.exports = { register };
