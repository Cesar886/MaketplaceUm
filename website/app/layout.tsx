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

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: 'Mercadito UM',
  description:
    'Compra y vende dentro de la Universidad de Montemorelos.',
  applicationName: 'Mercadito UM',
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
