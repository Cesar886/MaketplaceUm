'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { AsyncLocalStorage } = require('async_hooks');
const { Pool, types } = require('pg');

// node-postgres entrega BIGINT/NUMERIC como string. En esta aplicación esos
// campos son contadores, precios y cantidades que históricamente eran Number.
types.setTypeParser(20, value => Number(value));
types.setTypeParser(1700, value => Number(value));
types.setTypeParser(1114, value => new Date(`${value}Z`).toISOString());
types.setTypeParser(1184, value => new Date(value).toISOString());

const transactionContext = new AsyncLocalStorage();
const IDENTIFIER = /^[a-z_][a-z0-9_]*$/;

// PostgreSQL normaliza a minúsculas los identificadores sin comillas. El
// esquema mantiene ese comportamiento y aquí restauramos las claves legacy
// que consume el cliente Flutter, para no convertir esta migración en un
// cambio incompatible de API.
const LEGACY_KEYS = [
  'avatarInitials', 'isBusiness', 'logoUrl', 'businessDescription',
  'businessCategory', 'businessHours', 'paymentMethods', 'colorAcento',
  'avatarUrl', 'productId', 'meetingPoint', 'priceNum', 'publishedAgo',
  'imageIcon', 'imageColor', 'previousPrice', 'discountLabel', 'isFeatured',
  'isOffer', 'isFavorite', 'offerExpiresAt', 'availableDays', 'createdAt',
  'createdAtRaw', 'answeredAt', 'userId', 'queryText', 'autorNombre',
  'autorIniciales', 'autorLogo', 'autorMajor', 'autorEsNegocio',
  'autorVerificado', 'autorTipoCuenta', 'autorCarrera',
  'autorTipoVerificacion', 'autorSocioFundador', 'sellerName', 'sellerAvatar',
  'sellerIsBusiness', 'sellerVerified', 'sellerTipoCuenta', 'sellerCarrera',
  'sellerTipoVerificacion', 'sellerSocioFundador', 'totalCount',
  'unreadCount', 'lastMessageAt', 'lastMessagePreview', 'otherUserId',
  'productsToday', 'wantedToday', 'active7d', 'profileViews',
];
const LEGACY_KEY_BY_LOWER = new Map(LEGACY_KEYS.map(key => [key.toLowerCase(), key]));

let pool;
let schema = 'public';

function booleanEnv(name, fallback = false) {
  const value = process.env[name];
  if (value === undefined || value === '') return fallback;
  return ['1', 'true', 'yes', 'on'].includes(String(value).toLowerCase());
}

