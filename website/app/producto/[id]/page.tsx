import type { Metadata } from 'next';
import { notFound } from 'next/navigation';

import VistaBusqueda from '@/components/VistaBusqueda';
import VistaProducto from '@/components/VistaProducto';
import { obtenerPublicacion, SITE_URL, urlFoto } from '@/lib/api';
import {
  esTextoUtil,
  formatearPrecio,
  formatearRango,
  MAXIMO_DESCRIPCION,
  MAXIMO_TITULO,
  resumen,
  textoBusqueda,
} from '@/lib/formato';
import type { PublicacionPublica } from '@/lib/tipos';

type Props = { params: Promise<{ id: string }> };

/**
 * `/producto/:id` sirve las dos cosas que la app deja compartir: un producto
 * en venta y una publicación "se busca". El botón de compartir es uno solo y
 * genera esta misma URL para ambas, así que la ruta las despacha por el campo
 * `tipo` de la respuesta en vez de tener dos rutas que el usuario nunca
 * distinguiría al pegar un link.
 */

/**
 * Encabezado de la vista previa.
 *
 * El título lo escribe el vendedor y no siempre describe nada ("Jajs", "No
 * hay plata"): un preview con eso arriba se lee como spam al lado de un link
 * de Mercado Libre. Cuando el texto no llega al piso de [esTextoUtil] se le
 * suma la categoría — el único dato descriptivo que el backend garantiza — en
 * vez de publicarlo pelado, y si no hay ni título ni categoría se cae a la
 * marca antes que a un `undefined` o a un guion suelto.
 *
 * El recorte a [MAXIMO_TITULO] es lo que evita que WhatsApp lo corte a mitad
 * de palabra por su cuenta.
 */
function tituloPreview(
  titulo: string,
  categoria: string | null,
  sufijo: string,
): string {
  const limpio = titulo.replace(/\s+/g, ' ').trim();
  const encabezado = esTextoUtil(limpio)
    ? limpio
    : [limpio, categoria].filter(Boolean).join(' · ') || 'Publicación';

  // El sufijo de marca no se recorta: se descuenta del presupuesto para que
  // sobreviva entero, que es lo que hace reconocible el link.
  return `${resumen(encabezado, MAXIMO_TITULO - sufijo.length)} ${sufijo}`;
}

/** Título, descripción e imagen de la vista previa, según el tipo. */
function metaDe(publicacion: PublicacionPublica): {
  titulo: string;
  descripcion: string;
  foto: string | null;
} {
  const categoria = publicacion.categoria?.nombre ?? null;

  if (publicacion.tipo === 'busqueda') {
    const { encabezado } = textoBusqueda(publicacion);
    const rango = formatearRango(publicacion.precioMin, publicacion.precioMax);

    return {
      titulo: tituloPreview(
        publicacion.titulo,
        categoria,
        '- Se busca en Marketplace UM',
      ),
      descripcion: esTextoUtil(publicacion.descripcion)
        ? resumen(publicacion.descripcion)
        : `${encabezado}${rango ? `: ${rango}` : ''}. Publicado en Marketplace UM.`,
      // Una búsqueda no tiene fotos. Sin `og:image` WhatsApp cae a la tarjeta
      // pequeña, que es lo correcto: inventar una imagen genérica haría que
      // todas las búsquedas compartidas se vieran idénticas.
      foto: null,
    };
  }

  const precio = formatearPrecio(publicacion.precio);

  return {
    titulo: tituloPreview(publicacion.titulo, categoria, '- Marketplace UM'),
    // El precio va primero, como en Mercado Libre: es el dato que decide si
    // alguien abre el link, y así queda del lado que WhatsApp nunca corta.
    descripcion: esTextoUtil(publicacion.descripcion)
      ? `${precio} · ${resumen(publicacion.descripcion, MAXIMO_DESCRIPCION - precio.length - 3)}`
      : [precio, categoria, 'Disponible en Marketplace UM']
          .filter(Boolean)
          .join(' · '),
    foto: publicacion.fotos[0] ? urlFoto(publicacion.fotos[0]) : null,
  };
}

/**
 * Meta tags por publicación. Es lo más importante de esta página: define cómo
 * se ve el link al pegarse en WhatsApp, y el crawler de preview NO ejecuta JS,
 * así que todo esto tiene que resolverse en el servidor.
 */
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { id } = await params;
  const publicacion = await obtenerPublicacion(id);

  if (!publicacion) {
    return {
      title: 'Publicación no disponible - Marketplace UM',
      // Un 404 no debe quedar indexado ni acumular señales de SEO.
      robots: { index: false, follow: false },
    };
  }

  const { titulo, descripcion, foto } = metaDe(publicacion);
  const url = `${SITE_URL}/producto/${publicacion.id}`;

  return {
    title: titulo,
    description: descripcion,
    alternates: { canonical: url },
    openGraph: {
      title: titulo,
      description: descripcion,
      url,
      siteName: 'Marketplace UM',
      locale: 'es_MX',
      // og:product no es un tipo válido del estándar OG que Next tipe; el
      // que corresponde a un artículo a la venta es 'website' salvo que se
      // declare el namespace completo de product, que WhatsApp ignora.
      type: 'website',
      // El alt sale del título ya saneado: el crudo puede venir vacío, y un
      // `alt=""` en la foto principal es exactamente lo que no debe pasar.
      images: foto ? [{ url: foto, alt: titulo }] : [],
    },
    twitter: {
      card: foto ? 'summary_large_image' : 'summary',
      title: titulo,
      description: descripcion,
      images: foto ? [foto] : [],
    },
  };
}

export default async function PaginaPublicacion({ params }: Props) {
  const { id } = await params;
  const publicacion = await obtenerPublicacion(id);

  // notFound() emite un 404 real, no una página 200 que dice "no existe":
  // sin el status correcto los buscadores indexarían publicaciones muertas.
  if (!publicacion) notFound();

  return (
    // El padding inferior deja aire para el SmartBanner fijo.
    <main className="contenedor" style={{ padding: '18px 18px 120px' }}>
      {publicacion.tipo === 'busqueda' ? (
        <VistaBusqueda busqueda={publicacion} />
      ) : (
        <VistaProducto producto={publicacion} />
      )}
    </main>
  );
}
