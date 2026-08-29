/// Interruptor único de toda la funcionalidad de "planes para destacar"
/// publicaciones (promoción pagada para dar más visibilidad).
///
/// TODO: Destacar publicaciones pendiente para próxima actualización - no
/// eliminar, solo poner en `true` (o quitar los usos de esta bandera) cuando
/// esté listo para producción.
///
/// Mientras sea `false`:
/// - Ningún punto de entrada del frontend debe mostrarse ni ser accesible:
///   la opción "Planes de destacado" del perfil, el botón "Destacar/Extender"
///   de Mis publicaciones, la sección de planes de Publicar/Editar producto y
///   el banner de planes del home.
/// - Ningún badge ni indicador visual de "destacado" debe pintarse sobre las
///   publicaciones ([FeaturedBadge], borde/sombra dorada de la tarjeta,
///   contador "Destacadas").
/// - El home NO filtra los productos con `isFeatured = true`: como ya no hay
///   forma de quitarles el destacado desde la app, filtrarlos los dejaría
///   invisibles de forma permanente. Con la bandera en `false` se muestran
///   como publicaciones normales (ver `home_screen.dart`).
///
/// El código de la feature se deja intacto (comentado o detrás de esta
/// bandera) para poder reactivarlo cambiando solo este valor. El backend
/// (`/api/highlight-plans`, `PATCH /api/products/:id/featured`, tabla
/// `highlight_plans`) sigue existiendo pero queda sin consumidores.
const bool kDestacarHabilitado = false;
