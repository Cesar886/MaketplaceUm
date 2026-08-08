'use client';

import { useEffect, useState } from 'react';

import { detectarPlataforma, urlTienda, type Plataforma } from '@/lib/tiendas';

const CLAVE_DESCARTADO = 'mum-banner-descartado';

/**
 * Banner de instalación, fijo abajo. Va abajo y no arriba a propósito: la
 * parte alta de la página es la foto del producto, que es lo que el usuario
 * vino a ver y lo que decide si se queda.
 *
 * Se puede descartar, y el descarte dura la sesión (no para siempre): si el
 * usuario vuelve con otro link compartido, el puente a la app tiene que
 * seguir ahí.
 *
 * En escritorio no se muestra: no hay nada que instalar ahí, y el QR del CTA
 * ya cubre ese caso.
 */
export default function SmartBanner() {
  const [plataforma, setPlataforma] = useState<Plataforma | null>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const detectada = detectarPlataforma(navigator.userAgent);
    setPlataforma(detectada);
    if (detectada === 'escritorio') return;
    try {
      if (sessionStorage.getItem(CLAVE_DESCARTADO) !== '1') setVisible(true);
    } catch {
      // Modo privado sin sessionStorage: se muestra igual.
      setVisible(true);
    }
  }, []);

  if (!visible || !plataforma || plataforma === 'escritorio') return null;

  const destino = urlTienda(plataforma);

  function descartar() {
    setVisible(false);
    try {
      sessionStorage.setItem(CLAVE_DESCARTADO, '1');
    } catch {
      // Sin storage el descarte solo dura esta vista. Aceptable.
    }
  }

  return (
    <div
      style={{
        position: 'fixed',
        insetInline: 0,
        bottom: 0,
        zIndex: 40,
        display: 'flex',
        alignItems: 'center',
        gap: 12,
        padding: '10px 16px',
        background: 'var(--champagne)',
        borderTop: '1px solid var(--border)',
        // Respeta la barra de gestos en iOS.
        paddingBottom: 'calc(10px + env(safe-area-inset-bottom))',
      }}
    >
      <div style={{ flex: 1, minWidth: 0 }}>
        <p style={{ margin: 0, fontWeight: 700, fontSize: 14 }}>
          Descarga Mercadito UM
        </p>
        <p style={{ margin: 0, fontSize: 12.5, color: 'var(--muted)' }}>
          Compra y vende dentro de la Universidad de Montemorelos.
        </p>
      </div>

      {destino ? (
        <a
          href={destino}
          rel="noopener"
          style={{
            flexShrink: 0,
            padding: '8px 14px',
            borderRadius: 8,
            background: 'var(--primary)',
            color: '#fff',
            fontSize: 14,
            fontWeight: 700,
            textDecoration: 'none',
          }}
        >
          Abrir
        </a>
      ) : (
        <span style={{ flexShrink: 0, fontSize: 12.5, color: 'var(--muted)' }}>
          Muy pronto
        </span>
      )}

      <button
        onClick={descartar}
        aria-label="Cerrar el aviso de descarga"
        style={{
          flexShrink: 0,
          width: 30,
          height: 30,
          border: 0,
          borderRadius: 999,
          background: 'transparent',
          color: 'var(--muted)',
          fontSize: 19,
          lineHeight: 1,
          cursor: 'pointer',
        }}
      >
        ×
      </button>
    </div>
  );
}
