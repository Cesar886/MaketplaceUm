import type { Metadata } from 'next';
import { Suspense } from 'react';

import AdminAuthGate from './admin-auth-gate';
import AdminPanel from './admin-panel';
import styles from './revision.module.css';

export const metadata: Metadata = {
  title: 'Centro de administración · Marketplace UM',
  description: 'Panel privado de operaciones de Marketplace UM.',
  robots: { index: false, follow: false },
};

export default function RevisionPage() {
  return (
    <main className={styles.page}>
      <AdminAuthGate>
        <Suspense fallback={<p className={styles.state}>Preparando panel administrativo…</p>}>
          <AdminPanel />
        </Suspense>
      </AdminAuthGate>
    </main>
  );
}