function intEnv(name, fallback, { min, max }) {
  const parsed = Number.parseInt(process.env[name] || '', 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function loadSslConfig(connectionString) {
  const parsed = new URL(connectionString);
  const isLoopback = ['localhost', '127.0.0.1', '::1'].includes(parsed.hostname);
  const sslEnabled = booleanEnv('PGSSL', !isLoopback);
  if (!sslEnabled) {
    if (process.env.NODE_ENV === 'production' && !isLoopback) {
      throw new Error('[db] PGSSL no puede desactivarse para un servidor PostgreSQL remoto.');
    }
    return false;
  }

  const caFile = String(process.env.PGSSL_CA_FILE || '').trim();
  if (!caFile && process.env.NODE_ENV === 'production') {
    throw new Error('[db] PGSSL_CA_FILE es obligatorio en producción para verificar el servidor.');
  }
  return {
    rejectUnauthorized: true,
    ...(caFile ? { ca: fs.readFileSync(path.resolve(caFile), 'utf8') } : {}),
  };
}

function createPool() {
  const connectionString = String(process.env.DATABASE_URL || '').trim();
  if (!connectionString) {
    throw new Error('[db] DATABASE_URL es obligatoria para PostgreSQL.');
  }
  let parsed;
  try {
    parsed = new URL(connectionString);
  } catch {
    throw new Error('[db] DATABASE_URL no es una URL válida.');
  }
  if (!['postgres:', 'postgresql:'].includes(parsed.protocol)) {
    throw new Error('[db] DATABASE_URL debe usar postgres:// o postgresql://.');
  }

  schema = String(process.env.PGSCHEMA || 'public').trim();
  if (!IDENTIFIER.test(schema)) throw new Error('[db] PGSCHEMA no es un identificador seguro.');

  const statementTimeout = intEnv('PG_STATEMENT_TIMEOUT_MS', 15_000, { min: 1_000, max: 120_000 });
  const lockTimeout = intEnv('PG_LOCK_TIMEOUT_MS', 5_000, { min: 500, max: 60_000 });
  const poolMax = intEnv('PGPOOL_MAX', 10, { min: 2, max: 50 });
  const poolMin = Math.min(intEnv('PGPOOL_MIN', 1, { min: 0, max: 10 }), poolMax);
  const nextPool = new Pool({
    connectionString,
    ssl: loadSslConfig(connectionString),
    max: poolMax,
    min: poolMin,
    idleTimeoutMillis: intEnv('PGPOOL_IDLE_TIMEOUT_MS', 30_000, { min: 1_000, max: 300_000 }),
    connectionTimeoutMillis: intEnv('PG_CONNECT_TIMEOUT_MS', 5_000, { min: 1_000, max: 30_000 }),
    allowExitOnIdle: process.env.NODE_ENV === 'test',
    application_name: 'marketplace-um-api',
    options: `-c search_path=${schema},pg_catalog -c statement_timeout=${statementTimeout} -c lock_timeout=${lockTimeout} -c idle_in_transaction_session_timeout=15000`,
  });
  nextPool.on('error', error => {
    // No imprimir configuración ni parámetros: DATABASE_URL contiene secreto.
    console.error('[db] conexión inactiva de PostgreSQL falló:', error.message);
  });
  return nextPool;
}

function normalizeRow(row) {
  if (!row) return row;
  const normalized = {};
  for (const [key, value] of Object.entries(row)) {
    normalized[LEGACY_KEY_BY_LOWER.get(key) || key] = value;
  }
  return normalized;
}

function sqliteFunctionsToPostgres(input) {
  let sql = input;
  // SQLite conserva el casing de alias sin comillas; PostgreSQL los pliega a
  // minúsculas. Se citan sólo alias camelCase (no tipos de CAST).
  sql = sql.replace(/\bAS\s+([a-z][A-Za-z0-9_]*[A-Z][A-Za-z0-9_]*)\b/g, 'AS "$1"');
  sql = sql.replace(/SELECT\s+rowid\s+FROM\s+messages\b/gi, 'SELECT seq AS rowid FROM messages');
  sql = sql.replace(/\b([A-Za-z_][A-Za-z0-9_]*)\.rowid\b/g, '$1.seq');
  sql = sql.replace(/\bORDER\s+BY\s+rowid\b/gi, 'ORDER BY seq');
  sql = sql.replace(
    /SELECT\s+name\s+FROM\s+sqlite_master\s+WHERE\s+type\s*=\s*'table'\s+AND\s+name\s*=\s*\?/gi,
    'SELECT table_name AS name FROM information_schema.tables WHERE table_schema = current_schema() AND table_name = ?',
  );
  sql = sql.replace(/\b(email|username)\s*=\s*(\?|[@:$][A-Za-z_][A-Za-z0-9_]*)\s+COLLATE\s+NOCASE\b/gi,
    'lower($1) = lower($2)');
  sql = sql.replace(/strftime\(\s*'%Y-%m-%dT%H:%M:%SZ'\s*,\s*([^)]+)\)/gi,
    "to_char(($1)::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')");
  sql = sql.replace(/CAST\(strftime\(\s*'%s'\s*,\s*([^)]+)\)\s+AS\s+INTEGER\)/gi,
    'CAST(EXTRACT(EPOCH FROM ($1)::timestamptz) AS BIGINT)');
  sql = sql.replace(/\(julianday\('now'\)\s*-\s*julianday\(MAX\(([^)]+)\)\)\)/gi,
    '(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(($1)::timestamptz))) / 86400.0)');
  sql = sql.replace(/\(julianday\('now'\)\s*-\s*julianday\(([^)]+)\)\)/gi,
    '(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - ($1)::timestamptz)) / 86400.0)');
  sql = sql.replace(/datetime\(\s*'now'\s*,\s*'start of day'\s*\)/gi,
    "date_trunc('day', CURRENT_TIMESTAMP)");
  sql = sql.replace(/datetime\(\s*'now'\s*,\s*'-([0-9]+)\s+(day|days|hour|hours|second|seconds)'\s*\)/gi,
    (_match, amount, unit) => `(CURRENT_TIMESTAMP - INTERVAL '${amount} ${unit}')`);
  sql = sql.replace(/datetime\(\s*'now'\s*,\s*'-'\s*\|\|\s*([@:$?][A-Za-z0-9_]*|\?)\s*\|\|\s*'\s*(days?|hours?|seconds?)'\s*\)/gi,
    (_match, value, unit) => `(CURRENT_TIMESTAMP - (${value} * INTERVAL '1 ${unit.replace(/s$/, '')}'))`);
  sql = sql.replace(/datetime\(\s*'now'\s*,\s*(\?)\s*\)/gi,
    '(CURRENT_TIMESTAMP + (?)::interval)');
  sql = sql.replace(/datetime\(\s*'now'\s*\)/gi, 'CURRENT_TIMESTAMP');
  sql = sql.replace(/datetime\(\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*\)/gi, '(($1)::timestamptz)');
  sql = sql.replace(/unixepoch\(\s*\)/gi, 'CAST(EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) AS BIGINT)');
  sql = sql.replace(/json_extract\(\s*([^,]+),\s*'\$\.([A-Za-z0-9_]+)'\s*\)/gi,
    "(($1)::jsonb ->> '$2')");
  sql = sql.replace(/\bMAX\(\s*0\s*,/gi, 'GREATEST(0,');
  sql = sql.replace(/\bMAX\(COALESCE\(auth_invalid_before,\s*0\),\s*\?\)/gi,
    'GREATEST(COALESCE(auth_invalid_before, 0), ?)');
  sql = sql.replace(/\bCASE\s+WHEN\s+(\?|[@:$][A-Za-z_][A-Za-z0-9_]*)\s+THEN\b/gi,
    'CASE WHEN $1 = 1 THEN');
  // PostgreSQL no puede inferir el tipo de un parámetro usado sólo en
  // `? IS NULL`; el cast no altera la semántica de esa comprobación.
  sql = sql.replace(/(\?|[@:$][A-Za-z_][A-Za-z0-9_]*)\s+IS\s+(NOT\s+)?NULL\b/gi,
    'CAST($1 AS TEXT) IS $2NULL');
  sql = sql.replace(/\b([A-Za-z_][A-Za-z0-9_.]*)\s+IS\s+(\?|[@:$][A-Za-z_][A-Za-z0-9_]*)/gi,
    '$1 IS NOT DISTINCT FROM $2');
  sql = sql.replace(/\bCOLLATE\s+NOCASE\b/gi, '');
  sql = sql.replace(/\bINSERT\s+OR\s+IGNORE\s+INTO\b/gi, 'INSERT INTO');
  return sql;
}

