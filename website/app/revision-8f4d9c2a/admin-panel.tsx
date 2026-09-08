'use client';

import { FormEvent, ReactNode, useEffect, useMemo, useRef, useState } from 'react';
import { useSearchParams } from 'next/navigation';

import RevisionQueue from './revision-queue';
import styles from './admin-panel.module.css';

const base = '/revision-8f4d9c2a/api';
const sections = [
  ['verificaciones', 'Verificaciones'],
  ['dashboard', 'Dashboard'],
  ['reportes', 'Reportes'],
  ['usuarios', 'Usuarios'],
  ['publicaciones', 'Publicaciones'],
  ['configuracion', 'Configuración'],
  ['auditoria', 'Auditoría'],
] as const;
type Section = typeof sections[number][0];

type User = {
  id: string; name: string; email?: string | null; accountType?: string;
  verificationType?: string | null; isBusiness?: number | boolean; verified: number | boolean;
  adminStatus: 'active' | 'suspended' | 'banned'; adminStatusUntil?: string | null;
  adminStatusReason?: string | null; createdAt?: string | null; lastActive?: string | null;
  productCount: number; wantedCount: number; conversationCount?: number; profileViews?: number;
};
type Activity = { kind: 'product' | 'wanted'; id: string; title: string; createdAt: string; status: string };
type Publication = {
  kind: 'product' | 'wanted'; id: string; title: string; ownerId: string;
  ownerName: string; createdAt: string; moderationStatus: 'visible' | 'removed' | 'spam';
  domainStatus?: string | null; views: number;
};
type Report = {
  id: string; reporter_id: string; reporterName?: string | null;
  target_type: 'user' | 'product' | 'wanted' | 'chat'; target_id: string;
  target_user_id?: string | null; targetUserName?: string | null;
  reason: string; details?: string | null;
  status: 'received' | 'reviewing' | 'resolved' | 'dismissed';
  admin_note?: string | null; created_at: string; updated_at: string;
};
type ConfigRow = {
  key: string; productsActive: number; productsDaily: number; wantedActive: number;
  wantedDaily: number; durationDays: number; updatedAt?: string | null;
};

function formatDate(value?: string | null) {
  if (!value) return 'Sin registro';
  const date = new Date(value.includes('T') ? value : `${value.replace(' ', 'T')}Z`);
  return Number.isNaN(date.getTime())
    ? 'Sin registro'
    : new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium', timeStyle: 'short' }).format(date);
}

function statusLabel(value: string) {
  return ({ active: 'Activa', suspended: 'Suspendida', banned: 'Baneada', visible: 'Visible', removed: 'Retirada', spam: 'Spam', received: 'Recibido', reviewing: 'En revisión', resolved: 'Resuelto', dismissed: 'Descartado' } as Record<string, string>)[value] || value;
}

async function adminFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  if (init.method && init.method !== 'GET') {
    headers.set('Content-Type', 'application/json');
    headers.set('X-Revision-CSRF', '1');
  }
  const response = await fetch(base + path, { ...init, headers, cache: 'no-store', credentials: 'same-origin' });
  let payload: Record<string, unknown> = {};
  try { payload = await response.json() as Record<string, unknown>; } catch {}
  if (response.status === 401) window.dispatchEvent(new Event('mercadito:admin-session-expired'));
  if (!response.ok) throw new Error(typeof payload.error === 'string' ? payload.error : 'No se pudo completar la operación.');
  return payload as T;
}

function StatusBadge({ status }: { status: string }) {
  return <span className={`${styles.badge} ${styles[`badge_${status}`] ?? ''}`}>{statusLabel(status)}</span>;
}

function PanelState({ children, error = false }: { children: ReactNode; error?: boolean }) {
  return <div className={`${styles.panelState} ${error ? styles.panelError : ''}`} role={error ? 'alert' : 'status'}>{children}</div>;
}

