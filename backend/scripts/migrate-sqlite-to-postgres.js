#!/usr/bin/env node
'use strict';

const path = require('path');
const Database = require('better-sqlite3');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { database, initPostgres, closePostgres } = require('../src/db/postgres');

const replaceTarget = process.argv.includes('--replace');
const sourceArgument = process.argv.slice(2).find(value => !value.startsWith('--'));
if (!sourceArgument) {
  console.error('Uso: node scripts/migrate-sqlite-to-postgres.js RUTA_SQLITE [--replace]');
  process.exit(2);
}
const sourcePath = path.resolve(sourceArgument);
const sqlite = new Database(sourcePath, { readonly: true, fileMustExist: true });

const safeIdentifier = value => {
  if (!/^[a-z_][a-z0-9_]*$/i.test(value)) throw new Error(`Identificador inseguro: ${value}`);
  return `"${value.replaceAll('"', '""')}"`;
};

function orderedSourceTables() {
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

async function importTable(schema, table, columns, primaryKey) {
  const sourceColumns = sqlite.prepare(`PRAGMA table_info('${table.replaceAll("'", "''")}')`)
    .all().map(row => row.name);
  const sourceByLower = new Map(sourceColumns.map(column => [column.toLowerCase(), column]));
  const shared = columns.filter(column => sourceByLower.has(column.column_name.toLowerCase()));
  if (!shared.length) return { table, source: 0, target: 0 };

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

  const result = await database.query(
    `SELECT COUNT(*)::bigint AS count FROM ${safeIdentifier(schema)}.${safeIdentifier(table)}`,
  );
  return { table, source: rows.length, target: result.rows[0].count };
}

async function main() {
  const quickCheck = sqlite.pragma('quick_check', { simple: true });
  if (quickCheck !== 'ok') throw new Error(`SQLite quick_check falló: ${quickCheck}`);
  const foreignKeyErrors = sqlite.pragma('foreign_key_check');
  if (foreignKeyErrors.length) {
    throw new Error(`SQLite contiene ${foreignKeyErrors.length} violaciones de llave foránea.`);
  }

  await initPostgres();
  const schema = String(process.env.PGSCHEMA || 'public');
  const metadata = await targetMetadata(schema);
  const tables = orderedSourceTables().filter(table => metadata.has(table));
  const seedTables = new Set(['categories', 'highlight_plans', 'config']);

  const report = await database.transaction(async () => {
    await database.query("SELECT pg_advisory_xact_lock(hashtext('marketplace_um_sqlite_import'))");
    const nonEmpty = [];
    for (const table of tables) {
      if (seedTables.has(table)) continue;
      const count = await database.query(
        `SELECT COUNT(*)::bigint AS count FROM ${safeIdentifier(schema)}.${safeIdentifier(table)}`,
      );
      if (count.rows[0].count > 0) nonEmpty.push(table);
    }
    if (nonEmpty.length && !replaceTarget) {
      throw new Error(
        `Destino no vacío (${nonEmpty.join(', ')}). Detén la API y repite con --replace si deseas sustituirlo.`,
      );
    }
    if (replaceTarget) {
      const targets = [...metadata.keys()].filter(table => table !== 'schema_migrations');
      await database.query(
        `TRUNCATE ${targets.map(table =>
          `${safeIdentifier(schema)}.${safeIdentifier(table)}`).join(', ')} RESTART IDENTITY CASCADE`,
      );
    }

    const results = [];
    for (const table of tables) {
      results.push(await importTable(
        schema,
        table,
        metadata.get(table),
        await primaryKeys(schema, table),
      ));
    }
    const mismatch = results.filter(item => item.source !== item.target);
    if (mismatch.length) {
      throw new Error(`Conteos distintos: ${JSON.stringify(mismatch)}`);
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
    return results;
  })();

  console.log(JSON.stringify({ source: sourcePath, tables: report }, null, 2));
}

main().catch(error => {
  console.error(`Migración cancelada: ${error.message}`);
  process.exitCode = 1;
}).finally(async () => {
  sqlite.close();
  await closePostgres();
});
