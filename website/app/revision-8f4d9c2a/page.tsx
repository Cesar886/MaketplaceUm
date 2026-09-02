import type { Metadata } from 'next';

import RevisionQueue from './revision-queue';
import styles from './revision.module.css';

export const metadata: Metadata = {
  title: 'Revisión privada',
  robots: { index: false, follow: false },
};

export default function RevisionPage() {
  return (
    <main className={styles.page}>
      <section className={styles.header}>
        <p className={styles.eyebrow}>Marketplace UM · acceso privado</p>
        <h1>Solicitudes de verificación</h1>
        <p>Revisa la documentación y decide cada solicitud pendiente.</p>
      </section>
      <RevisionQueue />
    </main>
  );
}
