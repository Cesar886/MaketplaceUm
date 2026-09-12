import type { MetadataRoute } from 'next';

import { SITE_URL } from '@/lib/api';

const API_URL = process.env.API_URL ?? 'http://127.0.0.1:3000';

/**
 * Sitemap con una entrada por producto.
 *
 * Si el backend falla se devuelve solo la home en vez de lanzar: un sitemap
 * incompleto es un contratiempo, pero un build roto por una caída pasajera
 * del backend tumba el sitio entero.
 */
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const home: MetadataRoute.Sitemap = [
    {
      url: SITE_URL,
      lastModified: new Date(),
      changeFrequency: 'daily',
      priority: 1,
    },
  ];

  try {
    const res = await fetch(`${API_URL}/api/public/productos`, {
      next: { revalidate: 3600 },
    });
    if (!res.ok) return home;

    const { productos } = (await res.json()) as {
      productos: { id: string; actualizado: string | null }[];
    };

    return [
      ...home,
      ...productos.map(p => ({
        url: `${SITE_URL}/producto/${p.id}`,
        lastModified: p.actualizado ? new Date(p.actualizado) : undefined,
        changeFrequency: 'weekly' as const,
        priority: 0.8,
      })),
    ];
  } catch {
    return home;
  }
}
