# Redes sociales en perfil de negocio verificado

## Objetivo

Agregar campos de redes sociales (Facebook, Instagram, WhatsApp, TikTok, X/Twitter)
al perfil de negocio verificado. Solo negocios (`sellers.isBusiness = true`); no
aplica a estudiantes ni externos. Todos los campos opcionales.

## Base de datos

Se agregan columnas a `sellers` (no a `verificaciones`, que es la tabla de proceso
de onboarding/verificación y no la que alimenta el editor de perfil ni el perfil
público). Sigue el mismo patrón que `businessDescription`/`businessHours`, que ya
viven en `sellers` y se editan vía `PATCH /api/sellers/:id`.

Migración 27 en `backend/src/database.js`:

```sql
ALTER TABLE sellers ADD COLUMN facebook_url TEXT;
ALTER TABLE sellers ADD COLUMN instagram_url TEXT;
ALTER TABLE sellers ADD COLUMN whatsapp_number TEXT;
ALTER TABLE sellers ADD COLUMN tiktok_url TEXT;
ALTER TABLE sellers ADD COLUMN twitter_url TEXT;
```

Sin `DEFAULT` → SQLite deja NULL en filas existentes. No toca `verified`, `estado`
ni ninguna otra columna. Se aplica con el mismo guard de "columna ya existe, skip"
que usan las migraciones previas (`PRAGMA table_info`).

## Formato de WhatsApp

`whatsapp_number TEXT`: dígitos crudos con código de país (ej. `"5215512345678"`),
**no** la URL `wa.me/...` completa.

- Coherente con `sellers.phone`, que ya guarda números así.
- Validación determinista: `^\d{10,15}$`, sin `+`/espacios/guiones — evita parsear
  múltiples formatos de URL de WhatsApp (`wa.me/`, `api.whatsapp.com/send?phone=`,
  con o sin `+`, con query params).
- El cliente construye el link: `https://wa.me/$whatsapp_number`.
- Es un campo distinto de `sellers.phone` (un negocio puede querer un WhatsApp de
  atención distinto a su teléfono de cuenta).

## Validación server-side

Nuevos validadores en `backend/src/validation/sellerProfile.js`, mismo estilo que
`validateBusinessDescription` (retorna `null` o string de error), siguiendo el
patrón de `validarLinkRedSocial` en `backend/src/validation/verificacion.js`
(`new URL()`, exige `https:`, whitelist de hostname):

| Campo | Regla |
|---|---|
| `facebook_url` | HTTPS, hostname contiene `facebook.com` o `fb.com`, max 200 chars |
| `instagram_url` | HTTPS, hostname contiene `instagram.com`, max 200 chars |
| `tiktok_url` | HTTPS, hostname contiene `tiktok.com`, max 200 chars |
| `twitter_url` | HTTPS, hostname contiene `twitter.com` o `x.com`, max 200 chars |
| `whatsapp_number` | `^\d{10,15}$` |

Todos los campos son opcionales; string vacío se trata como NULL (permite borrar
un campo ya lleno). Validación aplicada inline en el handler, antes de escribir,
igual que el resto de `sellers.js`.

## Backend — endpoints

### `PATCH /api/sellers/:id` (extendido)

Nuevos campos opcionales en el body, gateados por `if (seller.isBusiness)` igual
que `businessDescription`/`businessCategory`/`businessHours` hoy:

```json
{
  "facebookUrl": "https://facebook.com/tunegocio",
  "instagramUrl": "https://instagram.com/tunegocio",
  "whatsappNumber": "5215512345678",
  "tiktokUrl": "https://tiktok.com/@tunegocio",
  "twitterUrl": "https://x.com/tunegocio"
}
```

Actualización parcial: solo se validan/escriben las claves presentes en el body;
omitir una clave no la borra.

### `GET /api/sellers/:id` (extendido)

`rowToSeller` en `backend/src/database.js` se extiende para incluir los 5 campos
nuevos (mismo shape que la respuesta de PATCH):

```json
{
  "id": "...", "name": "...", "isBusiness": true, "verified": true,
  "businessDescription": "...", "businessCategory": "...", "businessHours": {},
  "locationLat": 0.0, "locationLng": 0.0, "paymentMethods": [],
  "facebookUrl": null,
  "instagramUrl": "https://instagram.com/tunegocio",
  "whatsappNumber": null,
  "tiktokUrl": null,
  "twitterUrl": null
}
```

`null` si no está lleno o si el seller no es negocio. El cliente decide qué ícono
mostrar según qué campos vienen no-nulos.

Fuera de alcance: `GET /api/public/productos/:id` (usado solo por la web Next.js
para links compartidos de producto) no se toca — su sub-objeto `vendedor` no
incluye hoy ningún campo de URL y no fue pedido explícitamente.

## Frontend — editor de perfil (negocio)

`lib/screens/profile/edit_profile_screen.dart`: nueva sección "Redes sociales"
después de la sección de ubicación existente (mismo patrón `if (_isBusiness) ...`
que ya envuelve descripción/categoría/horario/ubicación), antes del botón guardar.
Un `TextFormField` por plataforma con ícono de prefijo:

| Campo | Ícono (FontAwesome, ya usado en `seller_profile_screen.dart`) | Placeholder |
|---|---|---|
| Facebook | `FontAwesomeIcons.facebook` | `facebook.com/tunegocio` |
| Instagram | `FontAwesomeIcons.instagram` | `instagram.com/tunegocio` |
| WhatsApp | `FontAwesomeIcons.whatsapp` | `521XXXXXXXXXX` |
| TikTok | `FontAwesomeIcons.tiktok` | `tiktok.com/@tunegocio` |
| X/Twitter | `FontAwesomeIcons.xTwitter` | `x.com/tunegocio` |

Validación en cliente espejo de la del backend (mismos regex/hostname checks),
mostrada como `errorText` del `TextFormField`, no bloqueante hasta submit. Se
envían como parte del mismo `ApiService.updateSellerProfile` call existente
(mismo submit, mismo request).

## Frontend — perfil público del negocio

`lib/screens/seller_profile_screen.dart`: fila horizontal de íconos debajo de la
info del negocio (nombre, badge `InsigniaVerificada`, ubicación), antes de la
sección de horarios/mapa (`SellerScheduleLocationRow`). Solo se renderizan los
íconos de campos no-nulos; si los 5 son null, la fila completa se omite (sin
`SizedBox` vacío). Cada ícono usa el patrón `url_launcher` ya establecido en el
proyecto (`Uri.parse` + `launchUrl(uri, mode: LaunchMode.externalApplication)`,
con snackbar de error si falla), igual que el botón de WhatsApp que ya existe en
esta misma pantalla. WhatsApp construye la URL como `https://wa.me/$whatsappNumber`.

Estética: íconos simples sin fondo pesado (`IconButton` con `Icon` o
`FaIcon` directo), tamaño ~22-24px, espaciado horizontal uniforme, sin bordes ni
contenedores — coherente con "less boxes, more air".
