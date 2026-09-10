'use strict';

// Las rutas se montan también de forma aislada en pruebas y herramientas;
// instalar aquí el puente garantiza propagación de errores async aun cuando
// no se haya cargado todavía el entrypoint principal.
require('./asyncExpress').installAsyncExpressBridge();

// PostgreSQL es la base de producción. La implementación SQLite se conserva
// únicamente para la suite legacy y para leer el archivo durante el traspaso;
// nunca se selecciona silenciosamente en un proceso normal.
const useLegacySqlite = process.env.NODE_ENV === 'test'
  && Boolean(process.env.MERCADITO_DB_PATH)
  && !process.env.DATABASE_URL;

module.exports = useLegacySqlite
  ? require('./database.sqlite')
  : require('./database.postgres');
