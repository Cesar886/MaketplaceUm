#!/usr/bin/env node
'use strict';

const path = require('path');
const Database = require('better-sqlite3');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { database, initPostgres, closePostgres } = require('../src/db/postgres');

const SEED_TABLES = new Set(['categories', 'highlight_plans', 'config']);

// El SQLite de produccion puede ser anterior a las ultimas migraciones legacy.
// Cada ausencia tolerada esta enumerada deliberadamente: una tabla nueva no se
// puede ignorar por accidente, sino que obliga a revisar este importador.
const ALLOWED_TARGET_ONLY_TABLES = new Map([
  ['admin_audit_log', 'bitacora administrativa agregada despues del esquema SQLite historico'],
  ['admin_revoked_tokens', 'sesiones administrativas agregadas despues del esquema SQLite historico'],
  ['admins', 'identidades administrativas que se pueden crear despues del corte'],
  ['chat_user_settings', 'preferencias de chat agregadas en una migracion legacy posterior'],
  ['config', 'catalogo sembrado por 002_seed_catalogs.sql; se conserva si el origen no lo tiene'],
  ['profile_view_events', 'metrica agregada en una migracion legacy posterior'],
  ['publication_limit_resets', 'auditoria administrativa agregada despues del esquema historico'],
  ['refresh_sessions', 'sesiones persistentes agregadas despues del esquema historico'],
  ['reports', 'reportes agregados en una migracion legacy posterior'],
  ['revoked_sessions', 'revocacion JWT agregada despues del esquema historico'],
]);

const ALLOWED_TARGET_ONLY_COLUMNS = new Map([
  ['messages', new Map([
    ['seq', 'secuencia PostgreSQL generada para conservar el orden de rowid'],
  ])],
  ['products', new Map([
    ['expires_at', 'columna nullable agregada despues del SQLite historico'],
    ['moderation_status', 'columna nueva con DEFAULT visible'],
    ['moderation_reason', 'columna nueva nullable'],
    ['moderated_at', 'columna nueva nullable'],
    ['moderated_by_admin_id', 'columna nueva nullable'],
  ])],
  ['sellers', new Map([
    ['profile_views', 'contador nuevo con DEFAULT 0'],
    ['admin_status', 'estado nuevo con DEFAULT active'],
    ['admin_status_reason', 'columna nueva nullable'],
    ['admin_status_until', 'columna nueva nullable'],
    ['auth_invalid_before', 'corte de sesiones nuevo con DEFAULT 0'],
    ['deleted_at', 'columna nueva nullable'],
  ])],
  ['wanted_posts', new Map([
    ['expires_at', 'columna nullable agregada despues del SQLite historico'],
    ['moderation_status', 'columna nueva con DEFAULT visible'],
    ['moderation_reason', 'columna nueva nullable'],
    ['moderated_at', 'columna nueva nullable'],
    ['moderated_by_admin_id', 'columna nueva nullable'],
  ])],
]);

// Deliberadamente vacias: nunca es aceptable descartar una tabla o columna del
// origen. Si aparece una, primero debe existir una migracion PostgreSQL capaz de
// recibirla; no se soluciona agregandola aqui sin una justificacion de negocio.
const ALLOWED_SOURCE_ONLY_TABLES = new Map();
const ALLOWED_SOURCE_ONLY_COLUMNS = new Map();

const REQUIRED_SEED_MINIMUMS = new Map([
  ['categories', 8],
  ['highlight_plans', 4],
  ['config', 5],
]);

const safeIdentifier = value => {
  if (!/^[a-z_][a-z0-9_]*$/i.test(value)) throw new Error(`Identificador inseguro: ${value}`);
  return `"${value.replaceAll('"', '""')}"`;
};

function orderedSourceTables(sqlite) {
  const tables = sqlite.prepare(`
    SELECT name FROM sqlite_master
    WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
    ORDER BY name
  `).all().map(row => row.name);
  const known = new Set(tables);
  const dependencies = new Map(tables.map(table => [
    table,
    new Set(sqlite.prepare(`PRAGMA foreign_key_list('${table.replaceAll("'", "''")}')`)
      .all().map(row => row.table).filter(name => name !== table && known.has(name))),
  ]));
  const ordered = [];
  const pending = new Set(tables);
  while (pending.size) {
    const ready = [...pending].filter(table =>
      [...dependencies.get(table)].every(dependency => !pending.has(dependency)));
    if (!ready.length) throw new Error(`Dependencias circulares: ${[...pending].join(', ')}`);
    ready.sort();
    for (const table of ready) {
      ordered.push(table);
      pending.delete(table);
    }
  }
  return ordered;
}

