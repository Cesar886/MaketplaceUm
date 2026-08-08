'use client';

import { useRef, useState } from 'react';

import { urlFoto } from '@/lib/api';

/**
 * Carrusel de fotos con scroll horizontal nativo (scroll-snap), no un slider
 * con JS: se siente igual que el swipe de la app, funciona sin hidratar y no
 * mete una dependencia solo para esto.
 */
export default function Galeria({
  fotos,
  titulo,
}: {
  fotos: string[];
  titulo: string;
}) {
  const [activa, setActiva] = useState(0);
  const pista = useRef<HTMLDivElement>(null);

  if (fotos.length === 0) {
    return (
      <div
        style={{
          aspectRatio: '4 / 3',
          borderRadius: 'var(--radio)',
          background: 'var(--surface-muted)',
          display: 'grid',
          placeItems: 'center',
          color: 'var(--muted)',
          fontSize: 14,
        }}
      >
        Sin fotos
      </div>
    );
  }

  function alDesplazar() {
    const nodo = pista.current;
    if (!nodo) return;
    const indice = Math.round(nodo.scrollLeft / nodo.clientWidth);
    if (indice !== activa) setActiva(indice);
  }

  return (
    <div style={{ position: 'relative' }}>
      <div
        ref={pista}
        onScroll={alDesplazar}
        style={{
          display: 'flex',
          overflowX: 'auto',
          scrollSnapType: 'x mandatory',
          scrollbarWidth: 'none',
          borderRadius: 'var(--radio)',
          background: 'var(--surface-muted)',
        }}
      >
        {fotos.map((foto, i) => (
          <img
            key={foto}
            src={urlFoto(foto)}
            alt={
              fotos.length > 1
                ? `${titulo} — foto ${i + 1} de ${fotos.length}`
                : titulo
            }
            // La primera es el LCP de la página: se carga con prioridad y el
            // resto en diferido.
            loading={i === 0 ? 'eager' : 'lazy'}
            fetchPriority={i === 0 ? 'high' : 'auto'}
            style={{
              flex: '0 0 100%',
              width: '100%',
              aspectRatio: '4 / 3',
              objectFit: 'cover',
              scrollSnapAlign: 'start',
            }}
          />
        ))}
      </div>

      {fotos.length > 1 && (
        <div
          style={{
            position: 'absolute',
            right: 12,
            bottom: 12,
            display: 'flex',
            gap: 5,
            padding: '5px 8px',
            borderRadius: 999,
            background: 'rgba(0,0,0,0.42)',
          }}
        >
          {fotos.map((foto, i) => (
            <span
              key={foto}
              style={{
                width: 6,
                height: 6,
                borderRadius: 999,
                background: i === activa ? '#fff' : 'rgba(255,255,255,0.45)',
              }}
            />
          ))}
        </div>
      )}
    </div>
  );
}
