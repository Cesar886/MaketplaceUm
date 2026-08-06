# Sistema de verificación de cuentas — 100% automático

## Contexto

Mercadito UM tiene tres tipos de cuenta y hoy un flujo de verificación **manual**
que quedó a medias: `verification_screen.dart` pide una foto de credencial
(estudiante) o de identificación oficial (particular), guarda un path *mock*
(`mock_credencial_<timestamp>.jpg`, L277) en el SQLite **local del dispositivo**
(`db_helper.dart`, tablas `student_verification` / `particular_verification`), y
deja al usuario en `verification_status = 'pendiente'` esperando a un admin que
llame a `DBHelper.resolveVerification` — método que **no tiene ninguna pantalla
de administración que lo invoque**. Es decir: nadie se verifica nunca.

Este diseño lo reemplaza por verificación automática, sin intervención humana,
con la autoridad en el backend.

### Estado del código, verificado (no supuesto)

**No existe tabla `users` en el backend.** La tabla real de usuarios es
`sellers` (`database.js` L24-39), con `id TEXT` de forma `u_<slug>_<sufijo>`
(`index.js` L260-262) y **ya tiene columna `verified INTEGER DEFAULT 0`**
(L35), que hoy siempre vale 0 y que ya leen `rowToSeller` (`database.js` L676),
`models.dart` L180/203, `home_screen.dart` L194/978 y
`product_detail_screen.dart` L1206.

La tabla `users` que existe vive solo en el **SQLite local de Flutter**
(`db_helper.dart` L41-56) y es, según el comentario en `auth_provider.dart`
L88-96, "solo una caché offline". Login y registro operan enteramente sobre
`sellers` (`index.js` L121 y L188).

**Tipos de cuenta:** el código usa `'estudiante' | 'particular' | 'negocio'`
(enum `AccountType` en `auth_provider.dart` L9, CHECK constraint en
`db_helper.dart` L47, `major` asignado en `index.js` L252-255). El tipo
"externo" del requerimiento es el `particular` existente.

**Correo institucional:** formato `<7 dígitos>@alumno.um.edu.mx`
(ej. `1220326@alumno.um.edu.mx`). Los 7 dígitos **son la matrícula**.

**Piezas reutilizables:** `LocationPickerScreen.open()`
(`location_picker.dart` L29-44) devuelve un `LatLng` y ya se usa para la
ubicación de perfil de negocio; `StaticMiniMap` para previsualizar el pin;
`validateLocation` y `validatePhone` (`validation/sellerProfile.js`);
`requireAuth` (`auth.js` L21).

**Dependencias:** el backend **no tiene** nodemailer, twilio, dotenv ni archivo
`.env`. Node v20.19.3 → `node:test` disponible sin instalar nada.

## Decisiones tomadas

| Decisión | Elección | Razón |
|---|---|---|
| Tabla de usuarios | Adaptar a `sellers`, **reusar `verified`** | Evita dos columnas booleanas que mantener en sync; la insignia funciona en toda la app sin tocar los call sites existentes |
| Nombre del 3er tipo | `particular` en DB/código, "externo" en UI y rutas | Cero migración; no rompe login/registro |
| Flujo manual anterior | Se elimina por completo | Una sola forma de verificarse |
| Envío de email | SMTP real vía env vars | El usuario tiene credenciales |
| Envío de SMS | Adaptador listo, modo dev | Twilio pendiente de contratar |
| Link de negocio | Whitelist de dominios estricta + HEAD tolerante | Facebook/Instagram bloquean bots (302 a login, 403, status 999); un HEAD que exija 200 rechazaría negocios legítimos |
| Matrícula | Debe coincidir con los 7 dígitos del correo | El correo ya prueba la matrícula; una discrepancia es error de captura o suplantación |

## Diseño

### 1. Migración de schema (`database.js`, migración #24)

Sigue el patrón existente de `runMigrations`: `PRAGMA table_info` para detectar,
`ALTER TABLE` para agregar, backfill con `UPDATE`.

```sql
ALTER TABLE sellers ADD COLUMN tipo_cuenta TEXT;
```

Backfill: `isBusiness = 1` → `'negocio'`; `major = 'Estudiante'` →
`'estudiante'`; resto → `'particular'`.

