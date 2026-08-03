// Configuración de PM2 para mercadito-backend.
//
// Por qué existe este archivo: un despliegue anterior actualizó el código
// (agregó bcryptjs como dependencia) sin correr `npm install` en el servidor.
// La app entró en crash-loop (MODULE_NOT_FOUND) y, como el min_uptime/backoff
// por defecto de PM2 son muy agresivos (reinicio casi instantáneo), agotó los
// 16 reintentos en segundos y quedó completamente caída y en silencio.
//
// Este archivo no evita que una app rota deje de funcionar — eso requiere
// arreglar la causa (ej. correr npm install). Lo que sí hace es:
//   1. Espaciar los reintentos con backoff exponencial en vez de machacar
//      el proceso cada pocos milisegundos.
//   2. Dar más margen (min_uptime más alto + más reintentos) antes de darse
//      por vencido, para que un problema transitorio tenga chance de curarse
//      solo sin agotar el límite en segundos.
//   3. Cuando SÍ se agota el límite, seguir "errored" y visible en
//      `pm2 list`/`pm2 logs` en vez de desaparecer sin dejar rastro — para
//      detectarlo de verdad hace falta un monitor externo pegándole a
//      /api/health (ver nota al final de este archivo).
module.exports = {
  apps: [
    {
      name: 'mercadito-backend',
      script: './src/index.js',
      cwd: __dirname,
      instances: 1,
      exec_mode: 'fork',

      autorestart: true,
      watch: false,

      // Un proceso que sobrevive menos de 30s se considera "inestable"
      // (por defecto PM2 usa 1000ms, que es casi nada para un crash-loop
      // de arranque como un módulo faltante).
      min_uptime: '30s',

      // Cuántos reinicios inestables se toleran antes de rendirse y quedar
      // "errored" sin más reintentos. Antes eran ~16 en segundos; ahora,
      // combinado con el backoff exponencial de abajo, esos 10 reintentos
      // se reparten a lo largo de varios minutos.
      max_restarts: 10,

      // Backoff exponencial: primer reintento a los 3s, y cada reintento
      // subsiguiente duplica el delay (PM2 lo topa internamente ~15s).
      // Es la corrección oficial de PM2 para "too many unstable restarts".
      exp_backoff_restart_delay: 3000,

      max_memory_restart: '300M',

      env: {
        NODE_ENV: 'production',
      },

      error_file: './logs/pm2-error.log',
      out_file: './logs/pm2-out.log',
      merge_logs: true,
      time: true,
    },
  ],
};

// ─── Notas de operación ──────────────────────────────────────────────
//
// Despliegue / arranque:
//   cd /root/mercaditoUmBack
//   npm install --omit=dev
//   pm2 delete mercadito-backend   (solo si ya existía sin este config)
//   pm2 start ecosystem.config.js
//   pm2 save                       (persiste la lista para el reboot)
//
// pm2 startup (arrancar solo tras un reinicio del servidor) ya está
// habilitado como servicio systemd (`pm2-root`) — no hace falta repetirlo
// a menos que se reinstale PM2 o cambie el usuario que lo corre.
//
// Recomendado (no configurado aquí, requiere credenciales que no tengo):
// un monitor externo tipo UptimeRobot / healthchecks.io pegándole a
// GET /api/health cada pocos minutos, con alerta por email/SMS si falla.
// Es la única forma real de enterarte si la app se cae de madrugada — el
// backoff de arriba solo evita que se caiga MÁS RÁPIDO, no garantiza que
// se quede arriba si el bug de fondo no se arregla.
