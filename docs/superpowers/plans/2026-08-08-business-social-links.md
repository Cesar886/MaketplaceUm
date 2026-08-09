# Business Social Links Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let verified business accounts add Facebook/Instagram/WhatsApp/TikTok/X links to their profile, editable in the existing profile editor and visible as tappable icons on the public business profile.

**Architecture:** Five nullable columns on the existing `sellers` table (not `verificaciones`, which is the onboarding table — the profile editor and public profile already read/write `sellers`). Backend validates each URL's hostname against a per-platform whitelist and WhatsApp as a bare digit string; `PATCH /api/sellers/:id` and `rowToSeller` (used by `GET /api/sellers/:id`) are extended the same way `businessDescription`/`businessHours` already are. Frontend adds a mirrored Dart validator, a new "Redes sociales" section in the business editor, and a small pure `buildSocialLinkEntries` helper + `SocialLinksRow` widget that the public profile renders only when at least one link is set.

**Tech Stack:** Node.js/Express/SQLite (better-sqlite3, node:test), Flutter/Dart, font_awesome_flutter ^11.0.0, url_launcher.

## Global Constraints

- All 5 fields are nullable and optional; empty string clears a filled field back to NULL.
- Only `sellers.isBusiness === true` accounts may set/see these fields via the editor; gating mirrors the existing `businessDescription`/`businessCategory` pattern in `backend/src/routes/sellers.js`.
- `whatsapp_number` stores bare digits with country code (e.g. `"5215512345678"`), never a full URL — see design doc `docs/superpowers/specs/2026-08-08-business-social-links-design.md` for the rationale.
- Max length 200 chars for the 4 URL fields; WhatsApp is `^\d{10,15}$`.
- Migration must not alter `verified`, `estado`, or any other existing column/table — existing verified businesses keep their status and get NULL in the 5 new columns.
- No new npm/pub dependencies.

---

### Task 1: Migration + `rowToSeller` — backend schema layer

**Files:**
- Modify: `backend/src/database.js:709-731` (add migration 27 after migration 26, before `console.log('🔄 Migración de schema completada')`)
- Modify: `backend/src/database.js:844-878` (`rowToSeller`)
- Create: `backend/src/database.socialLinks.test.js`

**Interfaces:**
- Produces: `sellers` table columns `facebook_url`, `instagram_url`, `whatsapp_number`, `tiktok_url`, `twitter_url` (all `TEXT`, nullable).
- Produces: `rowToSeller(row)` return object gains keys `facebookUrl`, `instagramUrl`, `whatsappNumber`, `tiktokUrl`, `twitterUrl` (each `string | null`).

- [ ] **Step 1: Write the failing test**

```js
// backend/src/database.socialLinks.test.js
const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-social-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

const db = require('./database');

db.initDatabase();

test('las columnas de redes sociales existen en sellers', () => {
  const cols = db.getDb().prepare("PRAGMA table_info('sellers')").all().map(c => c.name);
  for (const col of ['facebook_url', 'instagram_url', 'whatsapp_number', 'tiktok_url', 'twitter_url']) {
    assert.ok(cols.includes(col), `falta la columna ${col}`);
  }
});

test('un negocio ya verificado sin redes sociales queda con estos campos en NULL, sin tocar su verificación', () => {
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, avatarInitials, major, isBusiness, verified, tipo_cuenta)
     VALUES (?, 'Negocio Viejo', 'NV', '', 1, 1, 'negocio')`,
  ).run('seller_social_viejo_1');

  const row = db.getDb().prepare('SELECT * FROM sellers WHERE id = ?').get('seller_social_viejo_1');
  assert.strictEqual(row.facebook_url, null);
  assert.strictEqual(row.instagram_url, null);
  assert.strictEqual(row.whatsapp_number, null);
  assert.strictEqual(row.tiktok_url, null);
  assert.strictEqual(row.twitter_url, null);
  assert.strictEqual(row.verified, 1);

  const seller = db.rowToSeller(row);
  assert.strictEqual(seller.facebookUrl, null);
  assert.strictEqual(seller.instagramUrl, null);
  assert.strictEqual(seller.whatsappNumber, null);
  assert.strictEqual(seller.tiktokUrl, null);
  assert.strictEqual(seller.twitterUrl, null);
  assert.strictEqual(seller.verified, true);
});

