import type { Metadata } from 'next';
import { Baloo_2, Work_Sans } from 'next/font/google';

import SmartBanner from '@/components/SmartBanner';
import { SITE_URL } from '@/lib/api';
import './globals.css';

// Las mismas dos familias que carga la app vía GoogleFonts
// (`lib/app_theme.dart`): Baloo 2 para títulos, Work Sans para el cuerpo.
const titulo = Baloo_2({
  subsets: ['latin'],
  weight: ['600', '700'],
  variable: '--fuente-titulo',
  display: 'swap',
});

const cuerpo = Work_Sans({
  subsets: ['latin'],
  weight: ['400', '500', '600', '700'],
  variable: '--fuente-cuerpo',
  display: 'swap',
});

// El favicon y el icono de iOS NO se declaran aquí ni con <link> a mano: Next
// los toma por convención de archivo de `app/icon.png` y `app/apple-icon.png`,
// y genera las etiquetas del <head> con un hash en la URL para romper caché.
// Ambos salen de assets/icon/app_icon.png, el mismo icono de la app, para que
// la pestaña del navegador y el ícono del launcher sean la misma marca.
// `apple-icon.png` va aplanado sobre blanco a propósito: iOS no respeta la
// transparencia en el icono de la pantalla de inicio y la pinta de negro.
export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: 'Marketplace UM — Todo dentro de tu comunidad',
  description:
    'Descubre, compra y vende dentro de la comunidad de la Universidad de Montemorelos.',
  applicationName: 'Marketplace UM',
  openGraph: {
    type: 'website',
    locale: 'es_MX',
    siteName: 'Marketplace UM',
    title: 'Marketplace UM',
    description: 'Todo lo que buscas, dentro de tu comunidad.',
    images: [{ url: '/og.png', width: 1536, height: 1024, alt: 'Marketplace UM' }],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Marketplace UM',
    description: 'Todo lo que buscas, dentro de tu comunidad.',
    images: ['/og.png'],
  },
};

export const viewport = {
  themeColor: '#3D5C70',
  width: 'device-width',
  initialScale: 1,
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="es-MX" className={`${titulo.variable} ${cuerpo.variable}`}>
      <body>
        {children}
        <SmartBanner />
      </body>
    </html>
  );
}
