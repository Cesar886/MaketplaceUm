# Perfil: arreglar funcionalidad rota y agregar edición

## Contexto

`profile_screen.dart` ya tuvo un primer arreglo (calificación/opiniones desde
`ApiService.getSeller`, conteo de activas desde `ApiService.getProducts(seller:
...)` en vez del endpoint global `/api/listings`). Quedan pendientes:

1. `my_listings_screen.dart` tiene el mismo bug de origen: usa
   `ApiService.getListings()` (sin filtro por vendedor) en vez de
   `ApiService.getProducts(seller: sellerId)`.
2. No existe forma de editar nombre, teléfono ni foto de perfil.
3. Tres opciones del perfil ("Confianza y seguridad", "Planes para destacar",
   "Ayuda") no tienen `onTap` real — muestran un snackbar `"$title mock"`.

## Alcance

Backend (`backend/src/`) + frontend Flutter (`lib/`). No incluye rediseño
visual del perfil, solo conectar/crear la funcionalidad faltante.

## 1. Fix `MyListingsScreen`

`lib/screens/my_listings_screen.dart`: reemplazar la llamada a
`ApiService.getListings()` por `ApiService.getProducts(seller: sellerId)`,
leyendo `sellerId` desde `context.read<AuthProvider>().backendSellerId`
(agregar imports de `provider` y `AuthProvider`). Mismo patrón ya aplicado en
`profile_screen.dart`.

## 2. Backend: `PATCH /api/sellers/:id`

Nueva ruta en `backend/src/routes/sellers.js`, protegida con `requireAuth`
(ya existe en `backend/src/auth.js`, pone `req.user.id = sellerId` desde el
JWT). Solo el dueño del perfil puede editarse (`req.user.id !==
req.params.id` → 403).

Reutiliza `updateSellerField(sellerId, field, value)`, ya presente en
`backend/src/data.js` pero sin ninguna ruta que lo exponga hoy. Acepta
`{ name?, phone? }` en el body:

- Si viene `name` no vacío: actualiza `name` y recalcula `avatarInitials`
  (primeras letras de las primeras 2 palabras, mayúsculas).
- Si viene `phone` (incluyendo string vacío): actualiza `phone`.

Responde con el `Seller` actualizado completo.

La foto de perfil **no** usa una ruta nueva: se reutiliza
`POST /api/sellers/:id/logo` (ya existe, sube a `logoUrl`, usado hoy solo
para logos de negocio pero genérico — cualquier seller puede tener
`logoUrl`).

## 3. Frontend: edición de perfil

### `lib/services/api_service.dart`
Nuevo método:
```dart
static Future<Seller> updateSellerProfile({
  required String sellerId,
  String? name,
  String? phone,
}) async {
  final body = <String, dynamic>{};
  if (name != null) body['name'] = name;
  if (phone != null) body['phone'] = phone;
  final res = await _client.patch(
    _uri('/sellers/$sellerId'),
    headers: _authHeaders,
    body: jsonEncode(body),
  );
  if (res.statusCode != 200) throw Exception('Error al actualizar perfil');
  return Seller.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
}
```

### `lib/services/db_helper.dart`
Nuevo método `updateUserFields(int userId, {String? name, String? phone})`
que hace `db.update('users', {...campos no nulos...}, where: 'id = ?',
whereArgs: [userId])`. Mantiene la tabla local `users` (fuente de
`auth.currentUser`) en sync con el backend.

### `lib/providers/auth_provider.dart`
Nuevo método:
```dart
Future<void> updateProfile({String? name, String? phone, String? logoPath}) async {
  if (logoPath != null && _backendSellerId != null) {
    await ApiService.uploadBusinessLogo(sellerId: _backendSellerId!, imagePath: logoPath);
  }
  if ((name != null || phone != null) && _backendSellerId != null) {
    await ApiService.updateSellerProfile(sellerId: _backendSellerId!, name: name, phone: phone);
  }
  if (name != null || phone != null) {
    await _db.updateUserFields(userId, name: name, phone: phone);
    if (name != null) _currentUser!['name'] = name;
    if (phone != null) _currentUser!['phone'] = phone;
  }
  notifyListeners();
}
```
Errores de red se propagan (la pantalla los captura y muestra un snackbar,
sin dejar el formulario en estado inconsistente).

### `lib/screens/profile/edit_profile_screen.dart` (nuevo)
`StatefulWidget` con:
- Avatar tocable (usa `image_picker`, mismo patrón que
  `register_form_screen.dart`) — muestra preview local si se eligió foto
  nueva, si no la foto actual (`seller.logoUrl` vía `ApiService.baseUrl`) o
  iniciales de fallback.
- `TextField` nombre (requerido, no vacío).
- `TextField` teléfono.
- Botón "Guardar": valida, llama `auth.updateProfile(...)`, muestra loading,
  hace `Navigator.pop(context, true)` al terminar; captura excepción y
  muestra `SnackBar` con el error sin cerrar la pantalla.

### `lib/screens/profile_screen.dart`
- Guarda el `Seller` completo cargado en `_loadListings` (ya se obtiene con
  `ApiService.getSeller`) en un campo `_seller` para leer `logoUrl`.
- El `CircleAvatar` del header muestra `Image.network('${ApiService.baseUrl}${_seller!.logoUrl}')`
  si existe, con `errorBuilder`/fallback a las iniciales (mismo patrón que
  `home_screen.dart:749-764`).
- Ícono de lápiz superpuesto en la esquina del avatar (`Positioned` +
  `InkWell`) que abre `EditProfileScreen`; si vuelve con `true`, se
  recarga `_loadListings()`.

## 4. Tres pantallas nuevas (reemplazan el mock)

Todas en `lib/screens/profile/`, cada una un archivo propio, enlazadas desde
`profile_screen.dart` reemplazando el `onTap` por defecto de los
`_ProfileOption` correspondientes.

### `safety_tips_screen.dart`
Contenido estático (`ListView` de tarjetas con ícono + texto), tips reales
para un marketplace universitario: verificar identidad/perfil antes de
reunirse, quedar en zonas públicas del campus, revisar el producto antes de
pagar, desconfiar de pagos por adelantado fuera de la app, cómo reportar un
usuario sospechoso.

### `highlight_plans_screen.dart`
Llama `ApiService.getHighlightPlans()` (ya existe, usado en
`publish_product_screen.dart`) y muestra la lista en modo solo-lectura:
título, precio, duración en días, descripción de cada `HighlightPlan`. Sin
botón de compra — es informativo (para eso ya existe el flujo dentro de
publicar producto).

### `help_screen.dart`
FAQ estática (`ExpansionTile` por pregunta): cómo publicar un producto, cómo
contactar a un vendedor, cómo funciona la verificación de cuenta, cómo
reportar un problema, datos de contacto de soporte.

## Testing

- `flutter analyze` sobre los archivos tocados/creados.
- Backend: probar `PATCH /api/sellers/:id` manualmente con `curl` (con y sin
  token válido, con `id` de otro seller → 403).
- No hay entorno para correr la app en emulador en esta sesión; se deja
  explícito que la verificación visual queda pendiente para el usuario.