test('rowToSeller expone los valores guardados', () => {
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, avatarInitials, major, isBusiness, verified, tipo_cuenta,
       facebook_url, instagram_url, whatsapp_number, tiktok_url, twitter_url)
     VALUES (?, 'Negocio Con Redes', 'NR', '', 1, 1, 'negocio',
       'https://facebook.com/negocio', 'https://instagram.com/negocio', '5215512345678',
       'https://tiktok.com/@negocio', 'https://x.com/negocio')`,
  ).run('seller_social_lleno_1');

  const row = db.getDb().prepare('SELECT * FROM sellers WHERE id = ?').get('seller_social_lleno_1');
  const seller = db.rowToSeller(row);
  assert.strictEqual(seller.facebookUrl, 'https://facebook.com/negocio');
  assert.strictEqual(seller.instagramUrl, 'https://instagram.com/negocio');
  assert.strictEqual(seller.whatsappNumber, '5215512345678');
  assert.strictEqual(seller.tiktokUrl, 'https://tiktok.com/@negocio');
  assert.strictEqual(seller.twitterUrl, 'https://x.com/negocio');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test src/database.socialLinks.test.js`
Expected: FAIL — columns don't exist yet, `rowToSeller` doesn't return the new keys (first assertion mismatch or SQLITE_ERROR on INSERT with unknown column).

- [ ] **Step 3: Add migration 27 in `backend/src/database.js`**

Insert immediately before line 731 (`console.log('🔄 Migración de schema completada');`):

```js
  // 27. Redes sociales del negocio (Facebook, Instagram, WhatsApp, TikTok,
  //     X/Twitter): todas opcionales, solo tienen sentido cuando isBusiness.
  //     whatsapp_number guarda dígitos crudos con código de país, no la URL
  //     wa.me completa — así la validación es un regex simple y el cliente
  //     arma el link de forma determinista: https://wa.me/<número>. Ver
  //     docs/superpowers/specs/2026-08-08-business-social-links-design.md.
  const sellerColsSocial = db.prepare("PRAGMA table_info('sellers')").all();
  const socialColumns = ['facebook_url', 'instagram_url', 'whatsapp_number', 'tiktok_url', 'twitter_url'];
  for (const column of socialColumns) {
    if (!sellerColsSocial.some(c => c.name === column)) {
      db.exec(`ALTER TABLE sellers ADD COLUMN ${column} TEXT`);
    }
  }
```

- [ ] **Step 4: Extend `rowToSeller` in `backend/src/database.js`**

Add right after `paymentMethods: JSON.parse(row.paymentMethods || '[]'),` (line 876), still inside the returned object, before the closing `};`:

```js
    facebookUrl: row.facebook_url || null,
    instagramUrl: row.instagram_url || null,
    whatsappNumber: row.whatsapp_number || null,
    tiktokUrl: row.tiktok_url || null,
    twitterUrl: row.twitter_url || null,
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd backend && node --test src/database.socialLinks.test.js`
Expected: PASS (all 3 tests)

- [ ] **Step 6: Run the full backend suite to confirm no regression**

Run: `cd backend && npm test`
Expected: PASS (all existing suites, including `database.*.test.js`, still green)

- [ ] **Step 7: Commit**

```bash
git add backend/src/database.js backend/src/database.socialLinks.test.js
git commit -m "$(cat <<'EOF'
feat(backend): add social link columns to sellers table

Migration 27 adds facebook_url, instagram_url, whatsapp_number,
tiktok_url, twitter_url to sellers (all nullable) and extends
rowToSeller to expose them. whatsapp_number stores raw digits with
country code, not a full wa.me URL.
EOF
)"
```

---

### Task 2: Server-side validators for the 5 fields

**Files:**
- Modify: `backend/src/validation/sellerProfile.js`
- Create: `backend/src/validation/sellerProfile.socialLinks.test.js`

**Interfaces:**
- Consumes: nothing new (standalone).
- Produces: `validateSocialUrl(platform, url)` → `{ error: string } | { value: string | null }`, where `platform` is one of `'facebook' | 'instagram' | 'tiktok' | 'twitter'`.
- Produces: `validateWhatsappNumber(number)` → `{ error: string } | { value: string | null }`.
- Produces: exported constant `SOCIAL_PLATFORMS = ['facebook', 'instagram', 'tiktok', 'twitter']` for Task 3 to iterate over.

- [ ] **Step 1: Write the failing test**

```js
// backend/src/validation/sellerProfile.socialLinks.test.js
const test = require('node:test');
const assert = require('node:assert');
const { validateSocialUrl, validateWhatsappNumber } = require('./sellerProfile');

test('acepta una URL https del dominio correcto', () => {
  assert.deepStrictEqual(
    validateSocialUrl('facebook', 'https://facebook.com/minegocio'),
    { value: 'https://facebook.com/minegocio' },
  );
  assert.deepStrictEqual(
    validateSocialUrl('instagram', 'https://www.instagram.com/minegocio'),
    { value: 'https://www.instagram.com/minegocio' },
  );
  assert.deepStrictEqual(
    validateSocialUrl('twitter', 'https://x.com/minegocio'),
    { value: 'https://x.com/minegocio' },
  );
});

test('rechaza una URL de otra plataforma pegada en el campo equivocado', () => {
  const result = validateSocialUrl('instagram', 'https://facebook.com/minegocio');
  assert.ok(result.error);
  assert.match(result.error, /Instagram/);
});

test('rechaza un hostname que solo contiene el dominio como substring (bypass)', () => {
  const result = validateSocialUrl('facebook', 'https://facebook.com.evil.example/phish');
  assert.ok(result.error);
});

test('rechaza http (no https)', () => {
  const result = validateSocialUrl('tiktok', 'http://tiktok.com/@minegocio');
  assert.ok(result.error);
});

test('rechaza un valor que no es una URL', () => {
  const result = validateSocialUrl('twitter', 'no es un link');
  assert.ok(result.error);
});

test('vacío limpia el campo (value: null), no es error', () => {
  assert.deepStrictEqual(validateSocialUrl('facebook', ''), { value: null });
  assert.deepStrictEqual(validateSocialUrl('facebook', undefined), { value: null });
  assert.deepStrictEqual(validateSocialUrl('facebook', null), { value: null });
});

test('rechaza una URL más larga de 200 caracteres', () => {
  const largo = 'https://facebook.com/' + 'a'.repeat(200);
  const result = validateSocialUrl('facebook', largo);
  assert.ok(result.error);
});

test('WhatsApp: acepta solo dígitos con código de país', () => {
  assert.deepStrictEqual(validateWhatsappNumber('5215512345678'), { value: '5215512345678' });
});

test('WhatsApp: rechaza el signo + y espacios', () => {
  assert.ok(validateWhatsappNumber('+52 155 1234 5678').error);
});

test('WhatsApp: rechaza una URL wa.me completa', () => {
  assert.ok(validateWhatsappNumber('https://wa.me/5215512345678').error);
});

test('WhatsApp: rechaza menos de 10 dígitos', () => {
  assert.ok(validateWhatsappNumber('123').error);
});

test('WhatsApp: vacío limpia el campo', () => {
  assert.deepStrictEqual(validateWhatsappNumber(''), { value: null });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test src/validation/sellerProfile.socialLinks.test.js`
Expected: FAIL — `validateSocialUrl`/`validateWhatsappNumber` are `undefined`.

- [ ] **Step 3: Implement the validators**

In `backend/src/validation/sellerProfile.js`, add after `validatePaymentMethods` (before the closing `module.exports`):

```js
const MAX_SOCIAL_URL_LENGTH = 200;
const WHATSAPP_NUMBER_REGEX = /^\d{10,15}$/;

const SOCIAL_PLATFORMS = ['facebook', 'instagram', 'tiktok', 'twitter'];

const SOCIAL_URL_HOSTS = {
  facebook: new Set(['facebook.com', 'www.facebook.com', 'fb.com', 'm.facebook.com']),
  instagram: new Set(['instagram.com', 'www.instagram.com']),
  tiktok: new Set(['tiktok.com', 'www.tiktok.com']),
  twitter: new Set(['twitter.com', 'www.twitter.com', 'x.com', 'www.x.com']),
};

const SOCIAL_URL_LABELS = {
  facebook: 'Facebook',
  instagram: 'Instagram',
  tiktok: 'TikTok',
  twitter: 'X/Twitter',
};

// Link de red social del negocio: opcional. '' limpia el campo (vuelve a
// NULL). El hostname se compara por igualdad exacta contra una lista fija
// (no "contiene"): un "contiene" dejaría pasar
// https://facebook.com.evil.example/ porque la substring "facebook.com"
// aparece en un hostname que en realidad no es de Facebook.
function validateSocialUrl(platform, url) {
  if (url === undefined || url === null || url === '') return { value: null };
  if (typeof url !== 'string') {
    return { error: `El link de ${SOCIAL_URL_LABELS[platform]} no es válido` };
  }
  const trimmed = url.trim();
  if (trimmed.length > MAX_SOCIAL_URL_LENGTH) {
    return { error: `El link de ${SOCIAL_URL_LABELS[platform]} no puede superar ${MAX_SOCIAL_URL_LENGTH} caracteres` };
  }
  let parsed;
  try {
    parsed = new URL(trimmed);
  } catch {
    return { error: `El link de ${SOCIAL_URL_LABELS[platform]} no es una dirección web válida` };
  }
  if (parsed.protocol !== 'https:') {
    return { error: `El link de ${SOCIAL_URL_LABELS[platform]} debe empezar con https://` };
  }
  if (!SOCIAL_URL_HOSTS[platform].has(parsed.hostname.toLowerCase())) {
    return { error: `El link debe ser de ${SOCIAL_URL_LABELS[platform]}` };
  }
  return { value: trimmed };
}

