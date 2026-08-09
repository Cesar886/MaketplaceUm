import type { EstadoProducto, ProductoPublico } from './tipos';

const formateadorMXN = new Intl.NumberFormat('es-MX', {
  style: 'currency',
  currency: 'MXN',
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

export function formatearPrecio(precio: number): string {
  return formateadorMXN.format(precio);
}

/**
 * Etiqueta y color de estado, replicando `AvailabilityBadge`
 * (`lib/widgets/badges.dart`) para que la web y la app digan lo mismo.
 *
 * `tono` mapea a las variables CSS de globals.css.
 */
export function etiquetaEstado(producto: ProductoPublico): {
  texto: string;
  tono: 'exito' | 'aviso' | 'neutro' | 'marca';
} {
  const detalle = producto.estadoDetalle ?? {};

  const mapa: Record<
    EstadoProducto,
    { texto: string; tono: 'exito' | 'aviso' | 'neutro' | 'marca' }
  > = {
    available: { texto: 'Disponible', tono: 'exito' },
    sold_out: { texto: 'Agotado', tono: 'neutro' },
    available_other_day: {
      texto: detalle.next_available_day
        ? `Disponible el ${detalle.next_available_day}`
        : 'Próximamente',
      tono: 'aviso',
    },
    closed: {
      texto: detalle.opens_at ? `Disponible: ${detalle.opens_at}` : 'Cerrado',
      tono: 'neutro',
    },
    reserved: { texto: 'Apartado', tono: 'aviso' },
    negotiating: { texto: 'En negociación', tono: 'marca' },
    sold: { texto: 'Vendido', tono: 'neutro' },
    paused: { texto: 'Pausado', tono: 'neutro' },
  };

  return mapa[producto.estado] ?? { texto: 'Disponible', tono: 'exito' };
}

/**
 * Subtítulo de rol bajo el nombre del vendedor. Réplica de `subtituloRol`
 * (`lib/widgets/user_role.dart`): devuelve null cuando no hay nada que
 * mostrar, y entonces la línea se omite en vez de caer a un genérico.
 *
 * `major` no viaja a la web (es un campo interno del que el backend deriva
 * otros datos), así que para negocio y particular se usa una etiqueta fija.
 */
export function subtituloRol(
  vendedor: ProductoPublico['vendedor'],
): string | null {
  if (!vendedor) return null;

  if (vendedor.tipoCuenta !== 'estudiante') {
    return vendedor.esNegocio ? 'Negocio' : null;
  }
  if (!vendedor.verificado) return null;
  if (vendedor.tipoVerificacion === 'empleado') return 'Personal UM';
  return vendedor.carrera && vendedor.carrera.length > 0 ? vendedor.carrera : null;
}

/** Recorta la descripción para `og:description` sin partir una palabra. */
export function resumen(texto: string, maximo = 150): string {
  const limpio = texto.replace(/\s+/g, ' ').trim();
  if (limpio.length <= maximo) return limpio;
  const corte = limpio.slice(0, maximo);
  const ultimoEspacio = corte.lastIndexOf(' ');
  return `${(ultimoEspacio > 60 ? corte.slice(0, ultimoEspacio) : corte).trimEnd()}…`;
}
