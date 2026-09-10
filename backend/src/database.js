'use strict';

// PostgreSQL es la base de producción. La implementación SQLite se conserva
// únicamente para la suite legacy y para leer el archivo durante el traspaso;
// nunca se selecciona silenciosamente en un proceso normal.
const useLegacySqlite = process.env.NODE_ENV === 'test'
  && Boolean(process.env.MERCADITO_DB_PATH)
  && !process.env.DATABASE_URL;

module.exports = useLegacySqlite
  ? require('./database.sqlite')
  : require('./database.postgres');