// Número de WhatsApp del negocio: opcional. Solo dígitos con código de país
// incluido (ej. "5215512345678"), sin '+'/espacios/guiones. '' limpia el
// campo. Ver el design doc para por qué no se guarda la URL wa.me completa.
function validateWhatsappNumber(number) {
  if (number === undefined || number === null || number === '') return { value: null };
  if (typeof number !== 'string' || !WHATSAPP_NUMBER_REGEX.test(number.trim())) {
    return { error: 'El número de WhatsApp debe tener solo dígitos con código de país (10 a 15 dígitos)' };
  }
  return { value: number.trim() };
}
```

Update `module.exports` to add: `SOCIAL_PLATFORMS, validateSocialUrl, validateWhatsappNumber,`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test src/validation/sellerProfile.socialLinks.test.js`
Expected: PASS (all 12 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/src/validation/sellerProfile.js backend/src/validation/sellerProfile.socialLinks.test.js
git commit -m "$(cat <<'EOF'
feat(backend): add validators for business social link fields

Per-platform hostname whitelist (exact match, not substring, to
avoid a facebook.com.evil.example bypass) for the 4 URL fields, and
a digits-only regex for whatsapp_number.
EOF
)"
```

---

### Task 3: Wire the fields into `PATCH /api/sellers/:id`

**Files:**
- Modify: `backend/src/routes/sellers.js:62-137`
- Create: `backend/src/routes/sellers.test.js`

**Interfaces:**
- Consumes: `validateSocialUrl(platform, url)`, `validateWhatsappNumber(number)`, `SOCIAL_PLATFORMS` from Task 2 (`../validation/sellerProfile`).
- Consumes: `rowToSeller` fields from Task 1 (via `sellers`/`db` already wired in this file).
- Produces: request body accepts `facebookUrl`, `instagramUrl`, `whatsappNumber`, `tiktokUrl`, `twitterUrl` (all optional strings), applied only when `seller.isBusiness`.

- [ ] **Step 1: Write the failing integration test**

```js
// backend/src/routes/sellers.test.js
//
// Integración contra un servidor Express real y una SQLite temporal con el
// schema real (mismo patrón que routes/verificacion.test.js).

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-sellers-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

const express = require('express');
const db = require('../database');
const { generateToken } = require('../auth');
const sellersRoute = require('./sellers');

db.initDatabase();

let baseUrl;
let servidor;

test.before(async () => {
  const app = express();
  app.use(express.json());
  sellersRoute.register(app);
  servidor = http.createServer(app);
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  await new Promise(r => servidor.close(r));
});

let contador = 0;

function crearVendedor({ isBusiness }) {
  const id = `seller_test_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, avatarInitials, major, isBusiness, verified, tipo_cuenta)
     VALUES (?, ?, 'TT', '', ?, 1, ?)`,
  ).run(id, `Test ${id}`, isBusiness ? 1 : 0, isBusiness ? 'negocio' : 'estudiante');
  return { id, token: generateToken(id) };
}