function ActionDialog({ title, eyebrow, children, onClose }: {
  title: string; eyebrow: string; children: ReactNode; onClose: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    if (dialog && !dialog.open) dialog.showModal();
    return () => { if (dialog?.open) dialog.close(); };
  }, []);
  return (
    <dialog className={styles.dialog} onCancel={event => { event.preventDefault(); onClose(); }} ref={ref}>
      <div className={styles.dialogHeading}>
        <div><p className={styles.eyebrow}>{eyebrow}</p><h2>{title}</h2></div>
        <button aria-label="Cerrar" className={styles.iconButton} onClick={onClose} type="button">×</button>
      </div>
      {children}
    </dialog>
  );
}

function DashboardPanel() {
  const [data, setData] = useState<any>(null);
  const [error, setError] = useState('');
  useEffect(() => { adminFetch('/admin/dashboard').then(setData).catch(e => setError(e.message)); }, []);
  if (error) return <PanelState error>{error}</PanelState>;
  if (!data) return <PanelState>Cargando panorama operativo…</PanelState>;
  const metrics = [
    ['Usuarios activos', data.users.active7d, data.users.activeDefinition],
    ['Publicaciones hoy', data.publications.today, `${data.publications.productsToday} productos · ${data.publications.wantedToday} búsquedas`],
    ['Publicaciones 7 días', data.publications.week, 'Productos y “Se busca” creados'],
    ['Verificaciones pendientes', data.pendingVerifications, 'Solicitudes por resolver'],
  ];
  return (
    <section aria-labelledby="dashboard-title" className={styles.sectionPanel}>
      <div className={styles.sectionHeading}><div><p className={styles.eyebrow}>Estado de la plataforma</p><h2 id="dashboard-title">Dashboard</h2></div><span className={styles.livePill}><i /> Datos en vivo</span></div>
      <div className={styles.metricGrid}>{metrics.map(([label, value, note]) => <article className={styles.metricCard} key={String(label)}><span>{label}</span><strong>{value}</strong><p>{note}</p></article>)}</div>
      <div className={styles.splitCards}>
        <article className={styles.insightCard}><p className={styles.eyebrow}>Cuentas</p><h3>{data.users.enabled} habilitadas</h3><div className={styles.statLine}><span>Suspendidas</span><strong>{data.users.suspended}</strong></div><div className={styles.statLine}><span>Baneadas</span><strong>{data.users.banned}</strong></div><div className={styles.statLine}><span>Total registradas</span><strong>{data.users.total}</strong></div></article>
        <article className={styles.insightCard}><p className={styles.eyebrow}>Atención prioritaria</p><h3>Revisión de confianza</h3><p className={styles.muted}>Mantén las verificaciones al día y usa la auditoría para revisar quién ejecutó cada cambio sensible.</p><a className={styles.primaryLink} href="?section=verificaciones">Abrir verificaciones <span>→</span></a></article>
      </div>
    </section>
  );
}

