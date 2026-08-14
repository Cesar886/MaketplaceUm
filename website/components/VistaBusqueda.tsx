import CtaContacto from './CtaContacto';
import FichaVendedor from './FichaVendedor';
import { SITE_URL } from '@/lib/api';
import { formatearRango, textoBusqueda, tiempoRelativo } from '@/lib/formato';
import type { BusquedaPublica } from '@/lib/tipos';

/**
 * Cuerpo de la página para una publicación "se busca".
 *
 * No hay galería: una búsqueda no tiene fotos. El hueco no se rellena con un
 * placeholder — la página arranca directamente con lo que se pide, que es el
 * contenido real.
 */
export default function VistaBusqueda({ busqueda }: { busqueda: BusquedaPublica }) {
  const { encabezado, etiquetaPresupuesto } = textoBusqueda(busqueda);
  const rango = formatearRango(busqueda.precioMin, busqueda.precioMax);
  const publicado = tiempoRelativo(busqueda.publicadoEn);

  return (
    <>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
        <span className="pill pill--marca">{encabezado}</span>
        {!busqueda.abierta && (
          // El link compartido de una búsqueda ya resuelta sigue abriendo, así
          // que la página tiene que decirlo en vez de dejar creer que sigue viva.
          <span className="pill pill--neutro">Ya resuelta</span>
        )}
      </div>

      <h1 style={{ margin: '10px 0 0', fontSize: 26, lineHeight: 1.25 }}>
        {busqueda.titulo}
      </h1>

      <hr className="separador" />
      <h2 className="rotulo">{etiquetaPresupuesto}</h2>
      <p
        style={{
          margin: '6px 0 0',
          fontFamily: 'var(--fuente-titulo)',
          fontSize: rango ? 28 : 18,
          fontWeight: 700,
          color: busqueda.abierta ? 'var(--primary)' : 'var(--muted)',
        }}
      >
        {/* Sin ningún extremo del rango, decirlo con palabras: un "$0" aquí se
            leería como que no piensa pagar nada. */}
        {rango ?? 'Presupuesto abierto'}
      </p>

      {busqueda.descripcion && (
        <>
          <hr className="separador" />
          <h2 className="rotulo">Detalles</h2>
          <p style={{ margin: '8px 0 0', fontSize: 15, whiteSpace: 'pre-line' }}>
            {busqueda.descripcion}
          </p>
        </>
      )}

      {busqueda.categoria && (
        <div style={{ marginTop: 14 }}>
          <span
            className="pill"
            style={{ background: 'var(--surface-muted)', color: 'var(--muted)' }}
          >
            {busqueda.categoria.nombre}
          </span>
        </div>
      )}

      {busqueda.vendedor && (
        <>
          <hr className="separador" />
          <FichaVendedor vendedor={busqueda.vendedor} />
        </>
      )}

      <hr className="separador" />

      <CtaContacto
        urlProducto={`${SITE_URL}/producto/${busqueda.id}`}
        nombreVendedor={busqueda.vendedor?.nombre ?? null}
        sinNombre="a quien busca"
      />

      {publicado && <p className="pie-fecha">Publicado {publicado}</p>}
    </>
  );
}