async function patch(id, token, body) {
  const res = await fetch(`${baseUrl}/api/sellers/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

async function get(id, token) {
  const res = await fetch(`${baseUrl}/api/sellers/${id}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  return { status: res.status, body: await res.json() };
}

test('un negocio guarda sus redes sociales y las ve reflejadas en su perfil público', async () => {
  const negocio = crearVendedor({ isBusiness: true });

  const patchRes = await patch(negocio.id, negocio.token, {
    facebookUrl: 'https://facebook.com/minegocio',
    instagramUrl: 'https://instagram.com/minegocio',
    whatsappNumber: '5215512345678',
    tiktokUrl: 'https://tiktok.com/@minegocio',
    twitterUrl: 'https://x.com/minegocio',
  });
  assert.strictEqual(patchRes.status, 200);
  assert.strictEqual(patchRes.body.facebookUrl, 'https://facebook.com/minegocio');
  assert.strictEqual(patchRes.body.whatsappNumber, '5215512345678');

  const publicRes = await get(negocio.id);
  assert.strictEqual(publicRes.status, 200);
  assert.strictEqual(publicRes.body.instagramUrl, 'https://instagram.com/minegocio');
  assert.strictEqual(publicRes.body.tiktokUrl, 'https://tiktok.com/@minegocio');
  assert.strictEqual(publicRes.body.twitterUrl, 'https://x.com/minegocio');
});

test('actualizar solo un campo de red social no borra los demás (actualización parcial)', async () => {
  const negocio = crearVendedor({ isBusiness: true });
  await patch(negocio.id, negocio.token, {
    facebookUrl: 'https://facebook.com/minegocio',
    instagramUrl: 'https://instagram.com/minegocio',
  });

  const segundo = await patch(negocio.id, negocio.token, {
    instagramUrl: 'https://instagram.com/nuevo',
  });
  assert.strictEqual(segundo.status, 200);
  assert.strictEqual(segundo.body.facebookUrl, 'https://facebook.com/minegocio');
  assert.strictEqual(segundo.body.instagramUrl, 'https://instagram.com/nuevo');
});

test('mandar "" en un campo ya lleno lo limpia a null', async () => {
  const negocio = crearVendedor({ isBusiness: true });
  await patch(negocio.id, negocio.token, { facebookUrl: 'https://facebook.com/minegocio' });

  const limpiado = await patch(negocio.id, negocio.token, { facebookUrl: '' });
  assert.strictEqual(limpiado.status, 200);
  assert.strictEqual(limpiado.body.facebookUrl, null);
});

test('rechaza un link de la plataforma equivocada con mensaje claro', async () => {
  const negocio = crearVendedor({ isBusiness: true });
  const res = await patch(negocio.id, negocio.token, {
    instagramUrl: 'https://facebook.com/minegocio',
  });
  assert.strictEqual(res.status, 400);
  assert.match(res.body.error, /Instagram/);
});

test('rechaza un whatsappNumber con formato inválido', async () => {
  const negocio = crearVendedor({ isBusiness: true });
  const res = await patch(negocio.id, negocio.token, { whatsappNumber: '+52 1234' });
  assert.strictEqual(res.status, 400);
});

test('una cuenta que no es negocio no puede guardar redes sociales', async () => {
  const noNegocio = crearVendedor({ isBusiness: false });
  const res = await patch(noNegocio.id, noNegocio.token, {
    facebookUrl: 'https://facebook.com/algo',
  });
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.facebookUrl, undefined === res.body.facebookUrl ? res.body.facebookUrl : null);
  const row = db.getDb().prepare('SELECT facebook_url FROM sellers WHERE id = ?').get(noNegocio.id);
  assert.strictEqual(row.facebook_url, null);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test src/routes/sellers.test.js`
Expected: FAIL — PATCH accepts the fields but they're silently dropped (not in destructure/validation/apply), so responses lack `facebookUrl` etc. and rows stay NULL for the first several assertions.

- [ ] **Step 3: Implement in `backend/src/routes/sellers.js`**

Add to the import block (after `validatePaymentMethods,` inside the `require('../validation/sellerProfile')` destructure, line 15):

```js
  validateSocialUrl,
  validateWhatsappNumber,
```

Extend the body destructure on line 62:

```js
    const {
      name, phone, businessDescription, businessCategory, businessHours,
      locationLat, locationLng, paymentMethods,
      facebookUrl, instagramUrl, whatsappNumber, tiktokUrl, twitterUrl,
    } = req.body;
```

Inside the `if (seller.isBusiness) { ... }` validation block (after the `locationLat`/`locationLng` handling, before its closing `}` around line 103), add:

```js
      let normalizedFacebook, normalizedInstagram, normalizedTiktok, normalizedTwitter, normalizedWhatsapp;
      if (facebookUrl !== undefined) {
        const r = validateSocialUrl('facebook', facebookUrl);
        if (r.error) return res.status(400).json({ error: r.error });
        normalizedFacebook = r.value;
      }
      if (instagramUrl !== undefined) {
        const r = validateSocialUrl('instagram', instagramUrl);
        if (r.error) return res.status(400).json({ error: r.error });
        normalizedInstagram = r.value;
      }
      if (tiktokUrl !== undefined) {
        const r = validateSocialUrl('tiktok', tiktokUrl);
        if (r.error) return res.status(400).json({ error: r.error });
        normalizedTiktok = r.value;
      }
      if (twitterUrl !== undefined) {
        const r = validateSocialUrl('twitter', twitterUrl);
        if (r.error) return res.status(400).json({ error: r.error });
        normalizedTwitter = r.value;
      }
      if (whatsappNumber !== undefined) {
        const r = validateWhatsappNumber(whatsappNumber);
        if (r.error) return res.status(400).json({ error: r.error });
        normalizedWhatsapp = r.value;
      }
```

These `normalized*` variables are declared with `let` inside the `if (seller.isBusiness)` block, so they need to be visible in the apply section too — move their `let` declarations up next to `let normalizedHours;` / `let normalizedLocation;` (around line 83-84) instead, i.e.:

```js
    let normalizedHours;
    let normalizedLocation;
    let normalizedFacebook, normalizedInstagram, normalizedTiktok, normalizedTwitter, normalizedWhatsapp;
```

and drop the `let` keyword from the block added above (plain assignment). Then in the apply section (`if (seller.isBusiness) { ... }` around line 119-133), add after the `normalizedLocation` block:

```js
      if (normalizedFacebook !== undefined) {
        updateSellerField(seller.id, 'facebook_url', normalizedFacebook);
      }
      if (normalizedInstagram !== undefined) {
        updateSellerField(seller.id, 'instagram_url', normalizedInstagram);
      }
      if (normalizedTiktok !== undefined) {
        updateSellerField(seller.id, 'tiktok_url', normalizedTiktok);
      }
      if (normalizedTwitter !== undefined) {
        updateSellerField(seller.id, 'twitter_url', normalizedTwitter);
      }
      if (normalizedWhatsapp !== undefined) {
        updateSellerField(seller.id, 'whatsapp_number', normalizedWhatsapp);
      }
```

No changes are needed for `GET /api/sellers/:id` — it returns `seller` straight from the in-memory `sellers` array, which is rebuilt from `rowToSeller` (Task 1) by `updateSellerField`, so the new keys appear automatically.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test src/routes/sellers.test.js`
Expected: PASS (all 6 tests)

- [ ] **Step 5: Run the full backend suite**

Run: `cd backend && npm test`
Expected: PASS (no regressions in `verificacion.test.js`, `public.test.js`, etc.)

- [ ] **Step 6: Commit**

```bash
git add backend/src/routes/sellers.js backend/src/routes/sellers.test.js
git commit -m "$(cat <<'EOF'
feat(backend): accept business social links in PATCH /api/sellers/:id

Extends the existing business-only field gating (same pattern as
businessDescription/businessHours) to the 5 new social link fields.
GET /api/sellers/:id needed no change — it already serializes
through rowToSeller.
EOF
)"
```

---

### Task 4: Flutter `Seller` model — parse the new fields

**Files:**
- Modify: `lib/models.dart:149-254`
- Create: `test/seller_social_links_test.dart`

**Interfaces:**
- Produces: `Seller.facebookUrl`, `.instagramUrl`, `.whatsappNumber`, `.tiktokUrl`, `.twitterUrl` — all `String?`.
- Produces: `Seller.fromJson` reads `facebookUrl`/`instagramUrl`/`whatsappNumber`/`tiktokUrl`/`twitterUrl` from the JSON map.

- [ ] **Step 1: Write the failing test**

```dart
// test/seller_social_links_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/models.dart';

void main() {
  test('Seller.fromJson lee los 5 campos de redes sociales', () {
    final seller = Seller.fromJson({
      'id': 's1',
      'name': 'Negocio Test',
      'avatarInitials': 'NT',
      'major': '',
      'isBusiness': true,
      'rating': 4.5,
      'reviews': 10,
      'verified': true,
      'facebookUrl': 'https://facebook.com/negocio',
      'instagramUrl': 'https://instagram.com/negocio',
      'whatsappNumber': '5215512345678',
      'tiktokUrl': 'https://tiktok.com/@negocio',
      'twitterUrl': 'https://x.com/negocio',
    });

    expect(seller.facebookUrl, 'https://facebook.com/negocio');
    expect(seller.instagramUrl, 'https://instagram.com/negocio');
    expect(seller.whatsappNumber, '5215512345678');
    expect(seller.tiktokUrl, 'https://tiktok.com/@negocio');
    expect(seller.twitterUrl, 'https://x.com/negocio');
  });

  test('Seller.fromJson deja los campos en null cuando el backend no los manda', () {
    final seller = Seller.fromJson({
      'id': 's2',
      'name': 'Negocio Viejo',
      'avatarInitials': 'NV',
      'major': '',
      'isBusiness': true,
      'rating': 0,
      'reviews': 0,
      'verified': true,
    });

    expect(seller.facebookUrl, isNull);
    expect(seller.instagramUrl, isNull);
    expect(seller.whatsappNumber, isNull);
    expect(seller.tiktokUrl, isNull);
    expect(seller.twitterUrl, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/seller_social_links_test.dart`
Expected: FAIL — `The getter 'facebookUrl' isn't defined for the type 'Seller'` (compile error).

- [ ] **Step 3: Implement in `lib/models.dart`**

Add to the constructor parameter list (after `this.tipoVerificacion,` at line 169):

```dart
    this.facebookUrl,
    this.instagramUrl,
    this.whatsappNumber,
    this.tiktokUrl,
    this.twitterUrl,
```

Add to `Seller.fromJson` (after `tipoVerificacion: json['tipoVerificacion'] as String?,` at line 198):

```dart
      facebookUrl: json['facebookUrl'] as String?,
      instagramUrl: json['instagramUrl'] as String?,
      whatsappNumber: json['whatsappNumber'] as String?,
      tiktokUrl: json['tiktokUrl'] as String?,
      twitterUrl: json['twitterUrl'] as String?,
```

Add the fields (after `final String? tipoVerificacion;` at line 222):

```dart
  /// Link de Facebook del negocio. Solo tiene valor cuando [isBusiness].
  final String? facebookUrl;

  /// Link de Instagram del negocio. Solo tiene valor cuando [isBusiness].
  final String? instagramUrl;

  /// Número de WhatsApp del negocio: dígitos con código de país, sin '+' ni
  /// espacios (ej. "5215512345678"). El link se arma como
  /// https://wa.me/<whatsappNumber>. Solo tiene valor cuando [isBusiness].
  final String? whatsappNumber;

  /// Link de TikTok del negocio. Solo tiene valor cuando [isBusiness].
  final String? tiktokUrl;

  /// Link de X/Twitter del negocio. Solo tiene valor cuando [isBusiness].
  final String? twitterUrl;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/seller_social_links_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/models.dart test/seller_social_links_test.dart
git commit -m "$(cat <<'EOF'
feat(models): parse business social link fields on Seller
EOF
)"
```

---

### Task 5: Client-side mirror validators

**Files:**
- Create: `lib/validation/social_links.dart`
- Create: `test/social_links_validation_test.dart`

**Interfaces:**
- Produces: `String? validateSocialUrl(String platform, String value)` — mirrors backend rules; `platform` ∈ `{'facebook','instagram','tiktok','twitter'}`; returns `null` when valid (including empty string), an error message otherwise.
- Produces: `String? validateWhatsappNumber(String value)` — same contract.
- Produces: `const socialUrlHosts` map and `socialUrlLabels` map (platform → human label), reused by Task 7's placeholders/error text.

- [ ] **Step 1: Write the failing test**

```dart
// test/social_links_validation_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/validation/social_links.dart';

void main() {
  test('acepta una URL https del dominio correcto', () {
    expect(validateSocialUrl('facebook', 'https://facebook.com/minegocio'), isNull);
    expect(validateSocialUrl('twitter', 'https://x.com/minegocio'), isNull);
  });

  test('vacío es válido (campo opcional)', () {
    expect(validateSocialUrl('facebook', ''), isNull);
    expect(validateWhatsappNumber(''), isNull);
  });

  test('rechaza el dominio de otra plataforma', () {
    expect(validateSocialUrl('instagram', 'https://facebook.com/minegocio'), isNotNull);
  });

  test('rechaza http', () {
    expect(validateSocialUrl('tiktok', 'http://tiktok.com/@minegocio'), isNotNull);
  });

  test('WhatsApp: acepta solo dígitos con código de país', () {
    expect(validateWhatsappNumber('5215512345678'), isNull);
  });

  test('WhatsApp: rechaza el signo + y espacios', () {
    expect(validateWhatsappNumber('+52 155 1234 5678'), isNotNull);
  });

  test('WhatsApp: rechaza menos de 10 dígitos', () {
    expect(validateWhatsappNumber('123'), isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/social_links_validation_test.dart`
Expected: FAIL — `lib/validation/social_links.dart` doesn't exist (import error).

- [ ] **Step 3: Implement `lib/validation/social_links.dart`**

```dart
/// Validación de redes sociales del negocio, espejo de
/// backend/src/validation/sellerProfile.js (validateSocialUrl /
/// validateWhatsappNumber) para dar feedback inmediato en el editor sin
/// esperar la respuesta del servidor. La validación real y autoritativa
/// sigue viviendo en el backend.
library;

const socialUrlHosts = <String, Set<String>>{
  'facebook': {'facebook.com', 'www.facebook.com', 'fb.com', 'm.facebook.com'},
  'instagram': {'instagram.com', 'www.instagram.com'},
  'tiktok': {'tiktok.com', 'www.tiktok.com'},
  'twitter': {'twitter.com', 'www.twitter.com', 'x.com', 'www.x.com'},
};

const socialUrlLabels = <String, String>{
  'facebook': 'Facebook',
  'instagram': 'Instagram',
  'tiktok': 'TikTok',
  'twitter': 'X/Twitter',
};

const _maxSocialUrlLength = 200;
final _whatsappNumberRegex = RegExp(r'^\d{10,15}$');

/// Devuelve el mensaje de error, o null si [value] es válido (vacío incluido).
String? validateSocialUrl(String platform, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final label = socialUrlLabels[platform]!;
  if (trimmed.length > _maxSocialUrlLength) {
    return 'El link de $label no puede superar $_maxSocialUrlLength caracteres';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return 'El link de $label no es una dirección web válida';
  }
  if (uri.scheme != 'https') {
    return 'El link de $label debe empezar con https://';
  }
  if (!socialUrlHosts[platform]!.contains(uri.host.toLowerCase())) {
    return 'El link debe ser de $label';
  }
  return null;
}

/// Devuelve el mensaje de error, o null si [value] es válido (vacío incluido).
String? validateWhatsappNumber(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (!_whatsappNumberRegex.hasMatch(trimmed)) {
    return 'El número de WhatsApp debe tener solo dígitos con código de país (10 a 15 dígitos)';
  }
  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/social_links_validation_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/validation/social_links.dart test/social_links_validation_test.dart
git commit -m "$(cat <<'EOF'
feat(validation): add client-side mirror validators for social links
EOF
)"
```

---

### Task 6: `ApiService` + `AuthProvider` plumbing

**Files:**
- Modify: `lib/services/api_service.dart:921-956` (`updateSellerProfile`)
- Modify: `lib/providers/auth_provider.dart:492-536` (`updateProfile`)

**Interfaces:**
- Consumes: `Seller` fields from Task 4.
- Produces: `ApiService.updateSellerProfile({..., String? facebookUrl, String? instagramUrl, String? whatsappNumber, String? tiktokUrl, String? twitterUrl})` — same optional/only-if-non-null-adds-to-body pattern as existing params.
- Produces: `AuthProvider.updateProfile({..., String? facebookUrl, String? instagramUrl, String? whatsappNumber, String? tiktokUrl, String? twitterUrl})` — forwards to `ApiService.updateSellerProfile` when any profile field is present.

This task is thin plumbing with no independent test in this codebase (mirrors the existing untested state of `businessDescription`/`businessHours` wiring in these two files) — it's exercised end-to-end by Task 7's manual verification.

- [ ] **Step 1: Extend `ApiService.updateSellerProfile` in `lib/services/api_service.dart`**

Add parameters to the signature (after `List<String>? paymentMethods,` at line 930):

```dart
    String? facebookUrl,
    String? instagramUrl,
    String? whatsappNumber,
    String? tiktokUrl,
    String? twitterUrl,
```

Add to the body-building block (after `if (paymentMethods != null) body['paymentMethods'] = paymentMethods;` at line 945):

```dart
    if (facebookUrl != null) body['facebookUrl'] = facebookUrl;
    if (instagramUrl != null) body['instagramUrl'] = instagramUrl;
    if (whatsappNumber != null) body['whatsappNumber'] = whatsappNumber;
    if (tiktokUrl != null) body['tiktokUrl'] = tiktokUrl;
    if (twitterUrl != null) body['twitterUrl'] = twitterUrl;
```

- [ ] **Step 2: Extend `AuthProvider.updateProfile` in `lib/providers/auth_provider.dart`**

Add parameters to the signature (after `List<String>? paymentMethods,` at line 501):

```dart
    String? facebookUrl,
    String? instagramUrl,
    String? whatsappNumber,
    String? tiktokUrl,
    String? twitterUrl,
```

Extend `hasProfileFields` (line 509-516) to also check the new params:

```dart
    final hasProfileFields =
        name != null ||
        phone != null ||
        businessDescription != null ||
        businessCategory != null ||
        businessHours != null ||
        (locationLat != null && locationLng != null) ||
        paymentMethods != null ||
        facebookUrl != null ||
        instagramUrl != null ||
        whatsappNumber != null ||
        tiktokUrl != null ||
        twitterUrl != null;
```

Add to the `ApiService.updateSellerProfile(...)` call (line 518-528):

```dart
        facebookUrl: facebookUrl,
        instagramUrl: instagramUrl,
        whatsappNumber: whatsappNumber,
        tiktokUrl: tiktokUrl,
        twitterUrl: twitterUrl,
```

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/services/api_service.dart lib/providers/auth_provider.dart`
Expected: No new errors/warnings.

- [ ] **Step 4: Commit**

```bash
git add lib/services/api_service.dart lib/providers/auth_provider.dart
git commit -m "$(cat <<'EOF'
feat(api): forward business social links through updateSellerProfile
EOF
)"
```

---

### Task 7: Editor UI — "Redes sociales" section

**Files:**
- Modify: `lib/screens/profile/edit_profile_screen.dart`

**Interfaces:**
- Consumes: `Seller.facebookUrl` etc. (Task 4), `validateSocialUrl`/`validateWhatsappNumber`/`socialUrlLabels` (Task 5), `AuthProvider.updateProfile(...)` (Task 6).

No isolated automated test for this task — it's a form wired into an existing screen with no current widget-test coverage (matches the untested state of the rest of this screen). Verified manually in Step 4.

- [ ] **Step 1: Add controllers and imports**

In `lib/screens/profile/edit_profile_screen.dart`, add to imports (after `import '../../widgets/static_mini_map.dart';` at line 14):

```dart
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../validation/social_links.dart';
```

Add controller fields (after `late Map<int, BusinessHoursRange> _businessHours;` at line 36):

```dart
  late final TextEditingController _facebookController;
  late final TextEditingController _instagramController;
  late final TextEditingController _whatsappController;
  late final TextEditingController _tiktokController;
  late final TextEditingController _twitterController;
