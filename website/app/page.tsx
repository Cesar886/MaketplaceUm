import type { Metadata } from 'next';

import CtaContacto from '@/components/CtaContacto';
import { SITE_URL } from '@/lib/api';

export const metadata: Metadata = {
  title: 'Marketplace UM — Compra y vende dentro de la UM',
  description:
    'El mercado de la Universidad de Montemorelos: libros, apuntes, electrónicos y más, entre alumnos, personal y negocios de la comunidad.',
  alternates: { canonical: SITE_URL },
};

export default function Inicio() {
  return (
    <main
      className="contenedor"
      style={{ padding: '72px 18px 120px', textAlign: 'center' }}
    >
      <h1 style={{ fontSize: 34, lineHeight: 1.15 }}>Marketplace UM</h1>
      <p
        style={{
          margin: '14px auto 0',
          maxWidth: 440,
          fontSize: 16,
          color: 'var(--muted)',
        }}
      >
        Compra y vende dentro de la Universidad de Montemorelos. Libros,
        apuntes, electrónicos y los negocios de la comunidad, en un solo lugar.
      </p>

      <div style={{ maxWidth: 420, margin: '34px auto 0' }}>
        <CtaContacto urlProducto={SITE_URL} nombreVendedor={null} />
      </div>
    </main>
  );
}
