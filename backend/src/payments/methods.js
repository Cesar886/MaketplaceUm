'use strict';

const useLegacySqlite = process.env.NODE_ENV === 'test'
  && Boolean(process.env.MERCADITO_DB_PATH)
  && !process.env.DATABASE_URL;

module.exports = useLegacySqlite
  ? require('./methods.sqlite')
  : require('./methods.postgres');