```

In `initState` (after `_descriptionController = TextEditingController(...)` block, before `_selectedCategoryId = ...` at line 52):

```dart
    _facebookController = TextEditingController(
      text: widget.seller.facebookUrl ?? '',
    );
    _instagramController = TextEditingController(
      text: widget.seller.instagramUrl ?? '',
    );
    _whatsappController = TextEditingController(
      text: widget.seller.whatsappNumber ?? '',
    );
    _tiktokController = TextEditingController(
      text: widget.seller.tiktokUrl ?? '',
    );
    _twitterController = TextEditingController(
      text: widget.seller.twitterUrl ?? '',
    );
```

In `dispose` (after `_descriptionController.dispose();` at line 74):

```dart
    _facebookController.dispose();
    _instagramController.dispose();
    _whatsappController.dispose();
    _tiktokController.dispose();
    _twitterController.dispose();
```

- [ ] **Step 2: Pass the fields in `_save()`**

In `_save()`, extend the `auth.updateProfile(...)` call (after `paymentMethods: _selectedPaymentMethods.toList(),` at line 132):

```dart
        facebookUrl: _isBusiness ? _facebookController.text.trim() : null,
        instagramUrl: _isBusiness ? _instagramController.text.trim() : null,
        whatsappNumber: _isBusiness ? _whatsappController.text.trim() : null,
        tiktokUrl: _isBusiness ? _tiktokController.text.trim() : null,
        twitterUrl: _isBusiness ? _twitterController.text.trim() : null,
