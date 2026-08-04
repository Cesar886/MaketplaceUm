# Skeleton / shimmer loading states — Home grid y Perfil de vendedor

## Contexto

El home (`home_screen.dart`) y el perfil de vendedor (`seller_profile_screen.dart`)
muestran hoy un `CircularProgressIndicator` centrado mientras `_loading == true`.
Se reemplaza por un skeleton shimmer que refleja la estructura real post-rediseño
premium, en vez de una plantilla genérica de cajas grises.

`ProductDetailScreen` queda **fuera de alcance**: recibe `product` ya cargado por
constructor en los 13 call sites existentes (home, search, cart, qr_scanner, etc.),
no hace fetch de red al abrir, y por lo tanto no tiene un estado de carga real que
reemplazar.

## Estructura real extraída (verificada en código, no plantilla)

**Home grid** (`home_screen.dart` L1134-1140):
`SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12,
mainAxisSpacing: 12, childAspectRatio: 0.64)`. Loading actual: `CircularProgressIndicator`
centrado, L199-201.

**`ProductCard`** (`product_card.dart`, variante grid `_GridProductCard`):
`Padding(10)` sobre `DecoratedBox(borderRadius: 14)`; imagen `AspectRatio(4/3.4)`
con `borderRadius: 10`; `SizedBox(height:8)`; precio; `SizedBox(height:4)`; título
2 líneas (`label(13.5, w700)`); `SizedBox(height:2)`; descripción 1 línea
(`body(11.5)`); `Spacer()`; `SizedBox(height:6)`; fila inferior con texto
"publicado hace" + badge de estado (pill `borderRadius:999`).

**Perfil de vendedor** (`seller_profile_screen.dart`):
Loading actual: `CircularProgressIndicator` centrado. Estructura de `_buildContent`:
avatar `CircleAvatar(radius:40)` centrado; nombre + ícono verificado opcional;
carrera (`major`); rating; descripción opcional; botón WhatsApp ancho completo
(alto `52`, estilo `ElevatedButton` estándar) si aplica; `SellerScheduleAndLocationRow`
si hay horario/ubicación; `PaymentMethodsChips` (fila de íconos pequeños sin fondo,
`Wrap(spacing:18, runSpacing:10)`) si hay métodos de pago; grid de publicaciones
(mismo `ProductCard`, `crossAxisCount:2, childAspectRatio:0.66`).

## Diseño

### 1. Paquete y colores

- Agregar `shimmer: ^3.0.0` a `pubspec.yaml`.
- `lib/widgets/app_shimmer.dart`: envuelve `Shimmer.fromColors` usando
  `context.colors.surfaceMuted` (baseColor) y `context.colors.border`
  (highlightColor) — responden a modo oscuro/claro vía la extensión existente
  `AppColorsContext`. Incluye `ShimmerBox` (bloque `Container` con
  `borderRadius` configurable, color `context.colors.surfaceMuted`) como
  unidad base reutilizable.

### 2. `ProductCardSkeleton` (`lib/widgets/product_card_skeleton.dart`)

Replica bloque por bloque `_GridProductCard`, usando los mismos paddings,
alturas de `SizedBox` y `borderRadius` que el widget real (ver arriba). Toda
la card va envuelta en un solo `AppShimmer` (no uno por bloque) para que
respire como unidad.

### 3. `HomeGridSkeleton`

`GridView` con el mismo `SliverGridDelegateWithFixedCrossAxisCount` que el
grid real (crossAxisCount:2, spacing:12/12, aspectRatio:0.64), 6
`ProductCardSkeleton`. Reemplaza el `CircularProgressIndicator` en
`home_screen.dart` L199-201.

### 4. `SellerProfileSkeleton` (`lib/screens/seller_profile_screen.dart` o widget separado)

Replica `_buildContent`: círculo `radius:40`, línea de nombre, línea de
carrera, línea de rating, bloque de botón (alto 52, ancho completo), bloque
rectangular para horario/ubicación, fila de 4 círculos pequeños (métodos de
pago), grid de 4 `ProductCardSkeleton` (`childAspectRatio:0.66`). Reemplaza
el `CircularProgressIndicator` actual.

### 5. Transición fade

`body` de ambas pantallas envuelto en `AnimatedSwitcher(duration:
AppAnimations.medium)` con skeleton y contenido real como hijos con `key`
distinta.

## Fuera de alcance

- Skeleton de `ProductDetailScreen` (sin estado de carga real hoy).
- Contador de vistas y `PaymentMethodsChips` en detalle de producto (no
  existen en el código actual; el prompt original los mencionaba mal).

## Testing

- Verificación visual manual en home y perfil de vendedor (throttle de red o
  delay artificial temporal para observar el skeleton).
- `flutter analyze` sin nuevos errores.
