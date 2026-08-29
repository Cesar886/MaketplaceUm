/// Interruptor único de todo el módulo de pagos con Mercado Pago.
///
/// TODO: Mercado Pago pendiente para próxima actualización - no eliminar,
/// solo poner en `true` (o quitar los usos de esta bandera) cuando esté
/// listo para producción.
///
/// Mientras sea `false`, ningún punto de entrada del frontend (checkout,
/// tarjetas guardadas, conexión de cuenta de cobros del vendedor) debe
/// mostrarse ni ser accesible para el usuario final. El código de
/// `lib/features/payments/` se deja intacto para poder reactivarlo con
/// solo cambiar este valor.
const bool kMercadoPagoHabilitado = false;