function UsersPanel() {
  const [queryInput, setQueryInput] = useState('');
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('all');
  const [users, setUsers] = useState<User[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [selected, setSelected] = useState<{ user: User; recentActivity: Activity[] } | null>(null);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [action, setAction] = useState<{ ids: string[]; status?: User['adminStatus']; verification?: boolean; reset?: boolean } | null>(null);
  const [reasonText, setReasonText] = useState('');
  const [until, setUntil] = useState('');
  const [working, setWorking] = useState(false);

  const load = () => {
    setLoading(true); setError('');
    const params = new URLSearchParams({ page: '1', limit: '50', status });
    if (query) params.set('q', query);
    adminFetch<{ users: User[]; total: number }>(`/admin/users?${params}`)
      .then(result => { setUsers(result.users); setTotal(result.total); setSelectedIds(new Set()); })
      .catch(e => setError(e.message)).finally(() => setLoading(false));
  };
  useEffect(load, [query, status]);

  async function openDetail(id: string) {
    try { setSelected(await adminFetch(`/admin/users/${encodeURIComponent(id)}`)); }
    catch (e) { setError(e instanceof Error ? e.message : 'No se pudo cargar la cuenta.'); }
  }

  function closeAction() { if (!working) { setAction(null); setReasonText(''); setUntil(''); } }

  async function submitAction(event: FormEvent) {
    event.preventDefault();
    if (!action) return;
    setWorking(true); setError('');
    try {
      if (action.reset) {
        await adminFetch(`/admin/users/${encodeURIComponent(action.ids[0])}/reset-limits`, { method: 'POST', body: JSON.stringify({ scope: 'all' }) });
      } else if (action.verification !== undefined) {
        const user = users.find(item => item.id === action.ids[0]) || selected?.user;
        await adminFetch(`?id=${encodeURIComponent(action.ids[0])}&action=set-verification`, {
          method: 'POST', body: JSON.stringify({ verified: action.verification, expectedVerified: !!user?.verified, requestId: crypto.randomUUID(), reason: reasonText.trim() }),
        });
      } else if (action.ids.length > 1) {
        await adminFetch('/admin/users/bulk/status', { method: 'POST', body: JSON.stringify({ ids: action.ids, status: action.status, reason: reasonText.trim(), until: action.status === 'suspended' ? new Date(until).toISOString() : null }) });
      } else {
        const user = users.find(item => item.id === action.ids[0]) || selected?.user;
        await adminFetch(`/admin/users/${encodeURIComponent(action.ids[0])}/status`, { method: 'PATCH', body: JSON.stringify({ status: action.status, expectedStatus: user?.adminStatus, reason: reasonText.trim(), until: action.status === 'suspended' ? new Date(until).toISOString() : null }) });
      }
      setAction(null); setReasonText(''); setUntil(''); setSelected(null); load();
    } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo aplicar la acción.'); }
    finally { setWorking(false); }
  }

  const allSelected = users.length > 0 && users.every(user => selectedIds.has(user.id));
  return (
    <section aria-labelledby="users-title" className={styles.sectionPanel}>
      <div className={styles.sectionHeading}><div><p className={styles.eyebrow}>Control de cuentas</p><h2 id="users-title">Usuarios</h2><p>Busca, revisa actividad y aplica medidas con trazabilidad.</p></div><span className={styles.countPill}>{total} cuentas</span></div>
      <form className={styles.toolbar} onSubmit={event => { event.preventDefault(); setQuery(queryInput.trim()); }}>
        <label className={styles.searchField}><span>Buscar cuenta</span><input maxLength={100} onChange={e => setQueryInput(e.target.value)} placeholder="Nombre, correo o ID" value={queryInput} /></label>
        <label><span>Estado</span><select onChange={e => setStatus(e.target.value)} value={status}><option value="all">Todos</option><option value="active">Activas</option><option value="suspended">Suspendidas</option><option value="banned">Baneadas</option></select></label>
        <button className={styles.secondaryButton} type="submit">Buscar</button>
      </form>
      {selectedIds.size > 0 && <div className={styles.selectionBar}><strong>{selectedIds.size} seleccionadas</strong><span>Se creará y verificará un backup antes de una acción masiva.</span><button onClick={() => setAction({ ids: [...selectedIds], status: 'suspended' })} type="button">Suspender</button><button className={styles.dangerText} onClick={() => setAction({ ids: [...selectedIds], status: 'banned' })} type="button">Banear</button></div>}
      {error && <PanelState error>{error}</PanelState>}
      {loading ? <PanelState>Cargando usuarios…</PanelState> : users.length === 0 ? <PanelState>No hay cuentas con estos filtros.</PanelState> : (
        <div className={styles.tableWrap}><table className={styles.dataTable}><thead><tr><th><input aria-label="Seleccionar todas" checked={allSelected} onChange={e => setSelectedIds(e.target.checked ? new Set(users.map(user => user.id)) : new Set())} type="checkbox" /></th><th>Cuenta</th><th>Tipo</th><th>Actividad</th><th>Verificación</th><th>Estado</th><th><span className={styles.srOnly}>Acciones</span></th></tr></thead><tbody>{users.map(user => <tr key={user.id}><td><input aria-label={`Seleccionar ${user.name}`} checked={selectedIds.has(user.id)} onChange={e => { const next = new Set(selectedIds); e.target.checked ? next.add(user.id) : next.delete(user.id); setSelectedIds(next); }} type="checkbox" /></td><td><strong>{user.name}</strong><small>{user.email || user.id}</small></td><td>{user.isBusiness ? 'Negocio' : user.accountType === 'particular' ? 'Externo' : 'UM'}</td><td><strong>{user.productCount + user.wantedCount}</strong><small>{formatDate(user.lastActive)}</small></td><td>{user.verified ? <span className={styles.verified}>Verificada</span> : <span className={styles.muted}>Sin verificar</span>}</td><td><StatusBadge status={user.adminStatus} /></td><td><button className={styles.rowButton} onClick={() => openDetail(user.id)} type="button">Administrar</button></td></tr>)}</tbody></table></div>
      )}
      {selected && <ActionDialog eyebrow="Expediente de cuenta" onClose={() => setSelected(null)} title={selected.user.name}><div className={styles.detailGrid}><div><span>Correo</span><strong>{selected.user.email || 'Sin correo'}</strong></div><div><span>Estado</span><StatusBadge status={selected.user.adminStatus} /></div><div><span>Publicaciones</span><strong>{selected.user.productCount} productos · {selected.user.wantedCount} búsquedas</strong></div><div><span>Visitas al perfil</span><strong>{selected.user.profileViews ?? 0}</strong></div><div><span>Conversaciones</span><strong>{selected.user.conversationCount ?? 0}</strong></div><div><span>Última actividad</span><strong>{formatDate(selected.user.lastActive)}</strong></div><div><span>Alta</span><strong>{formatDate(selected.user.createdAt)}</strong></div></div><div className={styles.dialogActions}><button onClick={() => setAction({ ids: [selected.user.id], reset: true })} type="button">Resetear cupos</button><button onClick={() => setAction({ ids: [selected.user.id], verification: !selected.user.verified })} type="button">{selected.user.verified ? 'Quitar verificación' : 'Forzar verificación'}</button>{selected.user.adminStatus !== 'active' ? <button onClick={() => setAction({ ids: [selected.user.id], status: 'active' })} type="button">Reactivar</button> : <><button onClick={() => setAction({ ids: [selected.user.id], status: 'suspended' })} type="button">Suspender</button><button className={styles.dangerButton} onClick={() => setAction({ ids: [selected.user.id], status: 'banned' })} type="button">Banear</button></>}</div><div className={styles.activityList}><h3>Actividad reciente</h3>{selected.recentActivity.length ? selected.recentActivity.map(item => <div key={`${item.kind}-${item.id}`}><span>{item.kind === 'product' ? 'Producto' : 'Se busca'}</span><strong>{item.title}</strong><time>{formatDate(item.createdAt)}</time></div>) : <p className={styles.muted}>Sin publicaciones recientes.</p>}</div></ActionDialog>}
      {action && <ActionDialog eyebrow="Acción protegida" onClose={closeAction} title={action.reset ? 'Resetear límites diarios' : action.verification !== undefined ? (action.verification ? 'Forzar verificación' : 'Quitar verificación') : `${statusLabel(action.status || '')} ${action.ids.length > 1 ? `${action.ids.length} cuentas` : 'cuenta'}`}><form className={styles.actionForm} onSubmit={submitAction}><p className={styles.warningText}>{action.ids.length > 1 ? 'El servidor generará un backup SQLite verificado antes de tocar las cuentas.' : action.reset ? 'Esto reinicia los cupos diarios; no elimina publicaciones activas.' : 'La sesión actual de la cuenta se invalidará inmediatamente.'}</p>{!action.reset && <label><span>Motivo obligatorio</span><textarea autoFocus maxLength={500} minLength={10} onChange={e => setReasonText(e.target.value)} required value={reasonText} /><small>{reasonText.trim().length}/500 · mínimo 10</small></label>}{action.status === 'suspended' && <label><span>Suspender hasta</span><input min={new Date(Date.now() + 3600000).toISOString().slice(0, 16)} onChange={e => setUntil(e.target.value)} required type="datetime-local" value={until} /></label>}<div className={styles.dialogFooter}><button disabled={working} onClick={closeAction} type="button">Cancelar</button><button className={action.status === 'banned' ? styles.dangerButton : styles.primaryButton} disabled={working || (!action.reset && reasonText.trim().length < 10)} type="submit">{working ? 'Aplicando…' : 'Confirmar acción'}</button></div></form></ActionDialog>}
    </section>
  );
}

function PublicationsPanel() {
  const [queryInput, setQueryInput] = useState(''); const [query, setQuery] = useState('');
  const [kind, setKind] = useState('all'); const [status, setStatus] = useState('all');
  const [items, setItems] = useState<Publication[]>([]); const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true); const [error, setError] = useState('');
  const [action, setAction] = useState<{ item: Publication; target: 'spam' | 'removed' } | null>(null);
  const [reasonText, setReasonText] = useState(''); const [working, setWorking] = useState(false);
  const load = () => { setLoading(true); const p = new URLSearchParams({ page: '1', limit: '50', kind, status }); if (query) p.set('q', query); adminFetch<{ publications: Publication[]; total: number }>(`/admin/publications?${p}`).then(r => { setItems(r.publications); setTotal(r.total); }).catch(e => setError(e.message)).finally(() => setLoading(false)); };
  useEffect(load, [query, kind, status]);
  async function moderate(event: FormEvent) { event.preventDefault(); if (!action) return; setWorking(true); try { const route = `/admin/publications/${action.item.kind}/${encodeURIComponent(action.item.id)}${action.target === 'spam' ? '/spam' : ''}`; await adminFetch(route, { method: action.target === 'spam' ? 'PATCH' : 'DELETE', body: JSON.stringify({ reason: reasonText.trim(), expectedStatus: action.item.moderationStatus }) }); setAction(null); setReasonText(''); load(); } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo moderar.'); } finally { setWorking(false); } }
  return <section aria-labelledby="publications-title" className={styles.sectionPanel}><div className={styles.sectionHeading}><div><p className={styles.eyebrow}>Catálogo global</p><h2 id="publications-title">Publicaciones</h2><p>Modera productos y solicitudes sin destruir la evidencia.</p></div><span className={styles.countPill}>{total} registros</span></div><form className={styles.toolbar} onSubmit={e => { e.preventDefault(); setQuery(queryInput.trim()); }}><label className={styles.searchField}><span>Buscar</span><input maxLength={100} onChange={e => setQueryInput(e.target.value)} placeholder="Título, autor o ID" value={queryInput} /></label><label><span>Tipo</span><select onChange={e => setKind(e.target.value)} value={kind}><option value="all">Todos</option><option value="product">Productos</option><option value="wanted">Se busca</option></select></label><label><span>Moderación</span><select onChange={e => setStatus(e.target.value)} value={status}><option value="all">Todos</option><option value="visible">Visible</option><option value="spam">Spam</option><option value="removed">Retirada</option></select></label><button className={styles.secondaryButton} type="submit">Filtrar</button></form>{error && <PanelState error>{error}</PanelState>}{loading ? <PanelState>Cargando catálogo…</PanelState> : items.length === 0 ? <PanelState>No hay publicaciones con estos filtros.</PanelState> : <div className={styles.tableWrap}><table className={styles.dataTable}><thead><tr><th>Publicación</th><th>Tipo</th><th>Autor</th><th>Fecha</th><th>Estado</th><th>Vistas</th><th><span className={styles.srOnly}>Acciones</span></th></tr></thead><tbody>{items.map(item => <tr key={`${item.kind}-${item.id}`}><td><strong>{item.title}</strong><small>{item.id}</small></td><td>{item.kind === 'product' ? 'Producto' : 'Se busca'}</td><td><strong>{item.ownerName}</strong><small>{item.ownerId}</small></td><td>{formatDate(item.createdAt)}</td><td><StatusBadge status={item.moderationStatus} /></td><td>{item.views}</td><td>{item.moderationStatus === 'visible' ? <div className={styles.rowActions}><button onClick={() => setAction({ item, target: 'spam' })} type="button">Spam</button><button className={styles.dangerText} onClick={() => setAction({ item, target: 'removed' })} type="button">Retirar</button></div> : <span className={styles.muted}>Moderada</span>}</td></tr>)}</tbody></table></div>}{action && <ActionDialog eyebrow="Moderación" onClose={() => setAction(null)} title={action.target === 'spam' ? 'Marcar como spam' : 'Retirar publicación'}><form className={styles.actionForm} onSubmit={moderate}><p className={styles.warningText}>La publicación dejará de aparecer en feeds, búsquedas y detalles, pero la fila se conservará para auditoría.</p><label><span>Motivo obligatorio</span><textarea autoFocus maxLength={500} minLength={10} onChange={e => setReasonText(e.target.value)} required value={reasonText} /><small>{reasonText.trim().length}/500 · mínimo 10</small></label><div className={styles.dialogFooter}><button onClick={() => setAction(null)} type="button">Cancelar</button><button className={styles.dangerButton} disabled={working || reasonText.trim().length < 10} type="submit">{working ? 'Aplicando…' : 'Confirmar moderación'}</button></div></form></ActionDialog>}</section>;
}

function ReportsPanel() {
  const [status, setStatus] = useState('received');
  const [targetType, setTargetType] = useState('all');
  const [reports, setReports] = useState<Report[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [action, setAction] = useState<{ report: Report; status: Report['status'] } | null>(null);
  const [note, setNote] = useState('');
  const [working, setWorking] = useState(false);
  const load = () => {
    setLoading(true); setError('');
    const params = new URLSearchParams({ page: '1', limit: '50', status, targetType });
    adminFetch<{ reports: Report[]; total: number }>(`/admin/reports?${params}`)
      .then(result => { setReports(result.reports); setTotal(result.total); })
      .catch(e => setError(e.message))
      .finally(() => setLoading(false));
  };
  useEffect(load, [status, targetType]);
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!action) return;
    setWorking(true);
    try {
      await adminFetch(`/admin/reports/${encodeURIComponent(action.report.id)}`, {
        method: 'PATCH',
        body: JSON.stringify({ status: action.status, adminNote: note.trim() }),
      });
      setAction(null); setNote(''); load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudo actualizar el reporte.');
    } finally {
      setWorking(false);
    }
  }
  return <section aria-labelledby="reports-title" className={styles.sectionPanel}><div className={styles.sectionHeading}><div><p className={styles.eyebrow}>Confianza y seguridad</p><h2 id="reports-title">Reportes</h2><p>Casos creados desde perfiles, chats y publicaciones.</p></div><span className={styles.countPill}>{total} reportes</span></div><form className={styles.toolbar}><label><span>Estado</span><select onChange={e => setStatus(e.target.value)} value={status}><option value="all">Todos</option><option value="received">Recibidos</option><option value="reviewing">En revisión</option><option value="resolved">Resueltos</option><option value="dismissed">Descartados</option></select></label><label><span>Tipo</span><select onChange={e => setTargetType(e.target.value)} value={targetType}><option value="all">Todos</option><option value="user">Usuario</option><option value="product">Producto</option><option value="wanted">Se busca</option><option value="chat">Chat</option></select></label></form>{error && <PanelState error>{error}</PanelState>}{loading ? <PanelState>Cargando reportes…</PanelState> : reports.length === 0 ? <PanelState>No hay reportes con estos filtros.</PanelState> : <div className={styles.tableWrap}><table className={styles.dataTable}><thead><tr><th>Reporte</th><th>Reporta</th><th>Objetivo</th><th>Motivo</th><th>Estado</th><th>Fecha</th><th><span className={styles.srOnly}>Acciones</span></th></tr></thead><tbody>{reports.map(report => <tr key={report.id}><td><strong>{report.id}</strong><small>{report.details || 'Sin detalle adicional'}</small></td><td><strong>{report.reporterName || report.reporter_id}</strong><small>{report.reporter_id}</small></td><td><strong>{report.target_type}: {report.target_id}</strong><small>{report.targetUserName || report.target_user_id || 'Sin usuario asociado'}</small></td><td>{report.reason}</td><td><StatusBadge status={report.status} /></td><td>{formatDate(report.created_at)}</td><td><div className={styles.rowActions}>{report.status !== 'reviewing' && <button onClick={() => setAction({ report, status: 'reviewing' })} type="button">Revisar</button>}{report.status !== 'resolved' && <button onClick={() => setAction({ report, status: 'resolved' })} type="button">Resolver</button>}{report.status !== 'dismissed' && <button className={styles.dangerText} onClick={() => setAction({ report, status: 'dismissed' })} type="button">Descartar</button>}</div></td></tr>)}</tbody></table></div>}{action && <ActionDialog eyebrow="Reporte" onClose={() => setAction(null)} title={`${statusLabel(action.status)} ${action.report.id}`}><form className={styles.actionForm} onSubmit={submit}><p className={styles.warningText}>La decisión quedará en auditoría y el reporte conservará su evidencia.</p><label><span>Nota interna</span><textarea autoFocus maxLength={1000} onChange={e => setNote(e.target.value)} value={note} /></label><div className={styles.dialogFooter}><button onClick={() => setAction(null)} type="button">Cancelar</button><button className={action.status === 'dismissed' ? styles.dangerButton : styles.primaryButton} disabled={working} type="submit">{working ? 'Guardando…' : 'Guardar estado'}</button></div></form></ActionDialog>}</section>;
}

