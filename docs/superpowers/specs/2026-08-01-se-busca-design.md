# "Se busca" — Publicaciones de demanda (wanted posts)

## Contexto y objetivo

MercadoUm hoy solo soporta el flujo tradicional oferta → demanda: un vendedor publica un
producto y un comprador lo encuentra. Esta feature invierte el flujo: un comprador publica
qué está buscando ("busco calculadora científica", "busco tutor de cálculo") y los vendedores
relevantes son notificados automáticamente, sin que el comprador tenga que esperar a que
alguien publique el producto/servicio primero.

El objetivo del MVP es cerrar el ciclo completo (publicar → notificar → responder por chat →
marcar resuelto) reusando al máximo la infraestructura ya existente: categorías,
`category_interests` + push (FCM), y el sistema de chat anónimo. No se construye mensajería,
sistema de notificaciones, ni selector de categorías nuevos.

## Decisiones de alcance (confirmadas con el usuario)

- **Sin autenticación requerida**: publicar y responder usa el mismo patrón anónimo que el
  chat actual (`AnonymousId.resolve` → `sellerId` si hay sesión, o id anónimo persistido si no).
- **Matching**: solo por categoría, reusando `category_interests` (igual que notificación de
  productos nuevos en `products.js`). Sin palabras clave ni IA en este MVP.
- **Tipo de publicación**: cada "Se busca" es `producto` o `servicio`. Si es `servicio`, la UI
  no pide precio fijo sino que ofrece "cotización" (campo de precio opcional en ambos casos).
- **Respuesta**: el botón "Responder" abre directamente el chat existente 1:1 con el
  publicador — no hay hilo de comentarios públicos en este MVP.
- **Anti-spam**: máximo 3 publicaciones "Se busca" por usuario (`user_id`) por día natural,
  validado en el backend.
- **Cierre**: solo "marcar como resuelta" manual por el dueño de la publicación. Cierre
  automático por inactividad y el insight "lo más buscado esta semana" quedan fuera de este
  MVP (v2, no bloquean el ciclo core).

## Arquitectura y datos

### Nueva tabla `wanted_posts`

```sql
CREATE TABLE wanted_posts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,                 -- anonymousId o sellerId (mismo patrón que chat)
  title TEXT NOT NULL,
  description TEXT,
  category_id TEXT NOT NULL,             -- reusa categories.id, sin FK estricta (igual que products.category)
  type TEXT NOT NULL,                    -- 'producto' | 'servicio'
  price_min REAL,
  price_max REAL,
  status TEXT NOT NULL DEFAULT 'abierta',-- 'abierta' | 'resuelta'
  resolved_with_user_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  resolved_at TEXT
);

CREATE INDEX idx_wanted_posts_category ON wanted_posts(category_id, status);
CREATE INDEX idx_wanted_posts_user ON wanted_posts(user_id, created_at);
```

### Cambio en `conversations` (aditivo, migración compatible)

Hoy `conversations.product_id` es `NOT NULL` — una conversación siempre cuelga de un
producto. Para reusar el chat en respuestas a "Se busca", se agrega una columna nueva y se
relaja la restricción existente vía migración (patrón ya usado en `database.js` para
`extras`, `stock_quantity`, etc.):

```sql
ALTER TABLE conversations ADD COLUMN wanted_post_id TEXT;
-- product_id pasa a ser opcional a nivel de aplicación: exactamente uno de
-- (product_id, wanted_post_id) debe estar presente por conversación.
```

SQLite no permite quitar `NOT NULL` con `ALTER TABLE` directamente; la migración recrea la
tabla `conversations` (mismo patrón de "migración de schema" que ya existe en
`initDatabase()`) preservando los datos existentes, dejando `product_id` nullable y
agregando `wanted_post_id`.

`createConversation`/`findConversation` en `database.js` se generalizan para aceptar
`{ productId }` o `{ wantedPostId }` (exactamente uno).

## Endpoints backend

Nuevo archivo `backend/src/routes/wanted.js`, registrado igual que las demás rutas en
`index.js`.