```

- [ ] **Step 3: Add the "Redes sociales" section to `build()`**

Inside the `if (_isBusiness) ...[` block, after the location `OutlinedButton.icon` (after line 315, still before the block's closing `],` at line 316), add:

```dart
                const SizedBox(height: 24),
                Text(
                  'Redes sociales (opcional)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: context.colors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _facebookController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Facebook',
                    hintText: 'facebook.com/tunegocio',
                    prefixIcon: Icon(FontAwesomeIcons.facebook, size: 20),
                  ),
                  validator: (v) => validateSocialUrl('facebook', v ?? ''),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _instagramController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Instagram',
                    hintText: 'instagram.com/tunegocio',
                    prefixIcon: Icon(FontAwesomeIcons.instagram, size: 20),
                  ),
                  validator: (v) => validateSocialUrl('instagram', v ?? ''),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _whatsappController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp',
                    hintText: '521XXXXXXXXXX (con código de país)',
                    prefixIcon: Icon(FontAwesomeIcons.whatsapp, size: 20),
                  ),
                  validator: (v) => validateWhatsappNumber(v ?? ''),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _tiktokController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'TikTok',
                    hintText: 'tiktok.com/@tunegocio',
                    prefixIcon: Icon(FontAwesomeIcons.tiktok, size: 20),
                  ),
                  validator: (v) => validateSocialUrl('tiktok', v ?? ''),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _twitterController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'X / Twitter',
                    hintText: 'x.com/tunegocio',
                    prefixIcon: Icon(FontAwesomeIcons.xTwitter, size: 20),
                  ),
                  validator: (v) => validateSocialUrl('twitter', v ?? ''),
                ),