const configNames: Record<string, string> = { negocio_verificado: 'Negocio verificado', negocio_sin_verificar: 'Negocio sin verificar', um_verificado: 'UM verificado', um_sin_verificar: 'UM sin verificar', externo: 'Externo' };
const configFields = [['productsActive', 'Productos activos'], ['productsDaily', 'Productos / día'], ['wantedActive', '“Se busca” activos'], ['wantedDaily', '“Se busca” / día'], ['durationDays', 'Duración (días)']] as const;
function ConfigPanel() {
  const [rows, setRows] = useState<ConfigRow[]>([]); const [drafts, setDrafts] = useState<Record<string, ConfigRow>>({});
  const [error, setError] = useState(''); const [notice, setNotice] = useState(''); const [working, setWorking] = useState('');
  const load = () => adminFetch<{ config: ConfigRow[] }>('/admin/config').then(r => { setRows(r.config); setDrafts(Object.fromEntries(r.config.map(row => [row.key, { ...row }]))); }).catch(e => setError(e.message));
  useEffect(() => { void load(); }, []);
  async function save(key: string) { const row = drafts[key]; setWorking(key); setError(''); try { await adminFetch(`/admin/config/${key}`, { method: 'PUT', body: JSON.stringify(Object.fromEntries(configFields.map(([field]) => [field, Number(row[field])]))) }); setNotice(`${configNames[key]} actualizado.`); load(); } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo guardar.'); } finally { setWorking(''); } }
  async function reset(key: string) { if (!window.confirm(`¿Restablecer ${configNames[key]} a los valores predeterminados?`)) return; setWorking(key); try { await adminFetch(`/admin/config/${key}`, { method: 'DELETE', body: '{}' }); setNotice(`${configNames[key]} restablecido.`); load(); } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo restablecer.'); } finally { setWorking(''); } }
  return <section aria-labelledby="config-title" className={styles.sectionPanel}><div className={styles.sectionHeading}><div><p className={styles.eyebrow}>Políticas operativas</p><h2 id="config-title">Límites por cuenta</h2><p>Los cambios se aplican a nuevas publicaciones sin reiniciar el backend.</p></div></div>{notice && <div className={styles.successNotice} role="status">{notice}</div>}{error && <PanelState error>{error}</PanelState>}{rows.length === 0 ? <PanelState>Cargando configuración…</PanelState> : <div className={styles.configGrid}>{rows.map(row => { const draft = drafts[row.key] || row; return <article className={styles.configCard} key={row.key}><div className={styles.configHeading}><div><span>{row.key.replaceAll('_', ' ')}</span><h3>{configNames[row.key]}</h3></div><button disabled={working === row.key} onClick={() => reset(row.key)} type="button">Restablecer</button></div><div className={styles.configInputs}>{configFields.map(([field, label]) => <label key={field}><span>{label}</span><input min={field === 'durationDays' ? 1 : 0} onChange={e => setDrafts(current => ({ ...current, [row.key]: { ...draft, [field]: Number(e.target.value) } }))} required step="1" type="number" value={draft[field]} /></label>)}</div><div className={styles.configFooter}><small>Último cambio: {formatDate(row.updatedAt)}</small><button className={styles.primaryButton} disabled={working === row.key} onClick={() => save(row.key)} type="button">{working === row.key ? 'Guardando…' : 'Guardar límites'}</button></div></article>; })}</div>}</section>;
}

function AuditPanel() {
  const [entries, setEntries] = useState<any[]>([]); const [total, setTotal] = useState(0); const [error, setError] = useState('');
  useEffect(() => { adminFetch<{ entries: any[]; total: number }>('/admin/audit-log?page=1&limit=100').then(r => { setEntries(r.entries); setTotal(r.total); }).catch(e => setError(e.message)); }, []);
  return <section aria-labelledby="audit-title" className={styles.sectionPanel}><div className={styles.sectionHeading}><div><p className={styles.eyebrow}>Trazabilidad inmutable</p><h2 id="audit-title">Auditoría</h2><p>Cada cambio sensible queda atribuido al administrador autenticado.</p></div><span className={styles.countPill}>{total} eventos</span></div>{error && <PanelState error>{error}</PanelState>}{!error && entries.length === 0 ? <PanelState>Cargando bitácora…</PanelState> : <div className={styles.auditList}>{entries.map(entry => <article key={entry.id}><div className={styles.auditMark} /><div><strong>{entry.action}</strong><span>{entry.entityType} · {entry.entityId}</span></div><div className={styles.auditActor}><strong>{entry.adminUsername}</strong><time>{formatDate(entry.createdAt)}</time></div><details><summary>Detalles</summary><pre>{JSON.stringify(entry.details, null, 2)}</pre></details></article>)}</div>}</section>;
}

export default function AdminPanel() {
  const searchParams = useSearchParams();
  const requested = searchParams.get('section') as Section | null;
  const active = useMemo<Section>(() => sections.some(([key]) => key === requested) ? requested! : 'verificaciones', [requested]);
  return (
    <div className={styles.shell}>
      <header className={styles.hero}><div className={styles.brandMark} aria-hidden="true">UM</div><div><p className={styles.eyebrow}>Marketplace UM · Operaciones</p><h1>Centro de administración</h1><p>Confianza, catálogo y límites en un solo lugar.</p></div><div className={styles.securitySeal}><span aria-hidden="true">◆</span><div><strong>Sesión reforzada</strong><small>JWT · 2FA · Auditoría</small></div></div></header>
      <nav aria-label="Secciones administrativas" className={styles.nav}>{sections.map(([key, label], index) => <a aria-current={active === key ? 'page' : undefined} href={`?section=${key}`} key={key}><span>{String(index + 1).padStart(2, '0')}</span>{label}</a>)}</nav>
      <div className={styles.workspace}>{active === 'verificaciones' && <section className={styles.sectionPanel}><div className={styles.sectionHeading}><div><p className={styles.eyebrow}>Confianza de la comunidad</p><h2>Verificaciones</h2><p>La cola original permanece completa: pendientes, padrón e historial.</p></div></div><RevisionQueue /></section>}{active === 'dashboard' && <DashboardPanel />}{active === 'reportes' && <ReportsPanel />}{active === 'usuarios' && <UsersPanel />}{active === 'publicaciones' && <PublicationsPanel />}{active === 'configuracion' && <ConfigPanel />}{active === 'auditoria' && <AuditPanel />}</div>
      <footer className={styles.footer}><span>Marketplace UM</span><p>Panel privado · Todas las acciones sensibles quedan registradas.</p></footer>
    </div>
  );
}
