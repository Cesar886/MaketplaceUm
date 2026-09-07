import type { Metadata } from 'next';

import AdminAuthGate from './admin-auth-gate';
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
        <h1>Control de verificaciones</h1>
        <p>Revisa solicitudes y administra la palomita azul de todas las cuentas comprobadas.</p>
      </section>
      <AdminAuthGate>
        <RevisionQueue />
      </AdminAuthGate>
    </main>
  );
}