function sourceMetadata(sqlite) {
  const metadata = new Map();
  const tables = sqlite.prepare(`
    SELECT name FROM sqlite_master
    WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
    ORDER BY name
  `).all().map(row => row.name);
  for (const table of tables) {
    safeIdentifier(table);
    metadata.set(table, sqlite.prepare(
      `PRAGMA table_info('${table.replaceAll("'", "''")}')`,
    ).all().map(column => ({ column_name: column.name })));
  }
  return metadata;
}

function normalizedMetadata(metadata, label) {
  const normalized = new Map();
  for (const [table, columns] of metadata) {
    const normalizedTable = String(table).toLowerCase();
    if (normalized.has(normalizedTable)) {
      throw new Error(`Preflight de esquema fallo: ${label} contiene tablas duplicadas por casing: ${table}`);
    }
    const byName = new Map();
    for (const column of columns) {
      const normalizedColumn = String(column.column_name).toLowerCase();
      if (byName.has(normalizedColumn)) {
        throw new Error(
          `Preflight de esquema fallo: ${label}.${table} contiene columnas duplicadas por casing: ${column.column_name}`,
        );
      }
      byName.set(normalizedColumn, column);
    }
    normalized.set(normalizedTable, { actualName: table, columns: byName });
  }
  return normalized;
}

function analyzeSchemaCompatibility(source, target) {
  const sourceByName = normalizedMetadata(source, 'SQLite');
  const targetByName = normalizedMetadata(target, 'PostgreSQL');
  const errors = [];

  for (const [table, definition] of sourceByName) {
    if (!targetByName.has(table) && !ALLOWED_SOURCE_ONLY_TABLES.has(table)) {
      errors.push(`tabla SQLite sin destino: ${definition.actualName}`);
    }
  }
  for (const [table, definition] of targetByName) {
    if (!sourceByName.has(table) && !ALLOWED_TARGET_ONLY_TABLES.has(table)) {
      errors.push(`tabla PostgreSQL ausente en SQLite y no clasificada: ${definition.actualName}`);
    }
  }

  for (const [table, sourceDefinition] of sourceByName) {
    const targetDefinition = targetByName.get(table);
    if (!targetDefinition) continue;
    const allowedSourceColumns = ALLOWED_SOURCE_ONLY_COLUMNS.get(table) || new Map();
    const allowedTargetColumns = ALLOWED_TARGET_ONLY_COLUMNS.get(table) || new Map();
    for (const [column, definition] of sourceDefinition.columns) {
      if (!targetDefinition.columns.has(column) && !allowedSourceColumns.has(column)) {
        errors.push(`columna SQLite sin destino: ${sourceDefinition.actualName}.${definition.column_name}`);
      }
    }
    for (const [column, definition] of targetDefinition.columns) {
      if (!sourceDefinition.columns.has(column) && !allowedTargetColumns.has(column)) {
        errors.push(
          `columna PostgreSQL ausente en SQLite y no clasificada: ${targetDefinition.actualName}.${definition.column_name}`,
        );
      }
    }
  }

  if (errors.length) {
    throw new Error(
      'Preflight de esquema fallo; no se importaron datos:\n- ' + errors.join('\n- '),
    );
  }

  return {
    importedTables: [...sourceByName.keys()].filter(table => targetByName.has(table)),
    preservedTables: [...targetByName.keys()].filter(table => !sourceByName.has(table)),
  };
}

function replacementTables(orderedTables, compatibility) {
  const imported = new Set(compatibility.importedTables);
  return orderedTables
    .map(table => String(table).toLowerCase())
    .filter(table => imported.has(table));
}

function buildReplacementSql(schema, tables) {
  if (!tables.length) return null;
  return `TRUNCATE ${tables.map(table =>
    `${safeIdentifier(schema)}.${safeIdentifier(table)}`).join(', ')} RESTART IDENTITY`;
}

function assertRequiredSeedState(counts, label) {
  const errors = [];
  for (const [table, minimum] of REQUIRED_SEED_MINIMUMS) {
    if (counts.has(table) && counts.get(table) < minimum) {
      errors.push(`${table}: ${counts.get(table)}/${minimum}`);
    }
  }
  if (errors.length) {
    throw new Error(`Preflight de catalogos fallo en ${label}: ${errors.join(', ')}`);
  }
}

