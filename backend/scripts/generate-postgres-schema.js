#!/usr/bin/env node
'use strict';

// Herramienta de desarrollo usada para congelar el esquema PostgreSQL
// inicial a partir de una copia SQLite ya migrada. No se ejecuta al arrancar
// ni toca la base de producción.
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');

const source = path.resolve(process.argv[2] || 'mercadito_um.db');
const target = path.resolve(
  process.argv[3] || path.join('migrations', 'postgres', '001_initial.sql'),
);
const sqlite = new Database(source, { readonly: true, fileMustExist: true });

function timestampColumns(sql) {
  const dateName = /(?:_at|_en|_inicio|_expira|_until|expiresat|lastactive|last_active|fecha_verificacion|identidad_confirmada_en)$/i;
  return sql.replace(/("?[A-Za-z_][A-Za-z0-9_]*"?)\s+TEXT\b/g, (match, column) =>
    dateName.test(column.replaceAll('"', ''))
      ? match.replace(/\bTEXT\b/, 'TIMESTAMPTZ')
      : match);
}

function postgresTable(sql, name) {
  let output = timestampColumns(sql)
    .replace(/"interacciones_dispositivo"/g, 'interacciones_dispositivo')
    .replace(/INTEGER\s+PRIMARY\s+KEY\s+AUTOINCREMENT/gi, 'BIGSERIAL PRIMARY KEY')
    .replace(/\bREAL\b/gi, 'DOUBLE PRECISION')
    .replace(/DEFAULT\s*\(datetime\('now'\)\)/gi, 'DEFAULT CURRENT_TIMESTAMP')
    .replace(/\bCOLLATE\s+NOCASE\b/gi, '')
    .replace(/!=/g, '<>')
    // Epochs y marcas de invalidación están en segundos/milisegundos y
    // desbordan INTEGER (32 bits), aunque SQLite los aceptaba sin problema.
    .replace(/\b(auth_invalid_before|expires_at)\s+INTEGER\b/gi, '$1 BIGINT')
    .replace(/\b(admin_id|resolved_by_admin_id|updated_by_admin_id|moderated_by_admin_id)\s+INTEGER\b/gi, '$1 BIGINT');

  if (name === 'messages') {
    output = output.replace(
      /id\s+TEXT\s+PRIMARY\s+KEY,/i,
      'id TEXT PRIMARY KEY,\n        seq BIGSERIAL NOT NULL UNIQUE,',
    );
  }
  return output;
}

function postgresIndex(sql, name) {
  if (name === 'idx_sellers_email_unique') {
    return `CREATE UNIQUE INDEX idx_sellers_email_unique\n      ON sellers(lower(email))\n      WHERE email IS NOT NULL AND email <> ''`;
  }
  return sql
    .replace(/"interacciones_dispositivo"/g, 'interacciones_dispositivo')
    .replace(/\bCOLLATE\s+NOCASE\b/gi, '')
    .replace(/!=/g, '<>');
}

const tables = sqlite.prepare(`
  SELECT name, sql FROM sqlite_master
  WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND sql IS NOT NULL
`).all();
const byName = new Map(tables.map(table => [table.name, table]));
const dependencies = new Map(tables.map(table => [
  table.name,
  new Set(sqlite.prepare(`PRAGMA foreign_key_list('${table.name.replaceAll("'", "''")}')`)
    .all().map(row => row.table).filter(name => name !== table.name && byName.has(name))),
]));
const ordered = [];
const pending = new Set(byName.keys());
while (pending.size) {
  const ready = [...pending].filter(name =>
    [...dependencies.get(name)].every(dependency => !pending.has(dependency)));
  if (!ready.length) throw new Error(`Dependencias circulares: ${[...pending].join(', ')}`);
  ready.sort();
  for (const name of ready) {
    ordered.push(byName.get(name));
    pending.delete(name);
  }
}

const indexes = sqlite.prepare(`
  SELECT name, sql FROM sqlite_master
  WHERE type = 'index' AND name NOT LIKE 'sqlite_%' AND sql IS NOT NULL
  ORDER BY name
`).all();

const body = [
  '-- Marketplace UM: esquema base para PostgreSQL 16+',
  '-- Generado desde el esquema SQLite final; no editar después de aplicarlo.',
  "SET TIME ZONE 'UTC';",
  '',
  ...ordered.flatMap(table => [postgresTable(table.sql, table.name) + ';', '']),
  ...indexes.flatMap(index => [postgresIndex(index.sql, index.name) + ';', '']),
  // Consultas de expiración, bandeja y moderación dependen de estos índices.
  'CREATE INDEX IF NOT EXISTS idx_messages_conversation_seq ON messages(conversation_id, seq);',
  'CREATE INDEX IF NOT EXISTS idx_products_expires_at ON products(expires_at) WHERE expires_at IS NOT NULL;',
  'CREATE INDEX IF NOT EXISTS idx_wanted_posts_expires_at ON wanted_posts(expires_at) WHERE expires_at IS NOT NULL;',
  '',
].join('\n');

fs.mkdirSync(path.dirname(target), { recursive: true, mode: 0o750 });
fs.writeFileSync(target, body, { mode: 0o640 });
sqlite.close();
console.log(`Esquema PostgreSQL escrito en ${target}`);
