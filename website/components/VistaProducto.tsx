import CtaContacto from './CtaContacto';
import FichaVendedor from './FichaVendedor';
import Galeria from './Galeria';
import { SITE_URL } from '@/lib/api';
import { etiquetaEstado, formatearPrecio } from '@/lib/formato';
import type { ProductoPublico } from '@/lib/tipos';

/** Cuerpo de la página para un producto en venta. */
export default function VistaProducto({ producto }: { producto: ProductoPublico }) {
  const estado = etiquetaEstado(producto);
  // Vendido o agotado no se oculta: se muestra el producto con su estado, que
  // es la información que el visitante vino a buscar.
  const yaNoDisponible =
    producto.estado === 'sold' || producto.estado === 'sold_out';

  return (
    <>
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
          <h2 className="rotulo">Descripción</h2>
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
          <FichaVendedor vendedor={producto.vendedor} />
        </>
      )}

      <hr className="separador" />

      <CtaContacto
        urlProducto={`${SITE_URL}/producto/${producto.id}`}
        nombreVendedor={producto.vendedor?.nombre ?? null}
      />

      {producto.publicadoHace && (
        <p className="pie-fecha">Publicado {producto.publicadoHace}</p>
      )}
    </>
  );
}
