import type { Metadata } from 'next';
import { notFound } from 'next/navigation';

import CtaContacto from '@/components/CtaContacto';
import Galeria from '@/components/Galeria';
import { obtenerProducto, SITE_URL, urlFoto } from '@/lib/api';
import { etiquetaEstado, formatearPrecio, resumen, subtituloRol } from '@/lib/formato';

type Props = { params: Promise<{ id: string }> };

/**
 * Meta tags por producto. Es lo más importante de esta página: define cómo se
 * ve el link al pegarse en WhatsApp, y el crawler de preview NO ejecuta JS,
 * así que todo esto tiene que resolverse en el servidor.
 */
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { id } = await params;
  const producto = await obtenerProducto(id);

  if (!producto) {
    return {
      title: 'Publicación no disponible - Mercadito UM',
      // Un 404 no debe quedar indexado ni acumular señales de SEO.
      robots: { index: false, follow: false },
    };
  }

  const titulo = `${producto.titulo} - Mercadito UM`;
  const descripcion = producto.descripcion
    ? resumen(producto.descripcion)
    : `${formatearPrecio(producto.precio)} · Disponible en Mercadito UM.`;
  const foto = producto.fotos[0] ? urlFoto(producto.fotos[0]) : null;
  const url = `${SITE_URL}/producto/${producto.id}`;

  return {
    title: titulo,
    description: descripcion,
    alternates: { canonical: url },
    openGraph: {
      title: titulo,
      description: descripcion,
      url,
      siteName: 'Mercadito UM',
      locale: 'es_MX',
      // og:product no es un tipo válido del estándar OG que Next tipe; el
      // que corresponde a un artículo a la venta es 'website' salvo que se
      // declare el namespace completo de product, que WhatsApp ignora.
      type: 'website',
      images: foto ? [{ url: foto, alt: producto.titulo }] : [],
    },
    twitter: {
      card: foto ? 'summary_large_image' : 'summary',
      title: titulo,
      description: descripcion,
      images: foto ? [foto] : [],
    },
  };
}

export default async function PaginaProducto({ params }: Props) {
  const { id } = await params;
  const producto = await obtenerProducto(id);

  // notFound() emite un 404 real, no una página 200 que dice "no existe":
  // sin el status correcto los buscadores indexarían publicaciones muertas.
  if (!producto) notFound();

  const estado = etiquetaEstado(producto);
  const rol = subtituloRol(producto.vendedor);
  const urlProducto = `${SITE_URL}/producto/${producto.id}`;
  // Vendido o pausado no se oculta: se muestra el producto con su estado, que
  // es la información que el visitante vino a buscar.
  const yaNoDisponible = producto.estado === 'sold' || producto.estado === 'sold_out';

  return (
    // El padding inferior deja aire para el SmartBanner fijo.
    <main className="contenedor" style={{ padding: '18px 18px 120px' }}>
      <Galeria fotos={producto.fotos} titulo={producto.titulo} />

      <div style={{ marginTop: 16 }}>
        <span className={`pill pill--${estado.tono}`}>{estado.texto}</span>
      </div>

      <h1 style={{ margin: '10px 0 0', fontSize: 26, lineHeight: 1.25 }}>
        {producto.titulo}
      </h1>

      <div
        style={{
          display: 'flex',
          alignItems: 'baseline',
          flexWrap: 'wrap',
          gap: 10,
          marginTop: 8,
        }}
      >
        <span
          style={{
            fontFamily: 'var(--fuente-titulo)',
            fontSize: 32,
            fontWeight: 700,
            color: yaNoDisponible ? 'var(--muted)' : 'var(--primary)',
          }}
        >
          {formatearPrecio(producto.precio)}
        </span>

        {producto.precioAnterior != null &&
          producto.precioAnterior > producto.precio && (
            <>
              <span
                style={{
                  color: 'var(--muted)',
                  textDecoration: 'line-through',
                  fontSize: 16,
                }}
              >
                {formatearPrecio(producto.precioAnterior)}
              </span>
              {producto.etiquetaDescuento && (
                <span
                  className="pill"
                  style={{
                    color: 'var(--amber-dark)',
                    background: 'var(--champagne)',
                  }}
                >
                  {producto.etiquetaDescuento}
                </span>
              )}
            </>
          )}
      </div>

      {producto.descripcion && (
        <>
          <hr className="separador" />
          <h2
            style={{
              fontSize: 13,
              fontFamily: 'var(--fuente-cuerpo)',
              fontWeight: 600,
              color: 'var(--muted)',
              textTransform: 'uppercase',
              letterSpacing: '0.04em',
            }}
          >
            Descripción
          </h2>
          <p style={{ margin: '8px 0 0', fontSize: 15, whiteSpace: 'pre-line' }}>
            {producto.descripcion}
          </p>
        </>
      )}

      {producto.categoria && (
        <div style={{ marginTop: 14 }}>
          <span
            className="pill"
            style={{ background: 'var(--surface-muted)', color: 'var(--muted)' }}
          >
            {producto.categoria.nombre}
          </span>
        </div>
      )}

      {producto.vendedor && (
        <>
          <hr className="separador" />
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div
              aria-hidden="true"
              style={{
                width: 44,
                height: 44,
                flexShrink: 0,
                borderRadius: 999,
                display: 'grid',
                placeItems: 'center',
                background: 'color-mix(in srgb, var(--primary) 12%, transparent)',
                color: 'var(--primary)',
                fontWeight: 700,
                fontSize: 15,
              }}
            >
              {producto.vendedor.iniciales}
            </div>
            <div style={{ minWidth: 0 }}>
              <p style={{ margin: 0, fontWeight: 700, fontSize: 16 }}>
                {producto.vendedor.nombre}
                {producto.vendedor.verificado && (
                  <span
                    title="Cuenta verificada"
                    style={{ marginLeft: 6, color: 'var(--primary)' }}
                  >
                    ✓
                  </span>
                )}
              </p>
              {/* Sin rol comprobado no se pinta la línea, igual que en la app. */}
              {rol && (
                <p style={{ margin: 0, fontSize: 13, color: 'var(--muted)' }}>{rol}</p>
              )}
            </div>
          </div>
        </>
      )}

      <hr className="separador" />

      <CtaContacto
        urlProducto={urlProducto}
        nombreVendedor={producto.vendedor?.nombre ?? null}
      />

      {producto.publicadoHace && (
        <p
          style={{
            margin: '22px 0 0',
            textAlign: 'center',
            fontSize: 12.5,
            color: 'var(--muted)',
          }}
        >
          Publicado {producto.publicadoHace}
        </p>
      )}
    </main>
  );
}