```sql
CREATE TABLE IF NOT EXISTS verificaciones (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  usuario_id TEXT NOT NULL UNIQUE REFERENCES sellers(id) ON DELETE CASCADE,
  tipo_cuenta TEXT NOT NULL CHECK(tipo_cuenta IN ('estudiante','negocio','particular')),
  estado TEXT NOT NULL DEFAULT 'pendiente' CHECK(estado IN ('pendiente','verificado','rechazado')),
  fecha_verificacion TEXT,
  creado_en TEXT NOT NULL,

  correo_institucional TEXT,
  matricula TEXT,
  codigo_otp_email TEXT,
  codigo_otp_email_expira TEXT,

  nombre_negocio TEXT,
  ubicacion_lat REAL,
  ubicacion_lng REAL,
  link_red_social TEXT,

  telefono TEXT,
  codigo_otp_sms TEXT,
  codigo_otp_sms_expira TEXT,

  motivo_rechazo TEXT,
  intentos_envio INTEGER NOT NULL DEFAULT 0,
  ventana_envio_inicio TEXT,
  intentos_confirmacion INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_verificaciones_correo ON verificaciones(correo_institucional);
CREATE INDEX IF NOT EXISTS idx_verificaciones_telefono ON verificaciones(telefono);
```

`UNIQUE(usuario_id)`: una fila por usuario. Cada solicitud hace upsert sobre
esa fila. `sellers.verified` queda como bandera rápida denormalizada; la fila
de `verificaciones` es el detalle.

**Fechas:** texto ISO-8601 UTC (`new Date().toISOString()`), consistente con
`locked_until` en `index.js` L146.

### 2. Servicios backend (archivos nuevos)

#### `src/services/otp.js`

```js
generarCodigo()        // 6 dígitos vía crypto.randomInt(0, 1_000_000), padStart
hashCodigo(codigo)     // sha256 hex
verificarCodigo(codigo, hashGuardado, expiraEn)
                       // → { ok } | { ok:false, razon:'expirado'|'incorrecto' }
                       // comparación con crypto.timingSafeEqual
```

Los OTP se guardan **hasheados**. Un dump de `mercadito_um.db` no debe permitir
verificar cuentas ajenas. Al confirmar con éxito, `codigo_otp_*` y
`codigo_otp_*_expira` se ponen a `NULL` (no reutilizable).

Vigencia: **10 minutos**.

#### `src/services/mailer.js` y `src/services/sms.js`

Misma interfaz: `async enviar(destino, codigo) → { enviado, modoDev }` y
`estaConfigurado()`.

- `mailer.js`: nodemailer con `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`,
  `SMTP_PASS`, `SMTP_FROM`. Mensaje en texto plano + HTML simple: código,
  vigencia de 10 minutos, aviso de ignorar si no fue solicitado.
- `sms.js`: si existen `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`,
  `TWILIO_FROM` usa Twilio; si no, modo dev.

**Modo dev** (sin credenciales y `NODE_ENV !== 'production'`): imprime el
código en consola del backend y el endpoint lo devuelve como `codigo_dev` en
la respuesta.

**En producción sin credenciales**: el endpoint responde **503** con
`{ error: 'El envío de <email|SMS> no está configurado.' }`. Nunca finge haber
enviado, y nunca expone `codigo_dev`.

Se agregan `nodemailer` y `dotenv` a `backend/package.json`; `twilio` se agrega
también (el adaptador lo importa de forma perezosa, así que su ausencia no
rompe el arranque). `require('dotenv').config()` al inicio de `index.js`, y
`backend/.env.example` documentando las variables. `.env` va a `.gitignore`.

#### `src/validation/verificacion.js` — validadores puros

Sin DB y sin red, para poder testearlos aislados. Devuelven `null` si es válido
o un `string` con el mensaje de error, siguiendo la convención de
`validation/sellerProfile.js`.

```js
validarCorreoInstitucional(correo)   // regex ^\d{7}@<dominio>$ contra whitelist
extraerMatriculaDeCorreo(correo)     // matrícula (string) de los 7 dígitos, o null
validarNombreNegocio(nombre)         // trim, >= 3 caracteres, <= 80
validarLinkRedSocial(link)           // URL bien formada + host en whitelist
normalizarTelefono(telefono)         // → E.164 o error
```

**Dominios de estudiante:** whitelist por defecto `['alumno.um.edu.mx']`,
sobreescribible con `VERIFICATION_STUDENT_DOMAINS` (lista separada por comas).
Se acepta el dominio exacto, no subdominios arbitrarios. Comparación en
minúsculas.

