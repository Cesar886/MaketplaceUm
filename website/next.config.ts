import type { NextConfig } from 'next';

const config: NextConfig = {
  reactStrictMode: true,
  // Las fotos se sirven con <img> y no con next/image: el backend expone
  // /uploads por HTTP plano y sin dominio, así que el optimizador de Vercel
  // no puede firmarlas ni cachearlas de forma fiable. Cuando el backend tenga
  // TLS y dominio propio, esto se cambia por `images.remotePatterns`.
};

export default config;
