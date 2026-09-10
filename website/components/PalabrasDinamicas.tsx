'use client';

import { useEffect, useState } from 'react';

const PALABRAS = ['libros', 'tecnología', 'comida', 'oportunidades'];

export default function PalabrasDinamicas() {
  const [indice, setIndice] = useState(0);

  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const intervalo = window.setInterval(
      () => setIndice(actual => (actual + 1) % PALABRAS.length),
      2400,
    );
    return () => window.clearInterval(intervalo);
  }, []);

  return (
    <span className="palabra-dinamica-wrap">
      <span key={PALABRAS[indice]} className="palabra-dinamica" aria-hidden="true">
        {PALABRAS[indice]}
      </span>
      <span className="solo-lectores">libros, tecnología, comida y oportunidades</span>
    </span>
  );
}