**Whitelist de hosts de red social:** `facebook.com`, `www.facebook.com`,
`m.facebook.com`, `fb.com`, `instagram.com`, `www.instagram.com`,
`maps.google.com`, `www.google.com/maps`, `goo.gl`, `maps.app.goo.gl`. Se
compara el `hostname` parseado con `new URL()`, no un `includes` sobre el
string (`instagram.com.phishing.net` no debe pasar). Solo `https:` y `http:`.

**Teléfono:** 10 dígitos MX → se antepone `+52` si viene sin lada; se acepta
también `+52...` ya formado. Se limpian espacios, guiones y paréntesis.

#### `src/services/linkCheck.js` y `src/services/redDestino.js`

`async verificarLink(url) → { ok, motivo }`. HEAD con `AbortController` y
timeout de **5 s**, User-Agent de navegador.

- `ok` si el status es `< 500` (incluye 2xx, 401, 403 y el 999 de bloqueo
  antibot).
- Falla solo con: timeout, error de DNS/red, `404`, `410`, o `5xx`.
- Si el HEAD falla con 405 (método no permitido), reintenta con GET y
  `Range: bytes=0-0`.

Motivo de la tolerancia: la validación fuerte es el dominio; el HEAD solo
descarta URLs inventadas dentro de un dominio válido.

**Defensa contra SSRF.** Esta es la única parte del sistema donde un dato del
usuario decide a qué dirección se conecta el servidor, y `maps.app.goo.gl` es
un acortador: puede redirigir a `127.0.0.1` o a `169.254.169.254` (metadata de
la nube). Aunque el endpoint solo devuelve "responde / no responde", ese
booleano alcanza para mapear qué servicios internos existen. Por eso:

- Las redirecciones se siguen **a mano** (`redirect: 'manual'`, máximo 5
  saltos), no automáticamente.
- **Cada salto** se resuelve por DNS y se rechaza si alguna de sus direcciones
  cae en loopback, RFC1918, link-local, CGNAT, ULA, multicast o reservado
  (`redDestino.js`, que también desenvuelve IPv4 mapeadas en IPv6 como
  `::ffff:127.0.0.1`).
- Se rechaza cualquier salto cuyo esquema no sea http/https.
- La whitelist solo acepta **https**, y quedan fuera los acortadores genéricos
  (`goo.gl`, `fb.me`), que redirigen a cualquier destino. `maps.app.goo.gl` se
  conserva porque es el formato que genera "Compartir" en la app de Maps —el
  caso de uso principal de un negocio— y su riesgo queda cubierto por la
  validación por salto.

`comprobarDestino` se inyecta como dependencia para poder testear el
comportamiento frente a redirecciones contra un servidor local (que por
definición vive en una dirección privada); el guardián real es el default.

### 3. Rate limiting y anti-fuerza-bruta

**Envío de OTP** — máximo **3 solicitudes cada 15 minutos**, contado con
`intentos_envio` + `ventana_envio_inicio` en la propia fila. Persistido en DB,
no en memoria: sobrevive reinicios de PM2 (`ecosystem.config.js`). Si la
ventana expiró, se reinicia el contador. Al agotarse: **429** con los minutos
restantes, igual que el lockout de login (`index.js` L133-138).

Además se cuenta **por destino**: un mismo correo/teléfono no puede recibir más
de 3 códigos cada 15 min aunque se soliciten desde cuentas distintas (evita
usar N cuentas para bombardear un número ajeno). De ahí los índices sobre
`correo_institucional` y `telefono`.

**Confirmación de OTP** — máximo **5 intentos por código**. Al sexto, el código
se invalida (`codigo_otp_* = NULL`) y hay que pedir uno nuevo. Sin esto, un OTP
de 6 dígitos con 10 minutos de vida es forzable por fuerza bruta; el límite de
*envío* no protege contra eso.

### 4. Endpoints (`src/routes/verificacion.js`)

Todos bajo `requireAuth`. **El `usuario_id` sale siempre de `req.user.id`,
nunca del body.** Se registran en `index.js` junto a las rutas existentes.

Guarda común en los 5 endpoints de solicitud/confirmación: si
`sellers.verified = 1` → **409** `{ error: 'Tu cuenta ya está verificada.' }`.

También se valida que el `tipo_cuenta` del usuario corresponda al endpoint: un
usuario `negocio` no puede verificarse por el flujo de estudiante → **403**.