function assertPostImportState({ importedSourceCounts, targetCounts, preservedBefore, preservedAfter }) {
  const errors = [];
  for (const [table, sourceCount] of importedSourceCounts) {
    const targetCount = targetCounts.get(table);
    if (targetCount !== sourceCount) {
      errors.push(`${table}: SQLite=${sourceCount}, PostgreSQL=${String(targetCount)}`);
    }
  }
  for (const [table, before] of preservedBefore) {
    const after = preservedAfter.get(table);
    if (after !== before) {
      errors.push(`${table}: tabla preservada cambio de ${before} a ${String(after)}`);
    }
  }
  for (const [table, minimum] of REQUIRED_SEED_MINIMUMS) {
    if (preservedBefore.has(table) && preservedAfter.get(table) < minimum) {
      errors.push(`${table}: catalogo preservado incompleto (${preservedAfter.get(table)}/${minimum})`);
    }
  }
  if (errors.length) throw new Error(`Validacion post-import fallo:\n- ${errors.join('\n- ')}`);
}

function sqliteTableCounts(sqlite, tables) {
  return new Map(tables.map(table => [
    table,
    sqlite.prepare(`SELECT COUNT(*) AS count FROM ${safeIdentifier(table)}`).get().count,
  ]));
}

async function postgresTableCounts(schema, tables) {
  const counts = new Map();
  for (const table of tables) {
    const result = await database.query(
      `SELECT COUNT(*)::bigint AS count FROM ${safeIdentifier(schema)}.${safeIdentifier(table)}`,
    );
    counts.set(table, result.rows[0].count);
  }
  return counts;
}

async function targetMetadata(schema) {
  const result = await database.query(`
    SELECT table_name, column_name, data_type, is_nullable, column_default
    FROM information_schema.columns
    WHERE table_schema = $1
      AND table_name NOT IN ('schema_migrations')
    ORDER BY table_name, ordinal_position
  `, [schema]);
  const metadata = new Map();
  for (const row of result.rows) {
    if (!metadata.has(row.table_name)) metadata.set(row.table_name, []);
    metadata.get(row.table_name).push(row);
  }
  return metadata;
}

async function primaryKeys(schema, table) {
  const result = await database.query(`
    SELECT a.attname AS column_name
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(i.indkey)
    WHERE i.indisprimary AND n.nspname = $1 AND c.relname = $2
    ORDER BY array_position(i.indkey, a.attnum)
  `, [schema, table]);
  return result.rows.map(row => row.column_name);
}

function normalizeValue(value, column) {
  if (value === undefined) return null;
  if (column.data_type.includes('timestamp')) {
    if (value === null || value === '') return null;
    const parsed = Date.parse(String(value).includes('T') ? String(value) : `${value}Z`);
    if (!Number.isFinite(parsed)) throw new Error(`Timestamp inválido en ${column.column_name}`);
    return new Date(parsed).toISOString();
  }
  return value;
}

async function importTable(sqlite, schema, table, columns, primaryKey) {
  const sourceColumns = sqlite.prepare(`PRAGMA table_info('${table.replaceAll("'", "''")}')`)
    .all().map(row => row.name);
  const sourceByLower = new Map(sourceColumns.map(column => [column.toLowerCase(), column]));
  const shared = columns.filter(column => sourceByLower.has(column.column_name.toLowerCase()));
  if (!shared.length) return { table, source: 0 };

  const order = table === 'messages' ? ' ORDER BY rowid' : '';
  const rows = sqlite.prepare(`SELECT * FROM ${safeIdentifier(table)}${order}`).all();
  const quotedColumns = shared.map(column => safeIdentifier(column.column_name));
  const updateColumns = shared.filter(column => !primaryKey.includes(column.column_name));
  const conflict = primaryKey.length
    ? ` ON CONFLICT (${primaryKey.map(safeIdentifier).join(', ')}) ${
      updateColumns.length
        ? `DO UPDATE SET ${updateColumns.map(column =>
          `${safeIdentifier(column.column_name)} = excluded.${safeIdentifier(column.column_name)}`).join(', ')}`
        : 'DO NOTHING'}`
    : '';

  for (let offset = 0; offset < rows.length; offset += 200) {
    const batch = rows.slice(offset, offset + 200);
    const values = [];
    const tuples = batch.map(row => {
      const placeholders = shared.map(column => {
        values.push(normalizeValue(row[sourceByLower.get(column.column_name.toLowerCase())], column));
        return `$${values.length}`;
      });
      return `(${placeholders.join(', ')})`;
    });
    if (tuples.length) {
      await database.query(
        `INSERT INTO ${safeIdentifier(schema)}.${safeIdentifier(table)} (${quotedColumns.join(', ')}) `
          + `VALUES ${tuples.join(', ')}${conflict}`,
        values,
      );
    }
  }

  return { table, source: rows.length };
}