```

- [ ] **Step 4: Manual verification**

Run: `flutter analyze lib/screens/profile/edit_profile_screen.dart`
Expected: No errors.

Then run the app (`flutter run`), log in as a verified business account, open the profile editor, confirm:
- The "Redes sociales" section appears after "Ubicación del negocio" and before "Métodos de pago".
- Typing an invalid value (e.g. `http://facebook.com/x` or a bare word) shows an inline error without submitting.
- Saving with valid values succeeds and reopening the editor shows the saved values.
- The section does not appear at all for a non-business account.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/profile/edit_profile_screen.dart
git commit -m "$(cat <<'EOF'
feat(profile): add social links section to business profile editor

One field per platform with a mirrored client-side validator for
immediate feedback; saved as part of the existing profile submit.
EOF
)"
```

---

### Task 8: Public profile — social icons row

**Files:**
- Create: `lib/widgets/social_links_row.dart`
- Create: `test/social_links_row_test.dart`
- Modify: `lib/screens/seller_profile_screen.dart`

**Interfaces:**
- Consumes: `Seller` fields from Task 4.
- Produces: `List<SocialLinkEntry> buildSocialLinkEntries(Seller seller)` — pure function, one entry per non-empty field, empty list when none set.
- Produces: `class SocialLinksRow extends StatelessWidget` — renders nothing (`SizedBox.shrink()`) when `buildSocialLinkEntries` is empty.

- [ ] **Step 1: Write the failing test**

```dart
// test/social_links_row_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/social_links_row.dart';

Seller _seller({
  String? facebookUrl,
  String? instagramUrl,
  String? whatsappNumber,
  String? tiktokUrl,
  String? twitterUrl,
}) {
  return Seller(
    name: 'Negocio Test',
    avatarInitials: 'NT',
    major: '',
    isBusiness: true,
    rating: 0,
    reviews: 0,
    verified: true,
    facebookUrl: facebookUrl,
    instagramUrl: instagramUrl,
    whatsappNumber: whatsappNumber,
    tiktokUrl: tiktokUrl,
    twitterUrl: twitterUrl,
  );
}

