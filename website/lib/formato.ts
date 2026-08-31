import type {
  BusquedaPublica,
  EstadoProducto,
  ProductoPublico,
  VendedorPublico,
} from './tipos';

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
export function subtituloRol(vendedor: VendedorPublico | null): string | null {
  if (!vendedor) return null;

  if (vendedor.tipoCuenta !== 'estudiante') {
    return vendedor.esNegocio ? 'Negocio' : null;
  }
  if (!vendedor.verificado) return null;
  if (vendedor.tipoVerificacion === 'empleado') return 'Personal UM';
  return vendedor.carrera && vendedor.carrera.length > 0 ? vendedor.carrera : null;
}

/**
 * Rango de precio de una búsqueda, en lenguaje natural.
 *
 * Devuelve null cuando no hay ningún extremo: entonces la página dice
 * "Presupuesto abierto" en vez de un "$0" que se leería como una oferta real.
 */
export function formatearRango(
  min: number | null,
  max: number | null,
): string | null {
  if (min != null && max != null) {
    // Un rango donde ambos extremos coinciden es un precio, no un rango.
    if (min === max) return formatearPrecio(min);
    return `${formatearPrecio(min)} – ${formatearPrecio(max)}`;
  }
  if (max != null) return `Hasta ${formatearPrecio(max)}`;
  if (min != null) return `Desde ${formatearPrecio(min)}`;
  return null;
}

/**
 * Antigüedad en palabras, réplica de `lib/utils/tiempo_relativo.dart`.
 *
 * Las búsquedas mandan la fecha ISO cruda (los productos mandan un texto ya
 * formateado y congelado al publicar), así que el cálculo ocurre aquí, al
 * renderizar. Se corta en semanas: más allá de eso la fecha exacta importa
 * más que el "hace cuánto".
 */
export function tiempoRelativo(iso: string | null): string | null {
  if (!iso) return null;

  const fecha = new Date(iso);
  if (Number.isNaN(fecha.getTime())) return null;

  const segundos = Math.floor((Date.now() - fecha.getTime()) / 1000);
  // Un reloj desfasado puede dar una fecha en el futuro; "hace -3 minutos" es
  // peor que redondear a "hace un momento".
  if (segundos < 60) return 'hace un momento';

  const minutos = Math.floor(segundos / 60);
  if (minutos < 60) return `hace ${minutos} ${minutos === 1 ? 'minuto' : 'minutos'}`;

  const horas = Math.floor(minutos / 60);
  if (horas < 24) return `hace ${horas} ${horas === 1 ? 'hora' : 'horas'}`;

  const dias = Math.floor(horas / 24);
  if (dias < 7) return `hace ${dias} ${dias === 1 ? 'día' : 'días'}`;

  const semanas = Math.floor(dias / 7);
  if (semanas < 5) return `hace ${semanas} ${semanas === 1 ? 'semana' : 'semanas'}`;

  return fecha.toLocaleDateString('es-MX', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  });
}

/** Verbo y encabezado de una búsqueda, según pida un producto o un servicio. */
export function textoBusqueda(busqueda: BusquedaPublica): {
  encabezado: string;
  etiquetaPresupuesto: string;
} {
  return busqueda.busca === 'servicio'
    ? { encabezado: 'Busca contratar', etiquetaPresupuesto: 'Presupuesto' }
    : { encabezado: 'Busca comprar', etiquetaPresupuesto: 'Dispuesto a pagar' };
}

/**
 * Presupuesto de caracteres de la vista previa, medido contra lo que WhatsApp
 * llega a dibujar: pasado eso el texto no se pierde, se corta con puntos
 * suspensivos a mitad de palabra, que es justo lo que hace ver improvisado un
 * link al lado de uno de Mercado Libre.
 */
export const MAXIMO_TITULO = 65;
export const MAXIMO_DESCRIPCION = 150;

/**
 * ¿Este texto dice algo, o es relleno?
 *
 * Un título como "Jajs" pasa cualquier validación de "campo obligatorio" y
 * deja la vista previa indistinguible de un link basura. Diez caracteres es
 * el piso por debajo del cual conviene completar con la categoría en vez de
 * publicar el texto tal cual.
 */
export function esTextoUtil(texto: string | null | undefined): boolean {
  return (texto ?? '').replace(/\s+/g, ' ').trim().length >= 10;
}

/** Recorta la descripción para `og:description` sin partir una palabra. */
export function resumen(texto: string, maximo = MAXIMO_DESCRIPCION): string {
  const limpio = texto.replace(/\s+/g, ' ').trim();
  if (limpio.length <= maximo) return limpio;
  const corte = limpio.slice(0, maximo);
  const ultimoEspacio = corte.lastIndexOf(' ');
  // El umbral del espacio se escala con el máximo: cortando a 65 (un título)
  // no existe ningún espacio pasado el carácter 60, y con el 60 fijo que
  // había antes el recorte por palabra no se aplicaría nunca en títulos.
  const minimoEspacio = Math.floor(maximo * 0.4);
  return `${(ultimoEspacio > minimoEspacio ? corte.slice(0, ultimoEspacio) : corte).trimEnd()}…`;
}