| Endpoint | Body | Respuesta |
|---|---|---|
| `POST /api/verificacion/estudiante/solicitar` | `{ correo_institucional }` (la matrícula se extrae del correo) | `200 { enviado, expira_en, codigo_dev? }` · 400 validación · 409 correo ya usado por otra cuenta verificada · 429 · 503 |
| `POST /api/verificacion/estudiante/confirmar` | `{ codigo_otp }` | `200 { verificado:true, tipo_cuenta }` · 400 incorrecto/expirado con `intentos_restantes` |
| `POST /api/verificacion/negocio/solicitar` | `{ nombre_negocio, ubicacion_lat, ubicacion_lng, link_red_social }` | `200 { estado:'verificado' }` o `200 { estado:'rechazado', motivo_rechazo, campo }` |
| `POST /api/verificacion/externo/solicitar` | `{ telefono }` | igual que estudiante/solicitar |
| `POST /api/verificacion/externo/confirmar` | `{ codigo_otp }` | igual que estudiante/confirmar |
| `GET  /api/verificacion/estado` | — | `{ tipo_cuenta, estado, verificado, motivo_rechazo, campo_rechazado, puede_reintentar_en }` |

**Negocio** resuelve en la misma respuesta, sin cola. `campo` indica cuál dato
corregir (`nombre_negocio` \| `ubicacion` \| `link_red_social`) para que la app
pueda resaltar ese campo. El rechazo **no bloquea**: el usuario corrige y
vuelve a enviar (`estado` pasa de `rechazado` a `verificado` en el reintento).

Al verificar con éxito, en una sola transacción de `better-sqlite3`:
`verificaciones.estado = 'verificado'`, `fecha_verificacion = now`, códigos a
`NULL`, y `sellers.verified = 1`.

**Sanitización:** todos los inputs se pasan por `String()`, `trim()` y se
validan de longitud antes de tocar la DB. Todas las queries usan sentencias
preparadas (ya es el patrón del proyecto).

### 5. Flutter

#### `lib/services/api_service.dart`

Seis métodos nuevos siguiendo el patrón existente de la clase (headers con
token, manejo de error que lanza con el mensaje real del servidor).

#### `lib/screens/auth/verification_screen.dart` — reescrita

```dart
VerificationScreen({ required AccountType tipo, bool desdeRegistro = false })
```

Un solo `Scaffold` que renderiza el formulario según `tipo`, con widgets base
compartidos:

- `_CampoTexto` — envuelve `TextFormField` con el estilo ya usado en la
  pantalla (`prefixIcon`, `labelText`).
- `_BotonEnviarCodigo` — botón ancho completo con spinner, mismo estilo que el
  actual (L206-221).
- `_OtpInput` — 6 casillas, auto-avance, retroceso, pegado de código completo,
  autofill de SMS/email cuando el sistema lo ofrezca.
- `_CajaError` — extraída del bloque de error existente (L156-188).

**Estudiante:** correo institucional + matrícula → enviar → `_OtpInput` →
confirmar. Con reenvío que respeta el 429 (muestra cuenta regresiva).

**Negocio:** nombre + `LocationPickerScreen.open()` (pin previsualizado con
`StaticMiniMap`) + link. Un solo botón "Verificar negocio"; el resultado llega
en la misma respuesta. Si es rechazo, resalta el campo indicado por `campo`.

**Externo:** teléfono → enviar → `_OtpInput` → confirmar.

`desdeRegistro = true` → al terminar navega a `AccountCreatedScreen`
(comportamiento actual) y mantiene "Hacerlo después". `false` (desde perfil) →
hace `pop(true)` y el perfil refresca. Misma pantalla, mismo comportamiento de
verificación en ambos casos.

En modo dev, si la respuesta trae `codigo_dev`, se muestra en un aviso visible
para poder probar sin recibir el correo/SMS.

#### `lib/widgets/badges.dart` — `InsigniaVerificada`

```dart
InsigniaVerificada({ required AccountType tipo, bool compact = false })
```

Reusa el `_Badge` privado existente. Ícono `Icons.verified_rounded` para los
tres tipos; solo cambia el color y la etiqueta:

| Tipo | Color | Etiqueta |
|---|---|---|
| estudiante | `AppColors.primary` (Azul Piedra, `#3D5C70`) | Estudiante verificado |
| negocio | `AppColors.teal` (`#1F6B62`) | Negocio verificado |
| particular (externo) | `context.colors.muted` | Verificado |

(Los tres existen ya en `app_theme.dart` L12/21/28 — no se agregan colores
nuevos a la paleta. `teal` es además el color que ya usa el `VerifiedBadge`
actual, así que los negocios no cambian de aspecto.)