void main() {
  test('sin ninguna red social, la lista de entradas está vacía', () {
    expect(buildSocialLinkEntries(_seller()), isEmpty);
  });

  test('solo agrega entradas para los campos llenos', () {
    final entries = buildSocialLinkEntries(
      _seller(facebookUrl: 'https://facebook.com/negocio', tiktokUrl: 'https://tiktok.com/@negocio'),
    );
    expect(entries.length, 2);
    expect(entries.map((e) => e.label), containsAll(['Facebook', 'TikTok']));
  });

  test('WhatsApp arma el link wa.me a partir del número crudo', () {
    final entries = buildSocialLinkEntries(_seller(whatsappNumber: '5215512345678'));
    expect(entries.single.url, 'https://wa.me/5215512345678');
    expect(entries.single.icon, FontAwesomeIcons.whatsapp);
  });

  test('las demás plataformas usan la URL guardada tal cual', () {
    final entries = buildSocialLinkEntries(_seller(instagramUrl: 'https://instagram.com/negocio'));
    expect(entries.single.url, 'https://instagram.com/negocio');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/social_links_row_test.dart`
Expected: FAIL — `lib/widgets/social_links_row.dart` doesn't exist.

- [ ] **Step 3: Implement `lib/widgets/social_links_row.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models.dart';

class SocialLinkEntry {
  const SocialLinkEntry({
    required this.icon,
    required this.url,
    required this.label,
  });

  final IconData icon;
  final String url;
  final String label;
}

/// Una entrada por cada red social que el negocio llenó, en orden fijo
/// (Facebook, Instagram, WhatsApp, TikTok, X/Twitter). Lista vacía si no
/// llenó ninguna — [SocialLinksRow] se omite por completo en ese caso.
List<SocialLinkEntry> buildSocialLinkEntries(Seller seller) {
  final entries = <SocialLinkEntry>[];
  final facebookUrl = seller.facebookUrl;
  if (facebookUrl != null && facebookUrl.isNotEmpty) {
    entries.add(SocialLinkEntry(icon: FontAwesomeIcons.facebook, url: facebookUrl, label: 'Facebook'));
  }
  final instagramUrl = seller.instagramUrl;
  if (instagramUrl != null && instagramUrl.isNotEmpty) {
    entries.add(SocialLinkEntry(icon: FontAwesomeIcons.instagram, url: instagramUrl, label: 'Instagram'));
  }
  final whatsappNumber = seller.whatsappNumber;
  if (whatsappNumber != null && whatsappNumber.isNotEmpty) {
    entries.add(SocialLinkEntry(
      icon: FontAwesomeIcons.whatsapp,
      url: 'https://wa.me/$whatsappNumber',
      label: 'WhatsApp',
    ));
  }
  final tiktokUrl = seller.tiktokUrl;
  if (tiktokUrl != null && tiktokUrl.isNotEmpty) {
    entries.add(SocialLinkEntry(icon: FontAwesomeIcons.tiktok, url: tiktokUrl, label: 'TikTok'));
  }
  final twitterUrl = seller.twitterUrl;
  if (twitterUrl != null && twitterUrl.isNotEmpty) {
    entries.add(SocialLinkEntry(icon: FontAwesomeIcons.xTwitter, url: twitterUrl, label: 'X / Twitter'));
  }
  return entries;
}

/// Fila de íconos de redes sociales del negocio. Se omite por completo
/// (sin espacio reservado) cuando el negocio no llenó ninguna.
class SocialLinksRow extends StatelessWidget {
  const SocialLinksRow({super.key, required this.seller});

  final Seller seller;

  Future<void> _open(BuildContext context, SocialLinkEntry entry) async {
    final uri = Uri.parse(entry.url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir ${entry.label}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = buildSocialLinkEntries(seller);
    if (entries.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: InkWell(
              onTap: () => _open(context, entry),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: FaIcon(entry.icon, size: 22, color: context.colors.ink),
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/social_links_row_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Wire `SocialLinksRow` into `lib/screens/seller_profile_screen.dart`**

Add import (after `import '../widgets/seller_schedule_location_row.dart';` at line 13):

```dart
import '../widgets/social_links_row.dart';
```

In `_buildContent`, insert right after the `Center(...)` block closes and before `if (hasOperationalInfo) [...]` (after line 236, i.e. right after the `),` that closes `Center(`):

```dart
        Center(child: SocialLinksRow(seller: seller)),
```

Add `const SizedBox(height: 16)` immediately after it so it doesn't collide with the operational-info block when both are present — full insertion:

```dart
        Center(child: SocialLinksRow(seller: seller)),
        if (buildSocialLinkEntries(seller).isNotEmpty) const SizedBox(height: 16),
```

(`buildSocialLinkEntries` needs to be imported too — it comes from the same `social_links_row.dart` import above.)

- [ ] **Step 6: Run test to verify no regressions**

Run: `flutter test test/social_links_row_test.dart test/seller_profile_skeleton_test.dart`
Expected: PASS

- [ ] **Step 7: Manual verification**

Run: `flutter analyze lib/screens/seller_profile_screen.dart lib/widgets/social_links_row.dart`
Expected: No errors.

Then run the app, open a business profile that has social links saved (via Task 7's editor), confirm:
- Only icons for filled platforms appear, horizontally laid out below the business info, above the hours/location row.
- Tapping WhatsApp opens `https://wa.me/<number>`; tapping the others opens the saved URL.
- A business with no social links shows no row and no empty gap.

- [ ] **Step 8: Commit**

```bash
git add lib/widgets/social_links_row.dart test/social_links_row_test.dart lib/screens/seller_profile_screen.dart
git commit -m "$(cat <<'EOF'
feat(profile): show business social links as tappable icons

Row is entirely omitted when the business set none. WhatsApp builds
its wa.me link from the stored raw number; the other platforms use
the stored URL directly.
EOF
)"
```

---

## Final Verification

- [ ] Run: `cd backend && npm test` — expect full green (including the 3 new test files).
- [ ] Run: `flutter test` — expect full green (including the 3 new test files).
- [ ] Run: `flutter analyze` — expect no new issues.
- [ ] Manually re-verify the golden path end to end: log in as a verified business, add all 5 social links in the editor, save, view the public profile, confirm all 5 icons appear and open the right destination; then clear one field and confirm its icon disappears from the public profile.
