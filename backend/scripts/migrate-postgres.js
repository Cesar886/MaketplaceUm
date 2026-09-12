#!/usr/bin/env node
'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
process.env.PG_RUN_MIGRATIONS = 'true';

const { initPostgres, closePostgres } = require('../src/db/postgres');

initPostgres()
  .then(() => console.log('Migraciones PostgreSQL aplicadas y verificadas.'))
  .catch(error => {
    console.error(`Migración PostgreSQL falló: ${error.message}`);
    process.exitCode = 1;
  })
  .finally(closePostgres);