function bindParameters(inputSql, args) {
  let sql = sqliteFunctionsToPostgres(inputSql);
  const objects = args.filter(value => value && typeof value === 'object' && !Array.isArray(value) && !(value instanceof Date));
  const named = Object.assign({}, ...objects);
  const positional = args.filter(value => !objects.includes(value));
  const values = [];
  const namedIndexes = new Map();
  let positionalIndex = 0;
  let output = '';
  let quote = null;
  let lineComment = false;
  let blockComment = false;

  const pushValue = value => {
    values.push(value === undefined ? null : value);
    return `$${values.length}`;
  };

  for (let index = 0; index < sql.length; index += 1) {
    const char = sql[index];
    const next = sql[index + 1];
    if (lineComment) {
      output += char;
      if (char === '\n') lineComment = false;
      continue;
    }
    if (blockComment) {
      output += char;
      if (char === '*' && next === '/') {
        output += next;
        index += 1;
        blockComment = false;
      }
      continue;
    }
    if (quote) {
      output += char;
      if (char === quote && next === quote) {
        output += next;
        index += 1;
      } else if (char === quote) {
        quote = null;
      }
      continue;
    }
    if (char === '-' && next === '-') {
      output += char + next;
      index += 1;
      lineComment = true;
      continue;
    }
    if (char === '/' && next === '*') {
      output += char + next;
      index += 1;
      blockComment = true;
      continue;
    }
    if (char === "'" || char === '"') {
      quote = char;
      output += char;
      continue;
    }
    if (char === ':' && next === ':') {
      output += '::';
      index += 1;
      continue;
    }
    if (char === '?') {
      output += pushValue(positional[positionalIndex]);
      positionalIndex += 1;
      continue;
    }
    if (char === '@' || char === ':' || (char === '$' && !/[0-9]/.test(next || ''))) {
      const match = sql.slice(index + 1).match(/^[A-Za-z_][A-Za-z0-9_]*/);
      if (match) {
        const name = match[0];
        if (!(name in named)) throw new Error(`[db] falta el parámetro nombrado ${name}`);
        if (!namedIndexes.has(name)) namedIndexes.set(name, pushValue(named[name]));
        output += namedIndexes.get(name);
        index += name.length;
        continue;
      }
    }
    output += char;
  }

  if (/^\s*INSERT\s+INTO\b/i.test(output)
      && /\bOR\s+IGNORE\b/i.test(inputSql)
      && !/\bON\s+CONFLICT\b/i.test(output)) {
    output = `${output.replace(/;\s*$/, '')} ON CONFLICT DO NOTHING`;
  }
  // Único uso legacy que necesita lastInsertRowid.
  if (/^\s*INSERT\s+INTO\s+notification_log\b/i.test(output) && !/\bRETURNING\b/i.test(output)) {
    output = `${output.replace(/;\s*$/, '')} RETURNING id`;
  }
  return { text: output, values };
}