Mismo ícono a propósito: la diferencia de color comunica el tipo sin crear una
jerarquía de "más o menos confiable". En `compact` solo se muestra el ícono
coloreado (para tarjetas de producto).

Sustituye a `VerifiedBadge` (L73-88) y a los dos `Icon(Icons.verified_rounded)`
sueltos de `home_screen.dart` L978-982 y `product_detail_screen.dart`
L1206-1210. Se renderiza **solo si `seller.verified == true`**.

#### Propagación de `tipo_cuenta`

`rowToSeller` (`database.js` L676) expone `tipoCuenta`; `Seller` en
`models.dart` gana el campo (nullable, default `particular` al parsear JSON
viejo). Los mocks de `mock_data.dart` se ajustan.

#### `lib/providers/auth_provider.dart`

`isVerified` deja de leer `_currentUser['is_verified']` (caché local, L74) y
pasa a un campo alimentado por `GET /api/verificacion/estado`, consultado en
`tryAutoLogin`, tras login/registro y tras verificar. La caché local sigue
existiendo para el resto, pero **el backend es la autoridad de verificación**.

Se agregan `solicitarOtpEstudiante`, `confirmarOtpEstudiante`,
`verificarNegocio`, `solicitarOtpExterno`, `confirmarOtpExterno`,
`refrescarEstadoVerificacion`.

#### `lib/screens/profile_screen.dart`

Botón "Verificar cuenta" visible solo si `!auth.isVerified`, que abre
`VerificationScreen(tipo: auth.accountType)`. Si ya está verificado, muestra
`InsigniaVerificada` junto al nombre.

### 6. Código que se elimina

Con el flujo manual muerto (decisión "reemplazar por completo"):

- `db_helper.dart`: `submitStudentVerification`, `submitParticularVerification`,
  `resolveVerification`, `getPendingVerifications`, `skipVerification`, y las
  tablas `student_verification` / `particular_verification`. Las tablas se
  dejan de crear en `_createTables`; no se hace DROP en `_onUpgrade` (SQLite
  local, sin datos reales — solo paths mock; borrarlas no aporta y arriesga la
  migración de instalaciones existentes).
- `auth_provider.dart`: los tres métodos `submit*Verification` /
  `createBusinessProfile`-como-verificación y `skipVerification`.
  `createBusinessProfile` **se conserva** para el registro de negocio, que sí
  lo usa (L221-231) — solo se le quita el `verification_status = 'pendiente'`.
- `verification_screen.dart`: `_PhotoUploadTile` y los paths mock.
- `VerificationStatus` (enum, L11) y `verificationStatus` (getter, L72): quedan
  sin uso; se eliminan junto con la columna local `verification_status` como
  fuente de verdad.

### 7. Tests

**Backend** (`node:test`, built-in — cero dependencias nuevas). Los tests viven
junto a su fuente como `*.test.js` dentro de `src/`, y el script de
`package.json` pasa a `"test": "node --test src/"` (reemplaza el
`echo "Error: no test specified" && exit 1` actual):

- `validation/verificacion.test.js` — validadores puros: correo con dominio
  incorrecto, con menos/más de 7 dígitos, con mayúsculas; matrícula que no
  coincide; nombre de negocio de 2 caracteres; coordenadas fuera de rango;
  `instagram.com.phishing.net`; `javascript:` como esquema; teléfono con y sin
  lada.
- `services/otp.test.js` — código de 6 dígitos, hash estable, expirado,
  incorrecto.
- `routes/verificacion.test.js` — contra una DB SQLite temporal
  (`:memory:` o tmpdir), con mailer/sms inyectados como stub: flujo feliz de
  los tres tipos; 409 si ya verificado; 403 si el tipo no corresponde; 429 al
  cuarto envío; invalidación al sexto intento de confirmación; OTP no
  reutilizable tras usarse; rechazo de negocio con el `campo` correcto.

**Flutter** (`test/`): widget tests de `InsigniaVerificada` (color por tipo,
no se renderiza si `verified == false`) y de `_OtpInput` (auto-avance,
retroceso, pegado).

## Fuera de alcance

- Pantalla de administración (no hay revisión manual por diseño).
- Reverificación o expiración de la insignia.
- Verificación por WhatsApp (excluida explícitamente).
- Migrar el nombre `particular` → `externo` en DB/código.
- Gating de funciones de la app según verificación (publicar, chatear): la
  insignia es informativa; nada se bloquea por no estar verificado.