async function main(argv = process.argv.slice(2)) {
  const replaceTarget = argv.includes('--replace');
  const sourceArgument = argv.find(value => !value.startsWith('--'));
  if (!sourceArgument) {
    const error = new Error('Uso: node scripts/migrate-sqlite-to-postgres.js RUTA_SQLITE [--replace]');
    error.exitCode = 2;
    throw error;
  }
  const sourcePath = path.resolve(sourceArgument);
  const sqlite = new Database(sourcePath, { readonly: true, fileMustExist: true });
  let postgresInitialized = false;

  try {
    const quickCheck = sqlite.pragma('quick_check', { simple: true });
    if (quickCheck !== 'ok') throw new Error(`SQLite quick_check falló: ${quickCheck}`);
    const foreignKeyErrors = sqlite.pragma('foreign_key_check');
    if (foreignKeyErrors.length) {
      throw new Error(`SQLite contiene ${foreignKeyErrors.length} violaciones de llave foránea.`);
    }

    const source = sourceMetadata(sqlite);
    const orderedTables = orderedSourceTables(sqlite);
    const sourceCounts = sqliteTableCounts(
      sqlite,
      orderedTables.map(table => String(table).toLowerCase()),
    );
    assertRequiredSeedState(sourceCounts, 'SQLite');

    postgresInitialized = true;
    await initPostgres();
    const schema = String(process.env.PGSCHEMA || 'public');
    const metadata = await targetMetadata(schema);
    const compatibility = analyzeSchemaCompatibility(source, metadata);
    const tables = replacementTables(orderedTables, compatibility);

    const report = await database.transaction(async () => {
      await database.query("SELECT pg_advisory_xact_lock(hashtext('marketplace_um_sqlite_import'))");
      const preservedBefore = await postgresTableCounts(schema, compatibility.preservedTables);
      assertRequiredSeedState(preservedBefore, 'PostgreSQL preservado');

      const currentImportedCounts = await postgresTableCounts(schema, tables);
      const nonEmpty = tables.filter(table =>
        !SEED_TABLES.has(table) && currentImportedCounts.get(table) > 0);
      if (nonEmpty.length && !replaceTarget) {
        throw new Error(
          `Destino no vacío (${nonEmpty.join(', ')}). Detén la API y repite con --replace si deseas sustituirlo.`,
        );
      }
      if (replaceTarget && tables.length) {
        // Sólo se reemplazan tablas representadas en el snapshot. No se usa
        // CASCADE: una dependencia destino no clasificada debe abortar, no
        // borrar silenciosamente tablas nuevas o catálogos preservados.
        await database.query(buildReplacementSql(schema, tables));
      }

      const results = [];
      for (const table of tables) {
        results.push(await importTable(
          sqlite,
          schema,
          table,
          metadata.get(table),
          await primaryKeys(schema, table),
        ));
      }

      // Las secuencias deben continuar después del ID máximo importado.
      for (const [table, columns] of metadata) {
        for (const column of columns.filter(item => /^nextval\(/.test(item.column_default || ''))) {
          const relation = `${safeIdentifier(schema)}.${safeIdentifier(table)}`;
          const name = `${schema}.${table}`;
          await database.query(`
            SELECT setval(
              pg_get_serial_sequence($1, $2),
              GREATEST(COALESCE(MAX(${safeIdentifier(column.column_name)}), 0), 1),
              COALESCE(MAX(${safeIdentifier(column.column_name)}), 0) > 0
            )
            FROM ${relation}
          `, [name, column.column_name]);
        }
      }

      const targetCounts = await postgresTableCounts(schema, tables);
      const preservedAfter = await postgresTableCounts(schema, compatibility.preservedTables);
      assertPostImportState({
        importedSourceCounts: new Map(results.map(item => [item.table, item.source])),
        targetCounts,
        preservedBefore,
        preservedAfter,
      });
      return {
        tables: results.map(item => ({ ...item, target: targetCounts.get(item.table) })),
        preservedTables: Object.fromEntries(preservedAfter),
      };
    })();

    console.log(JSON.stringify({ source: sourcePath, ...report }, null, 2));
    return report;
  } finally {
    sqlite.close();
    if (postgresInitialized) await closePostgres();
  }
}

if (require.main === module) {
  main().catch(error => {
    console.error(`Migración cancelada: ${error.message}`);
    process.exitCode = error.exitCode || 1;
  });
}

module.exports = {
  ALLOWED_SOURCE_ONLY_COLUMNS,
  ALLOWED_SOURCE_ONLY_TABLES,
  ALLOWED_TARGET_ONLY_COLUMNS,
  ALLOWED_TARGET_ONLY_TABLES,
  REQUIRED_SEED_MINIMUMS,
  analyzeSchemaCompatibility,
  assertPostImportState,
  assertRequiredSeedState,
  buildReplacementSql,
  main,
  replacementTables,
  safeIdentifier,
};