function activeClient() {
  if (!pool) throw new Error('Database not initialized. Call initDatabase() first.');
  return transactionContext.getStore() || pool;
}

class Statement {
  constructor(sql) {
    this.sql = sql;
  }

  async all(...args) {
    const result = await activeClient().query(bindParameters(this.sql, args));
    return result.rows.map(normalizeRow);
  }

  async get(...args) {
    const result = await activeClient().query(bindParameters(this.sql, args));
    return normalizeRow(result.rows[0]);
  }

  async run(...args) {
    const result = await activeClient().query(bindParameters(this.sql, args));
    return {
      changes: result.rowCount || 0,
      lastInsertRowid: result.rows[0] ? result.rows[0].id : undefined,
    };
  }
}

const database = {
  prepare(sql) {
    if (typeof sql !== 'string' || !sql.trim()) throw new Error('[db] SQL vacío.');
    return new Statement(sql);
  },
  async exec(sql) {
    return activeClient().query(sqliteFunctionsToPostgres(sql));
  },
  transaction(callback) {
    return async (...args) => {
      if (transactionContext.getStore()) return callback(...args);
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const result = await transactionContext.run(client, () => callback(...args));
        await client.query('COMMIT');
        return result;
      } catch (error) {
        try { await client.query('ROLLBACK'); } catch {}
        throw error;
      } finally {
        client.release();
      }
    };
  },
  async query(sql, values = []) {
    const result = await activeClient().query(sql, values);
    return { ...result, rows: result.rows.map(normalizeRow) };
  },
};

async function runMigrations() {
  const client = await pool.connect();
  try {
    await client.query("SELECT pg_advisory_lock(hashtext('marketplace_um_schema_migrations'))");
    await client.query(`CREATE TABLE IF NOT EXISTS ${schema}.schema_migrations (
      name TEXT PRIMARY KEY,
      checksum TEXT NOT NULL,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`);
    const directory = path.join(__dirname, '..', '..', 'migrations', 'postgres');
    const names = fs.readdirSync(directory).filter(name => /^\d+.*\.sql$/.test(name)).sort();
    for (const name of names) {
      const sql = fs.readFileSync(path.join(directory, name), 'utf8');
      const checksum = crypto.createHash('sha256').update(sql).digest('hex');
      const current = await client.query(
        `SELECT checksum FROM ${schema}.schema_migrations WHERE name = $1`,
        [name],
      );
      if (current.rows[0]) {
        if (current.rows[0].checksum !== checksum) {
          throw new Error(`[db] la migración aplicada ${name} fue modificada`);
        }
        continue;
      }
      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query(
          `INSERT INTO ${schema}.schema_migrations (name, checksum) VALUES ($1, $2)`,
          [name, checksum],
        );
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw new Error(`[db] falló la migración ${name}: ${error.message}`, { cause: error });
      }
    }
  } finally {
    try { await client.query("SELECT pg_advisory_unlock(hashtext('marketplace_um_schema_migrations'))"); } catch {}
    client.release();
  }
}

async function verifyMigrations() {
  const expected = fs.readdirSync(path.join(__dirname, '..', '..', 'migrations', 'postgres'))
    .filter(name => /^\d+.*\.sql$/.test(name))
    .sort()
    .map(name => ({
      name,
      checksum: crypto.createHash('sha256')
        .update(fs.readFileSync(path.join(__dirname, '..', '..', 'migrations', 'postgres', name), 'utf8'))
        .digest('hex'),
    }));
  const exists = await pool.query('SELECT to_regclass($1) AS name', [`${schema}.schema_migrations`]);
  if (!exists.rows[0]?.name) {
    throw new Error('[db] faltan migraciones; ejecuta npm run db:migrate con DATABASE_URL del migrador.');
  }
  const applied = await pool.query(`SELECT name, checksum FROM ${schema}.schema_migrations`);
  const byName = new Map(applied.rows.map(row => [row.name, row.checksum]));
  for (const migration of expected) {
    if (!byName.has(migration.name)) {
      throw new Error(`[db] falta la migración ${migration.name}; ejecuta npm run db:migrate.`);
    }
    if (byName.get(migration.name) !== migration.checksum) {
      throw new Error(`[db] la migración aplicada ${migration.name} fue modificada.`);
    }
  }
}

async function initPostgres() {
  if (pool) return database;
  pool = createPool();
  await pool.query('SELECT 1');
  if (process.env.NODE_ENV !== 'production' || booleanEnv('PG_RUN_MIGRATIONS', false)) {
    await runMigrations();
  } else {
    await verifyMigrations();
  }
  return database;
}

async function closePostgres() {
  const current = pool;
  pool = undefined;
  if (current) await current.end();
}

module.exports = {
  database,
  initPostgres,
  closePostgres,
  bindParameters,
  sqliteFunctionsToPostgres,
};
