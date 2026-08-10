# Placeholder dinámico con búsquedas populares (trending searches)

## Contexto

El botón de búsqueda del Home (`_SearchBox` en `home_screen.dart`, clase
alrededor de la L782) no es un `TextField`: es un `Material`+`InkWell` con un
`Text` estático ("Buscar libros, laptops, tutorias...") que al tocarse navega
a `SearchScreen` (`search_screen.dart`).

`SearchScreen` sí tiene el `TextField` real (L132, hint "Libro, electronico,
servicio..."), pero la búsqueda es **100% client-side**: `_filteredResults`
(L68) filtra `_allProducts` (ya cargado completo vía `ApiService.getProducts()`
sin filtros) contra `_queryController.text` en cada `onChanged`. No hay
debounce, no hay submit real, y el backend nunca recibe el término buscado
aunque `GET /api/products` ya soporta `?search=` (`products.js` L237-241, sin
uso desde Flutter).

No existe ninguna tabla ni endpoint de analítica de búsquedas hoy. El patrón
más cercano en el backend es `interacciones_dispositivo` (`database.js`
L230-245): tabla de eventos con `created_at` + índices por ventana de tiempo,
alimentando agregados (popularidad de producto). `search_queries` sigue el
mismo molde pero sin `device_id`/`user_id` — es agregado puro, sin historial
por usuario.

## Decisiones tomadas

| Decisión | Elección | Razón |
|---|---|---|
| Dónde rota el placeholder | Solo `_SearchBox` del Home | Es el punto de entrada real; `SearchScreen` ya tiene su propio hint fijo y no se toca su UX de filtrado |
| Trigger de registro | `onSubmitted` del `TextField` en `SearchScreen` + apertura desde el Home con término precargado | Evita registrar ruido de cada tecla; solo cuenta intención real de buscar |
| Umbral mínimo para "trending" | Ninguno — top N tal cual venga | Simplicidad; app nueva sin data devuelve `[]` de forma natural y el frontend ya cae al placeholder genérico |
| Animación | Fade simple (`AnimatedSwitcher`) cada ~3s | Consistente con el resto del Home, sin timer letra-por-letra |
| Caché del agregado | Variable de módulo `{ data, expiresAt }` en la ruta, 20 min | Mismo patrón informal que `mailer.js`/`sms.js` (`*Cache`), sin dependencias nuevas |
| Autoridad de guardas (longitud) | Backend decide, frontend replica para evitar POST inútil | El backend nunca debe confiar en que el cliente validó |

## Diseño

### 1. Base de datos (`backend/src/database.js`)

Nueva tabla, agregada junto a `interacciones_dispositivo` en `initDatabase()`:

```sql
CREATE TABLE IF NOT EXISTS search_queries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  query_text TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_search_queries_created ON search_queries(created_at);
CREATE INDEX IF NOT EXISTS idx_search_queries_text ON search_queries(query_text, created_at);
```

Sin `device_id`/`user_id`: solo texto + timestamp, agregado estadístico.

### 2. Funciones de datos (`database.js`)

```js
const SEARCH_QUERY_MIN_LEN = 2;
const SEARCH_QUERY_MAX_LEN = 60;

function normalizeSearchQuery(text) {
  return String(text ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
}

function recordSearchQuery(text) {
  const normalized = normalizeSearchQuery(text);
  if (normalized.length < SEARCH_QUERY_MIN_LEN || normalized.length > SEARCH_QUERY_MAX_LEN) {
    return false;
  }
  db.prepare('INSERT INTO search_queries (query_text) VALUES (?)').run(normalized);
  return true;
}

function getTrendingSearches({ days, limit }) {
  return db.prepare(`
    SELECT query_text AS queryText, COUNT(*) AS count
    FROM search_queries
    WHERE created_at >= datetime('now', '-' || ? || ' days')
    GROUP BY query_text
    ORDER BY count DESC, MAX(created_at) DESC
    LIMIT ?
  `).all(days, limit);
}
```

Ambas se exportan en `module.exports` junto al resto.

### 3. Endpoint — nueva ruta `backend/src/routes/search.js`

```js
const db = require('../database');

const TRENDING_WINDOW_DAYS = 7;
const TRENDING_LIMIT = 12;
const TRENDING_CACHE_MS = 20 * 60 * 1000;

let trendingCache = { data: null, expiresAt: 0 };

function register(app) {
  // GET /api/search/trending — términos más buscados en los últimos
  // TRENDING_WINDOW_DAYS días, cacheado TRENDING_CACHE_MS (no es tiempo real).
  app.get('/api/search/trending', (_req, res) => {
    const now = Date.now();
    if (!trendingCache.data || now >= trendingCache.expiresAt) {
      const rows = db.getTrendingSearches({
        days: TRENDING_WINDOW_DAYS,
        limit: TRENDING_LIMIT,
      });
      trendingCache = {
        data: rows.map(r => r.queryText),
        expiresAt: now + TRENDING_CACHE_MS,
      };
    }
    res.json({ terms: trendingCache.data });
  });

  // POST /api/search/track — registra una búsqueda ejecutada por el usuario.
  // Fire-and-forget desde el cliente; nunca falla la búsqueda local si esto
  // falla, por eso responde 204 siempre que el body sea válido.
  app.post('/api/search/track', (req, res) => {
    const { query } = req.body || {};
    if (typeof query !== 'string') {
      return res.status(400).json({ error: 'query es obligatorio' });
    }
    db.recordSearchQuery(query);
    res.status(204).end();
  });
}

module.exports = { register };
```

Registrar en `index.js` junto a los demás `require('./routes/...').register(app)`.

### 4. Frontend — `ApiService` (`lib/services/api_service.dart`)

```dart
static Future<List<String>> getTrendingSearches() async {
  final res = await _getWithRetry(_uri('/search/trending'));
  if (res.statusCode != 200) throw Exception('Error fetching trending searches');
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return (body['terms'] as List<dynamic>).cast<String>();
}

/// Fire-and-forget: no bloquea la UI ni propaga errores de red.
static void recordSearchQuery(String text) {
  final trimmed = text.trim();
  if (trimmed.length < 2 || trimmed.length > 60) return;
  _client
      .post(
        _uri('/search/track'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': trimmed}),
      )
      .catchError((_) => http.Response('', 500));
}
```

### 5. Frontend — Home (`home_screen.dart`)

- Estado de `_HomeScreenState` (o el State que ya orquesta las cargas
  iniciales) gana `List<String> _trendingSearches = []`, cargado una vez en
  `initState`/`_loadData` vía `ApiService.getTrendingSearches()`. Falla
  silenciosa → queda `[]` → comportamiento actual sin cambios.
- `_SearchBox` pasa de `StatelessWidget` a `StatefulWidget` (necesita
  `Timer.periodic` para rotar). Recibe `List<String> trendingTerms` además de
  `onTap` (que cambia de `VoidCallback` a `ValueChanged<String?>` para poder
  pasar el término tocado).
- Si `trendingTerms.isEmpty`: se pinta el `Text` estático actual, sin timer.
- Si no está vacío: `Timer.periodic(Duration(seconds: 3))` avanza un índice
  circular; el texto se envuelve en `AnimatedSwitcher` (`duration: 250ms`,
  `transitionBuilder: FadeTransition`) mostrando `"Buscar '$termino'..."`.
  Timer se cancela en `dispose()`.
- El `Row` completo sigue siendo tocable (`InkWell.onTap`); el callback pasa
  el término actualmente mostrado (`null` si se está mostrando el placeholder
  genérico).
- El caller en `HomeScreen` (donde hoy se instancia `_SearchBox(onTap: ...)`)
  pasa un callback que navega a `SearchScreen(initialQuery: term)`.

### 6. Frontend — `SearchScreen` (`search_screen.dart`)

- Constructor gana `this.initialQuery` (opcional, junto a `initialCategoryId`).
- `initState`: si `initialQuery != null`, `_queryController.text =
  initialQuery!` (el filtrado ya es reactivo, no hace falta más) y se llama
  `ApiService.recordSearchQuery(initialQuery!)`.
- `TextField` (L132) gana `onSubmitted: (value) =>
  ApiService.recordSearchQuery(value)`. Sigue sin bloquear el filtrado local,
  que ya reacciona por `onChanged`.

## Testing

- Backend (`node --test`, sigue convención de `*.test.js` junto a la ruta o en
  `database.*.test.js`):
  - `normalizeSearchQuery`: lowercase, trim, colapsa espacios.
  - `recordSearchQuery`: descarta `< 2` y `> 60` caracteres; inserta lo válido.
  - `getTrendingSearches`: respeta ventana de días (excluye filas viejas),
    ordena por conteo desc, desempata por más reciente.
  - `GET /api/search/trending`: cachea (segunda llamada dentro de la ventana
    no reconsulta — se puede probar espiando `db.getTrendingSearches` con un
    contador de llamadas).
  - `POST /api/search/track`: 400 si falta `query`, 204 si válido, no revienta
    con query basura (muy corta/larga se ignora sin error).
- Frontend: no hay suite de widgets para `HomeScreen`/`SearchScreen` hoy; no se
  agrega una nueva salvo que surja necesidad — se verifica manualmente
  corriendo la app (placeholder rota, tap navega con término precargado,
  fallback sin data no rompe nada).
