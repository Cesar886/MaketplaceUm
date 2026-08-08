'use client';

import { useEffect, useState } from 'react';

import QrProducto from './QrProducto';
import { detectarPlataforma, urlTienda, type Plataforma } from '@/lib/tiendas';

/**
 * CTA principal: en vez de exponer el WhatsApp del vendedor (que ni siquiera
 * viaja en la respuesta pública), empuja a instalar la app.
 *
 * En móvil es un botón a la tienda que corresponda; en escritorio, un QR a
 * esta misma URL. La plataforma se resuelve tras hidratar, así que hasta
 * entonces se pinta el estado neutro — nunca un botón de la tienda
 * equivocada.
 */
export default function CtaContacto({
  urlProducto,
  nombreVendedor,
}: {
  urlProducto: string;
  nombreVendedor: string | null;
}) {
  const [plataforma, setPlataforma] = useState<Plataforma | null>(null);

  useEffect(() => {
    setPlataforma(detectarPlataforma(navigator.userAgent));
  }, []);

  if (plataforma === 'escritorio') {
    return <QrProducto url={urlProducto} />;
  }

  const destino = plataforma ? urlTienda(plataforma) : null;
  const aQuien = nombreVendedor ? `a ${nombreVendedor}` : 'al vendedor';

  return (
    <div>
      {destino ? (
        <a className="boton-principal" href={destino} rel="noopener">
          Contactar en la app
        </a>
      ) : (
        // Sin URL de tienda todavía: un botón que no lleva a ningún lado
        // erosiona más la confianza que decir claramente que falta poco.
        <div
          className="boton-principal"
          style={{ background: 'var(--surface-muted)', color: 'var(--muted)', cursor: 'default' }}
          aria-disabled="true"
        >
          Muy pronto en App Store y Google Play
        </div>
      )}
      <p
        style={{
          margin: '10px 0 0',
          textAlign: 'center',
          fontSize: 13,
          color: 'var(--muted)',
        }}
      >
        Para escribirle {aQuien} necesitas la app de Mercadito UM.
      </p>
    </div>
  );
}