```
POST   /api/wanted
  body: { userId, title, description?, categoryId, type, priceMin?, priceMax? }
  - Valida type ∈ {producto, servicio}.
  - Rate limit: máx 3 posts por userId en las últimas 24h → 429 si se excede.
  - Al crear: busca category_interests de categoryId, crea notificación in-app
    (db.createNotification) y dispara sendPush a los interesados (excluyendo al publicador),
    igual que products.js hace para productos nuevos.

GET    /api/wanted
  query: ?category=&status=(abierta|resuelta, default abierta)&type=
  - Devuelve feed ordenado por created_at desc.

GET    /api/wanted/:id
  - Detalle de una publicación (404 si no existe).

PATCH  /api/wanted/:id/resolve
  body: { userId, resolvedWithUserId? }
  - 403 si userId no es el dueño.
  - 400 si ya estaba resuelta.

POST   /api/wanted/:id/respond
  body: { userId }
  - 400 si userId === wanted_posts.user_id (no puedes responderte a ti mismo).
  - 400 si el post ya está resuelta.
  - Reusa/crea conversación vía wantedPostId (findConversation/createConversation
    generalizados) y devuelve { conversationId }. El primer mensaje lo manda el cliente
    con el POST /api/chat/send normal usando ese conversationId.
```

## Frontend (Flutter)

- **Modelo `WantedPost`** en `models.dart`, análogo a `Product`: `fromJson`/`toJson`,
  incluye `title`, `description`, `categoryId`, `type` (enum), `priceMin`, `priceMax`,
  `status`, `createdAt`.
- **`ApiService`**: `createWantedPost`, `getWantedPosts`, `getWantedPost`, `resolveWantedPost`,
  `respondToWantedPost` — mismo patrón que los métodos existentes de productos, sin
  `Authorization` header obligatorio (usa `userId` en el body, igual que chat).
- **FAB** (`main_shell.dart`, `_PublishFab`): el `onTap` deja de navegar directo a
  `PublishProductScreen` y en su lugar abre un `showModalBottomSheet` con dos opciones:
  "Publicar producto" (comportamiento actual) y "Publicar búsqueda" (nuevo).
- **`WantedPostScreen`** (nueva, similar estructura a `PublishProductScreen` pero sin
  imágenes): título, descripción, selector de categoría (reusa el widget/lista de
  categorías ya usado en publicar producto), toggle Producto/Servicio, rango de precio
  (opcional, con placeholder "Cotización" si es servicio).
- **`WantedFeedScreen`** (nueva): lista de publicaciones abiertas, filtro por categoría,
  card compacta (título, categoría, tipo, tiempo). Accesible desde el mismo bottom sheet
  del FAB ("Ver búsquedas") y desde un acceso en `HomeScreen`.
- **`WantedPostDetailScreen`** (nueva): muestra el detalle; si `userId actual == owner`
  muestra botón "Marcar como resuelta" (con selector opcional de con quién se resolvió);
  si no, botón "Responder" que llama `respondToWantedPost` y navega a `ChatScreen` con el
  `conversationId` devuelto.
- **Chat existente** (`chat_list_screen.dart`, `chat_screen.dart`): hoy asumen que toda
  conversación tiene producto. Se ajustan para, cuando `product == null` y viene
  `wantedPost != null`, mostrar el título del "Se busca" en el header/preview en vez de la
  tarjeta de producto.

## Manejo de errores

- Límite diario excedido → 429, mensaje "Ya publicaste el máximo de 3 búsquedas hoy".
- Responder a post resuelto → 400 "Esta búsqueda ya fue resuelta".
- Responder a tu propia publicación → 400 "No puedes responder tu propia búsqueda".
- `categoryId` inexistente → 400 (misma validación laxa que productos: se guarda igual,
  el feed simplemente no tendrá `categoryObj` si la categoría no existe).

## Testing

- Backend: pruebas manuales vía curl (crear, listar, responder, resolver, límite diario)
  igual que se hizo para verificar `extras` — no hay framework de test automatizado en el
  repo actualmente.
- Frontend: `flutter analyze` sin errores nuevos; prueba manual del flujo completo en la
  app (publicar búsqueda anónimo, responder desde otra sesión, verificar que el chat abre
  y que "marcar resuelta" oculta el post del feed de abiertos).

## Fuera de alcance (v2)

- Cierre automático de publicaciones sin respuesta tras N días.
- Insight "lo más buscado esta semana" / analytics de demanda insatisfecha.
- Matching por palabras clave o similitud de texto.
- Hilo de comentarios públicos antes de abrir chat privado.
