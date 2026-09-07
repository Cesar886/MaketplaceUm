'use client';

import { useEffect, useState } from 'react';

import styles from './revision.module.css';
import StaticMiniMap from './static-mini-map';

const apiBase = '/revision-8f4d9c2a/api';

type Document = {
  id: string | number;
  type: string;
  url: string;
  mimeType?: string;
  originalName?: string;
  uploadedAt?: string;
};
type BusinessHour = { open?: string; close?: string };
type Request = {
  id: string;
  submittedAt?: string | null;
  business: {
    name: string;
    profileName?: string | null;
    category?: string | null;
    responsibleName?: string | null;
    description?: string | null;
    phone?: string | null;
    email?: string | null;
    logoUrl?: string | null;
    accountCreatedAt?: string | null;
    businessHours?: Record<string, BusinessHour>;
    paymentMethods?: string[];
  };
  location?: {
    lat: number;
    lng: number;
    source: 'request' | 'profile';
  } | null;
  socialLinks?: {
    submitted?: string | null;
    facebook?: string | null;
    instagram?: string | null;
    whatsapp?: string | null;
    tiktok?: string | null;
    twitter?: string | null;
  };
  documents: Document[];
};

const dayLabel = [
  'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo',
];

const paymentLabel: Record<string, string> = {
  efectivo: 'Efectivo',
  tarjeta: 'Tarjeta',
  paypal: 'PayPal',
  cripto: 'Cripto',
  transferencia: 'Transferencia',
};
type HistoryAction = 'approved' | 'rejected' | 'revoked' | 'restored';
type HistoryEntry = {
  id: number;
  userId: string;
  action: HistoryAction;
  reason: string | null;
  business: {
    name: string;
    category?: string | null;
    responsibleName?: string | null;
  };
  decidedAt: string;
  currentVerified: boolean;
  canRevoke: boolean;
  canRestore: boolean;
  request: Request | null;
};
type AccountRole = 'negocio' | 'estudiante' | 'empleado';
type ManagedAccount = {
  id: string;
  name: string;
  email: string | null;
  role: AccountRole;
  verified: boolean;
  verificationState: 'pendiente' | 'verificado' | 'rechazado' | null;
  verifiedAt: string | null;
  createdAt: string | null;
  canVerify: boolean;
  canUnverify: boolean;
  verificationBlockedReason: string | null;
  lastChange: {
    action: 'verified' | 'unverified';
    reason: string;
    actor: string;
    decidedAt: string;
  } | null;
};
type AccountsPayload = {
  accounts: ManagedAccount[];
  pagination: { page: number; limit: number; total: number; totalPages: number };
  summary: { total: number; verified: number; unverified: number };
};
type AccountTypeFilter = 'all' | 'business' | 'student' | 'employee';
type AccountStatusFilter = 'all' | 'verified' | 'unverified';
type AccountChange = {
  account: ManagedAccount;
  targetVerified: boolean;
  requestId: string;
};
type AccountDetail = {
  account: Record<string, unknown>;
  verification: Record<string, unknown> | null;
  documents: Document[];
  badges: Array<Record<string, unknown>>;
  activity: Record<string, unknown>;
  verificationHistory: Array<Record<string, unknown>>;
  adminHistory: Array<Record<string, unknown>>;
};

type Notice = { kind: 'error' | 'success'; text: string } | null;

type ErrorPayload = { error?: string };

const documentLabel: Record<string, string> = {
  facade: 'Fachada',
  menu: 'Menú',
  responsible_ine_front: 'INE · frente',
  responsible_ine_back: 'INE · reverso',
  additional_evidence: 'Evidencia adicional',
};

const actionLabel: Record<HistoryAction, string> = {
  approved: 'Aceptada',
  rejected: 'Rechazada',
  revoked: 'Verificación retirada',
  restored: 'Verificación reactivada',
};

const accountRoleLabel: Record<AccountRole, string> = {
  negocio: 'Negocio',
  estudiante: 'Estudiante',
  empleado: 'Empleado UM',
};

const dateFormatter = new Intl.DateTimeFormat('es-MX', {
  dateStyle: 'medium',
  timeStyle: 'short',
  timeZone: 'America/Monterrey',
});

function isImage(document: Document) {
  return document.mimeType?.startsWith('image/')
    || /\.(avif|gif|jpe?g|png|webp)$/i.test(document.url);
}

function formatDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : dateFormatter.format(date);
}

const fieldLabels: Record<string, string> = {
  id: 'ID', name: 'Nombre', email: 'Correo', phone: 'Telefono', accountType: 'Tipo de cuenta',
  verificationType: 'Tipo de verificacion', verified: 'Verificada', createdAt: 'Creada',
  verifiedAt: 'Verificada el', institutionalEmail: 'Correo institucional', enrollment: 'Matricula',
  carrera: 'Carrera', businessName: 'Nombre del negocio', responsibleName: 'Responsable',
  businessCategory: 'Categoria', businessDescription: 'Descripcion', businessHours: 'Horario',
  paymentMethods: 'Metodos de pago', locationLat: 'Latitud', locationLng: 'Longitud',
  rating: 'Calificacion', reviews: 'Resenas', lastActive: 'Ultima actividad', authProvider: 'Acceso con',
  status: 'Estado', rejectionReason: 'Motivo de rechazo', rejectedField: 'Campo rechazado',
  identityConfirmedAt: 'Identidad confirmada', sendAttempts: 'Intentos de envio',
  confirmationAttempts: 'Intentos de confirmacion', action: 'Accion', reason: 'Motivo', actor: 'Administrador',
  decidedAt: 'Fecha', products: 'Productos', wantedPosts: 'Solicitudes', purchases: 'Compras',
  sales: 'Ventas', comments: 'Comentarios', questions: 'Preguntas', conversations: 'Conversaciones',
  notifications: 'Notificaciones', foundingPartner: 'Socio fundador', key: 'Insignia', awardedAt: 'Otorgada',
};

function detailValue(key: string, value: unknown) {
  if (value === null || value === undefined || value === '') return 'Sin dato';
  if (typeof value === 'boolean' || value === 0 || value === 1) {
    if (typeof value === 'boolean' || ['verified', 'isBusiness', 'showOnlineStatus', 'foundingPartner', 'previousVerified', 'newVerified'].includes(key)) return value ? 'Si' : 'No';
  }
  if (typeof value === 'string' && /(At|created|fecha|active|en)$/i.test(key)) return formatDate(value);
  if (typeof value === 'object') return JSON.stringify(value, null, 2);
  return String(value);
}

function DetailSection({ title, data }: { title: string; data: Record<string, unknown> | null }) {
  if (!data) return <section className={styles.detailSection}><h3>{title}</h3><p>Sin registros.</p></section>;
  return (
    <section className={styles.detailSection}>
      <h3>{title}</h3>
      <dl className={styles.detailGrid}>
        {Object.entries(data).map(([key, value]) => (
          <div key={key}>
            <dt>{fieldLabels[key] ?? key.replace(/([A-Z])/g, ' $1')}</dt>
            <dd className={typeof value === 'object' ? styles.longDetail : undefined}>{detailValue(key, value)}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

function normalizeSearch(value: string) {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim();
}

function safeUrl(value?: string | null) {
  if (!value) return null;
  try {
    const parsed = new URL(value);
    return ['http:', 'https:'].includes(parsed.protocol) ? parsed.toString() : null;
  } catch {
    return null;
  }
}

function socialEntries(request: Request) {
  const social = request.socialLinks;
  const candidates = [
    ['Enlace enviado para verificar', social?.submitted],
    ['Facebook', social?.facebook],
    ['Instagram', social?.instagram],
    ['WhatsApp', social?.whatsapp
      ? `https://wa.me/${social.whatsapp.replace(/\D/g, '')}`
      : null],
    ['TikTok', social?.tiktok],
    ['X / Twitter', social?.twitter],
  ] as const;
  const seen = new Set<string>();

  return candidates.flatMap(([label, value]) => {
    const url = safeUrl(value);
    if (!url || seen.has(url)) return [];
    seen.add(url);
    return [{ label, url }];
  });
}

function businessHourEntries(request: Request) {
  return Object.entries(request.business.businessHours ?? {})
    .map(([day, value]) => ({
      day: dayLabel[Number(day)] ?? `Día ${day}`,
      open: value?.open ?? '—',
      close: value?.close ?? '—',
      order: Number(day),
    }))
    .sort((a, b) => a.order - b.order);
}

async function payloadOrError<T>(response: Response, fallback: string): Promise<T> {
  const payload = await response.json() as T & ErrorPayload;
  if (!response.ok) {
    if (response.status === 401) {
      window.dispatchEvent(new Event('mercadito:admin-session-expired'));
    }
    throw new Error(payload.error || fallback);
  }
  return payload;
}

function VerificationDossier({
  request,
  onPreview,
}: {
  request: Request;
  onPreview: (document: Document) => void;
}) {
  const hours = businessHourEntries(request);
  const socials = socialEntries(request);
  const payments = request.business.paymentMethods ?? [];

  return (
    <div className={styles.dossier}>
      <div className={styles.dossierHeading}>
        <div>
          <p className={styles.eyebrow}>Expediente enviado</p>
          <h3>Todo lo revisado en esta decisión</h3>
        </div>
        {request.submittedAt && (
          <time dateTime={request.submittedAt}>{formatDate(request.submittedAt)}</time>
        )}
      </div>

      <dl className={styles.details}>
        <div>
          <dt>Responsable</dt>
          <dd>{request.business.responsibleName ?? 'No capturado'}</dd>
        </div>
        <div>
          <dt>Teléfono</dt>
          <dd>{request.business.phone ?? 'No capturado'}</dd>
        </div>
        <div>
          <dt>Correo</dt>
          <dd>
            {request.business.email
              ? <a href={`mailto:${request.business.email}`}>{request.business.email}</a>
              : 'No capturado'}
          </dd>
        </div>
        <div>
          <dt>Cuenta creada</dt>
          <dd>
            {request.business.accountCreatedAt
              ? formatDate(request.business.accountCreatedAt)
              : 'Sin fecha'}
          </dd>
        </div>
        <div>
          <dt>ID de cuenta</dt>
          <dd><code>{request.id}</code></dd>
        </div>
        {request.business.profileName
          && request.business.profileName !== request.business.name && (
          <div>
            <dt>Nombre guardado en el perfil</dt>
            <dd>{request.business.profileName}</dd>
          </div>
        )}
      </dl>

      <section className={styles.infoSection}>
        <h3>Descripción del negocio</h3>
        <p>{request.business.description ?? 'No se capturó una descripción.'}</p>
      </section>

      <section className={styles.infoSection}>
        <h3>Ubicación y coordenadas</h3>
        {request.location ? (
          <StaticMiniMap
            lat={request.location.lat}
            lng={request.location.lng}
            source={request.location.source}
          />
        ) : (
          <p className={styles.emptyValue}>No hay una ubicación registrada.</p>
        )}
      </section>

      <section className={styles.infoSection}>
        <h3>Redes sociales y enlace de verificación</h3>
        {socials.length ? (
          <div className={styles.linkGrid}>
            {socials.map(social => (
              <a
                href={social.url}
                key={`${social.label}-${social.url}`}
                rel="noreferrer"
                target="_blank"
              >
                <span>{social.label}</span>
                <strong>{social.url}</strong>
              </a>
            ))}
          </div>
        ) : (
          <p className={styles.emptyValue}>No hay redes sociales registradas.</p>
        )}
      </section>

      <div className={styles.profileGrid}>
        <section className={styles.infoSection}>
          <h3>Horario del negocio</h3>
          {hours.length ? (
            <dl className={styles.hoursList}>
              {hours.map(hour => (
                <div key={hour.order}>
                  <dt>{hour.day}</dt>
                  <dd>{hour.open} – {hour.close}</dd>
                </div>
              ))}
            </dl>
          ) : (
            <p className={styles.emptyValue}>No hay horarios registrados.</p>
          )}
        </section>

        <section className={styles.infoSection}>
          <h3>Métodos de pago</h3>
          {payments.length ? (
            <div className={styles.chips}>
              {payments.map(method => (
                <span key={method}>{paymentLabel[method] ?? method}</span>
              ))}
            </div>
          ) : (
            <p className={styles.emptyValue}>No hay métodos registrados.</p>
          )}
        </section>
      </div>

      <section className={styles.infoSection}>
        <h3>Documentos y evidencias</h3>
        {request.documents.length ? (
          <div className={styles.documents}>
            {request.documents.map(document => (
              <button
                className={styles.document}
                key={document.id}
                onClick={() => onPreview(document)}
                type="button"
              >
                {isImage(document)
                  ? <img alt={documentLabel[document.type] ?? 'Documento'} src={document.url} />
                  : <span className={styles.pdf}>PDF</span>}
                <span>{documentLabel[document.type] ?? document.type}</span>
                {document.originalName && (
                  <small title={document.originalName}>{document.originalName}</small>
                )}
              </button>
            ))}
          </div>
        ) : (
          <p className={styles.emptyValue}>No hay documentos adjuntos.</p>
        )}
      </section>
    </div>
  );
}

export default function RevisionQueue() {
  const [requests, setRequests] = useState<Request[]>([]);
  const [history, setHistory] = useState<HistoryEntry[]>([]);
  const [accountsData, setAccountsData] = useState<AccountsPayload>({
    accounts: [],
    pagination: { page: 1, limit: 25, total: 0, totalPages: 1 },
    summary: { total: 0, verified: 0, unverified: 0 },
  });
  const [view, setView] = useState<'pending' | 'accounts' | 'history'>('pending');
  const [loading, setLoading] = useState(true);
  const [accountsLoading, setAccountsLoading] = useState(false);
  const [notice, setNotice] = useState<Notice>(null);
  const [rejecting, setRejecting] = useState<string | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  const [revoking, setRevoking] = useState<number | null>(null);
  const [revokeReason, setRevokeReason] = useState('');
  const [restoring, setRestoring] = useState<number | null>(null);
  const [expandedHistory, setExpandedHistory] = useState<number | null>(null);
  const [historyQuery, setHistoryQuery] = useState('');
  const [accountQuery, setAccountQuery] = useState('');
  const [accountType, setAccountType] = useState<AccountTypeFilter>('all');
  const [accountStatus, setAccountStatus] = useState<AccountStatusFilter>('all');
  const [accountPage, setAccountPage] = useState(1);
  const [accountChange, setAccountChange] = useState<AccountChange | null>(null);
  const [accountDetail, setAccountDetail] = useState<AccountDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState<string | null>(null);
  const [accountReason, setAccountReason] = useState('');
  const [accountConfirmed, setAccountConfirmed] = useState(false);
  const [working, setWorking] = useState<string | null>(null);
  const [preview, setPreview] = useState<Document | null>(null);

  async function loadPending() {
    const response = await fetch(apiBase, { cache: 'no-store' });
    const data = await payloadOrError<{ requests: Request[] }>(
      response,
      'No se pudieron cargar las solicitudes.',
    );
    setRequests(data.requests ?? []);
  }

  async function loadHistory() {
    const response = await fetch(`${apiBase}?view=history`, { cache: 'no-store' });
    const data = await payloadOrError<{ entries: HistoryEntry[] }>(
      response,
      'No se pudo cargar el historial.',
    );
    setHistory(data.entries ?? []);
  }

  async function loadAccounts(page = accountPage, signal?: AbortSignal) {
    setAccountsLoading(true);
    const query = new URLSearchParams({
      view: 'accounts',
      page: String(page),
      limit: '25',
      type: accountType,
      verified: accountStatus,
    });
    if (accountQuery.trim()) query.set('q', accountQuery.trim());
    try {
      const response = await fetch(`${apiBase}?${query.toString()}`, {
        cache: 'no-store',
        signal,
      });
      const data = await payloadOrError<AccountsPayload>(
        response,
        'No se pudo cargar el padrón de cuentas.',
      );
      setAccountsData(data);
      if (data.pagination.page !== accountPage) {
        setAccountPage(data.pagination.page);
      }
    } finally {
      setAccountsLoading(false);
    }
  }

  async function openAccountDetail(account: ManagedAccount) {
    setDetailLoading(account.id);
    setNotice(null);
    try {
      const response = await fetch(`${apiBase}?view=accounts&accountId=${encodeURIComponent(account.id)}`, { cache: 'no-store' });
      setAccountDetail(await payloadOrError<AccountDetail>(response, 'No se pudo cargar el expediente.'));
    } catch (error) {
      setNotice({ kind: 'error', text: error instanceof Error ? error.message : 'No se pudo cargar el expediente.' });
    } finally {
      setDetailLoading(null);
    }
  }

  useEffect(() => {
    Promise.all([loadPending(), loadHistory(), loadAccounts(1)])
      .catch(error => setNotice({
        kind: 'error',
        text: error instanceof Error ? error.message : 'Ocurrió un error.',
      }))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    if (view !== 'accounts' || loading) return undefined;
    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      loadAccounts(accountPage, controller.signal).catch(error => {
        if (error instanceof DOMException && error.name === 'AbortError') return;
        setNotice({
          kind: 'error',
          text: error instanceof Error ? error.message : 'No se pudo cargar el padrón.',
        });
      });
    }, 250);
    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [view, accountQuery, accountType, accountStatus, accountPage]);

  async function decide(
    id: string,
    action: 'approve' | 'reject' | 'revoke' | 'restore',
    reason?: string,
  ) {
    const trimmedReason = reason?.trim() ?? '';
    if (['reject', 'revoke'].includes(action) && !trimmedReason) {
      setNotice({
        kind: 'error',
        text: action === 'reject'
          ? 'Escribe un motivo antes de rechazar la solicitud.'
          : 'Escribe un motivo antes de retirar la verificación.',
      });
      return;
    }

    const workKey = `${action}:${id}`;
    setWorking(workKey);
    setNotice(null);
    try {
      const response = await fetch(
        `${apiBase}?id=${encodeURIComponent(id)}&action=${action}`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Revision-CSRF': '1',
          },
          body: JSON.stringify({ reason: trimmedReason }),
        },
      );
      await payloadOrError<ErrorPayload>(response, 'No se pudo guardar la decisión.');

      if (['approve', 'reject'].includes(action)) {
        setRequests(current => current.filter(request => request.id !== id));
      }
      setRejecting(null);
      setRejectReason('');
      setRevoking(null);
      setRevokeReason('');
      setRestoring(null);

      try {
        await Promise.all([loadHistory(), loadAccounts(accountPage)]);
        setNotice({
          kind: 'success',
          text: action === 'approve'
            ? 'Cuenta aceptada. La decisión quedó guardada en el historial.'
            : action === 'reject'
              ? 'Solicitud rechazada. El motivo quedó guardado en el historial.'
              : action === 'revoke'
                ? 'La verificación fue retirada y el motivo quedó registrado.'
                : 'La cuenta volvió a estar verificada y quedó registrada la reactivación.',
        });
      } catch {
        setNotice({
          kind: 'error',
          text: 'La decisión se guardó, pero no se pudo actualizar el historial. Recarga la página.',
        });
      }
    } catch (error) {
      setNotice({
        kind: 'error',
        text: error instanceof Error ? error.message : 'Ocurrió un error.',
      });
    } finally {
      setWorking(null);
    }
  }

  function beginAccountChange(account: ManagedAccount, targetVerified: boolean) {
    setAccountChange({
      account,
      targetVerified,
      requestId: window.crypto.randomUUID(),
    });
    setAccountReason('');
    setAccountConfirmed(false);
    setNotice(null);
  }

  async function saveAccountVerification() {
    if (!accountChange) return;
    const reason = accountReason.trim();
    if (reason.length < 10) {
      setNotice({
        kind: 'error',
        text: 'Escribe un motivo de al menos 10 caracteres.',
      });
      return;
    }
    if (!accountConfirmed) {
      setNotice({
        kind: 'error',
        text: 'Confirma que revisaste la cuenta y el cambio solicitado.',
      });
      return;
    }

    const { account, targetVerified, requestId } = accountChange;
    const workKey = `account:${account.id}`;
    setWorking(workKey);
    setNotice(null);
    try {
      const response = await fetch(
        `${apiBase}?id=${encodeURIComponent(account.id)}&action=set-verification`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Revision-CSRF': '1',
          },
          body: JSON.stringify({
            verified: targetVerified,
            expectedVerified: account.verified,
            reason,
            requestId,
          }),
        },
      );
      await payloadOrError<ErrorPayload>(
        response,
        'No se pudo actualizar la verificación.',
      );
      setAccountChange(null);
      setAccountReason('');
      setAccountConfirmed(false);
      await loadAccounts(accountPage);
      setNotice({
        kind: 'success',
        text: targetVerified
          ? `La palomita azul de ${account.name} quedó activada y auditada.`
          : `La palomita azul de ${account.name} quedó retirada y auditada.`,
      });
    } catch (error) {
      setNotice({
        kind: 'error',
        text: error instanceof Error ? error.message : 'Ocurrió un error.',
      });
    } finally {
      setWorking(null);
    }
  }

  const normalizedHistoryQuery = normalizeSearch(historyQuery);
  const filteredHistory = normalizedHistoryQuery
    ? history.filter(entry => normalizeSearch([
        entry.business.name,
        entry.business.responsibleName ?? '',
        entry.userId,
      ].join(' ')).includes(normalizedHistoryQuery))
    : history;

  if (loading) return <p className={styles.state}>Cargando solicitudes e historial…</p>;

  return (
    <section className={styles.queue} aria-live="polite">
      <div className={styles.tabs} role="tablist" aria-label="Vistas de revisión">
        <button
          aria-selected={view === 'pending'}
          className={view === 'pending' ? styles.activeTab : undefined}
          onClick={() => setView('pending')}
          role="tab"
          type="button"
        >
          Pendientes <span>{requests.length}</span>
        </button>
        <button
          aria-selected={view === 'accounts'}
          className={view === 'accounts' ? styles.activeTab : undefined}
          onClick={() => setView('accounts')}
          role="tab"
          type="button"
        >
          Cuentas <span>{accountsData.summary.total}</span>
        </button>
        <button
          aria-selected={view === 'history'}
          className={view === 'history' ? styles.activeTab : undefined}
          onClick={() => setView('history')}
          role="tab"
          type="button"
        >
          Historial <span>{history.length}</span>
        </button>
      </div>

      {notice && (
        <p className={notice.kind === 'error' ? styles.error : styles.success}>
          {notice.text}
        </p>
      )}

      {view === 'pending' && (
        <div className={styles.list} role="tabpanel">
          {requests.length === 0 && (
            <p className={styles.state}>No hay solicitudes pendientes.</p>
          )}
          {requests.map(request => {
            const hours = businessHourEntries(request);
            const socials = socialEntries(request);
            const payments = request.business.paymentMethods ?? [];

            return (
              <article className={styles.card} key={request.id}>
                <div className={styles.business}>
                  <div className={styles.businessIdentity}>
                    {request.business.logoUrl ? (
                      <img
                        alt={`Logo de ${request.business.name}`}
                        className={styles.businessLogo}
                        src={request.business.logoUrl}
                      />
                    ) : (
                      <span aria-hidden="true" className={styles.logoFallback}>
                        {request.business.name.slice(0, 1).toUpperCase()}
                      </span>
                    )}
                    <div>
                      <p className={styles.eyebrow}>
                        {request.business.category ?? 'Negocio'}
                      </p>
                      <h2>{request.business.name}</h2>
                    </div>
                  </div>
                  <span className={styles.pending}>Pendiente</span>
                </div>

                <dl className={styles.details}>
                  <div>
                    <dt>Responsable</dt>
                    <dd>{request.business.responsibleName ?? 'No capturado'}</dd>
                  </div>
                  <div>
                    <dt>Teléfono</dt>
                    <dd>{request.business.phone ?? 'No capturado'}</dd>
                  </div>
                  <div>
                    <dt>Correo</dt>
                    <dd>
                      {request.business.email
                        ? <a href={`mailto:${request.business.email}`}>{request.business.email}</a>
                        : 'No capturado'}
                    </dd>
                  </div>
                  <div>
                    <dt>Solicitud enviada</dt>
                    <dd>
                      {request.submittedAt
                        ? <time dateTime={request.submittedAt}>{formatDate(request.submittedAt)}</time>
                        : 'Sin fecha'}
                    </dd>
                  </div>
                  <div>
                    <dt>Cuenta creada</dt>
                    <dd>
                      {request.business.accountCreatedAt
                        ? formatDate(request.business.accountCreatedAt)
                        : 'Sin fecha'}
                    </dd>
                  </div>
                  <div>
                    <dt>ID de cuenta</dt>
                    <dd><code>{request.id}</code></dd>
                  </div>
                  {request.business.profileName
                    && request.business.profileName !== request.business.name && (
                    <div className={styles.description}>
                      <dt>Nombre guardado en el perfil</dt>
                      <dd>{request.business.profileName}</dd>
                    </div>
                  )}
                </dl>

                <section className={styles.infoSection}>
                  <h3>Descripción del negocio</h3>
                  <p>{request.business.description ?? 'No se capturó una descripción.'}</p>
                </section>

                <section className={styles.infoSection}>
                  <h3>Ubicación y coordenadas</h3>
                  {request.location ? (
                    <StaticMiniMap
                      lat={request.location.lat}
                      lng={request.location.lng}
                      source={request.location.source}
                    />
                  ) : (
                    <p className={styles.emptyValue}>No hay una ubicación registrada.</p>
                  )}
                </section>

                <section className={styles.infoSection}>
                  <h3>Redes sociales y enlace de verificación</h3>
                  {socials.length ? (
                    <div className={styles.linkGrid}>
                      {socials.map(social => (
                        <a
                          href={social.url}
                          key={`${social.label}-${social.url}`}
                          rel="noreferrer"
                          target="_blank"
                        >
                          <span>{social.label}</span>
                          <strong>{social.url}</strong>
                        </a>
                      ))}
                    </div>
                  ) : (
                    <p className={styles.emptyValue}>No hay redes sociales registradas.</p>
                  )}
                </section>

                <div className={styles.profileGrid}>
                  <section className={styles.infoSection}>
                    <h3>Horario del negocio</h3>
                    {hours.length ? (
                      <dl className={styles.hoursList}>
                        {hours.map(hour => (
                          <div key={hour.order}>
                            <dt>{hour.day}</dt>
                            <dd>{hour.open} – {hour.close}</dd>
                          </div>
                        ))}
                      </dl>
                    ) : (
                      <p className={styles.emptyValue}>No hay horarios registrados.</p>
                    )}
                  </section>

                  <section className={styles.infoSection}>
                    <h3>Métodos de pago</h3>
                    {payments.length ? (
                      <div className={styles.chips}>
                        {payments.map(method => (
                          <span key={method}>{paymentLabel[method] ?? method}</span>
                        ))}
                      </div>
                    ) : (
                      <p className={styles.emptyValue}>No hay métodos registrados.</p>
                    )}
                  </section>
                </div>

                <section className={styles.infoSection}>
                  <h3>Documentos y evidencias</h3>
                  {request.documents.length ? (
                    <div className={styles.documents}>
                      {request.documents.map(document => (
                        <button
                          className={styles.document}
                          key={document.id}
                          onClick={() => setPreview(document)}
                          type="button"
                        >
                          {isImage(document)
                            ? <img alt={documentLabel[document.type] ?? 'Documento'} src={document.url} />
                            : <span className={styles.pdf}>PDF</span>}
                          <span>{documentLabel[document.type] ?? document.type}</span>
                        </button>
                      ))}
                    </div>
                  ) : (
                    <p className={styles.emptyValue}>No hay documentos adjuntos.</p>
                  )}
                </section>

                {rejecting === request.id ? (
                  <div className={styles.decisionBox}>
                    <label htmlFor={`reason-${request.id}`}>Motivo del rechazo</label>
                    <textarea
                      id={`reason-${request.id}`}
                      maxLength={500}
                      onChange={event => setRejectReason(event.target.value)}
                      placeholder="Indica qué debe corregirse."
                      value={rejectReason}
                    />
                    <div className={styles.actions}>
                      <button
                        onClick={() => {
                          setRejecting(null);
                          setRejectReason('');
                        }}
                        type="button"
                      >
                        Cancelar
                      </button>
                      <button
                        className={styles.reject}
                        disabled={working === `reject:${request.id}`}
                        onClick={() => decide(request.id, 'reject', rejectReason)}
                        type="button"
                      >
                        Confirmar rechazo
                      </button>
                    </div>
                  </div>
                ) : (
                  <div className={styles.actions}>
                    <button
                      className={styles.approve}
                      disabled={working === `approve:${request.id}`}
                      onClick={() => decide(request.id, 'approve')}
                      type="button"
                    >
                      Aprobar
                    </button>
                    <button
                      className={styles.reject}
                      disabled={working !== null}
                      onClick={() => {
                        setRejecting(request.id);
                        setRejectReason('');
                      }}
                      type="button"
                    >
                      Rechazar
                    </button>
                  </div>
                )}
              </article>
            );
          })}
        </div>
      )}

      {view === 'accounts' && (
        <div className={styles.accountsPanel} role="tabpanel">
          <div className={styles.accountSummary}>
            <div>
              <span>Total administrables</span>
              <strong>{accountsData.summary.total}</strong>
            </div>
            <div>
              <span>Con palomita azul</span>
              <strong>{accountsData.summary.verified}</strong>
            </div>
            <div>
              <span>Sin verificación</span>
              <strong>{accountsData.summary.unverified}</strong>
            </div>
          </div>

          <div className={styles.accountFilters}>
            <label className={styles.accountSearch}>
              <span>Buscar cuenta</span>
              <input
                maxLength={100}
                onChange={event => {
                  setAccountQuery(event.target.value);
                  setAccountPage(1);
                }}
                placeholder="Nombre, correo o ID"
                type="search"
                value={accountQuery}
              />
            </label>
            <label>
              <span>Tipo</span>
              <select
                onChange={event => {
                  setAccountType(event.target.value as AccountTypeFilter);
                  setAccountPage(1);
                }}
                value={accountType}
              >
                <option value="all">Todos</option>
                <option value="business">Negocios</option>
                <option value="student">Estudiantes</option>
                <option value="employee">Empleados UM</option>
              </select>
            </label>
            <label>
              <span>Estado</span>
              <select
                onChange={event => {
                  setAccountStatus(event.target.value as AccountStatusFilter);
                  setAccountPage(1);
                }}
                value={accountStatus}
              >
                <option value="all">Todos</option>
                <option value="verified">Verificados</option>
                <option value="unverified">Sin verificar</option>
              </select>
            </label>
          </div>

          <div className={styles.accountTableWrap}>
            <table className={styles.accountTable}>
              <caption>
                Cuentas con verificación actual o con un trámite previo comprobable
              </caption>
              <thead>
                <tr>
                  <th scope="col">Cuenta</th>
                  <th scope="col">Tipo</th>
                  <th scope="col">Verificación</th>
                  <th scope="col">Último cambio</th>
                  <th scope="col"><span className={styles.srOnly}>Acción</span></th>
                </tr>
              </thead>
              <tbody>
                {!accountsLoading && accountsData.accounts.length === 0 && (
                  <tr>
                    <td className={styles.emptyAccounts} colSpan={5}>
                      No hay cuentas que coincidan con estos filtros.
                    </td>
                  </tr>
                )}
                {accountsData.accounts.map(account => {
                  const canChange = account.verified
                    ? account.canUnverify
                    : account.canVerify;
                  return (
                    <tr key={account.id}>
                      <td>
                        <strong>{account.name}</strong>
                        <span>{account.email ?? 'Sin correo visible'}</span>
                        <code>{account.id}</code>
                      </td>
                      <td>
                        <span className={`${styles.rolePill} ${styles[account.role]}`}>
                          {accountRoleLabel[account.role]}
                        </span>
                      </td>
                      <td>
                        <span className={
                          account.verified ? styles.verifiedState : styles.unverifiedState
                        }>
                          <span aria-hidden="true">
                            {account.verified ? '✓' : '—'}
                          </span>
                          {account.verified ? 'Verificada' : 'Sin verificar'}
                        </span>
                        {account.verifiedAt && (
                          <small>{formatDate(account.verifiedAt)}</small>
                        )}
                      </td>
                      <td>
                        {account.lastChange ? (
                          <>
                            <span>
                              {account.lastChange.action === 'verified'
                                ? 'Palomita activada'
                                : 'Palomita retirada'}
                            </span>
                            <small>
                              {formatDate(account.lastChange.decidedAt)}
                              {' · '}
                              {account.lastChange.actor}
                            </small>
                          </>
                        ) : (
                          <span className={styles.mutedCell}>Sin ajuste manual</span>
                        )}
                      </td>
                      <td className={styles.accountAction}>
                        <button
                          className={styles.viewAccount}
                          disabled={detailLoading !== null}
                          onClick={() => openAccountDetail(account)}
                          type="button"
                        >
                          {detailLoading === account.id ? 'Cargando…' : 'Ver datos'}
                        </button>
                        <button
                          className={account.verified
                            ? styles.removeVerification
                            : styles.addVerification}
                          disabled={working !== null || !canChange}
                          onClick={() => beginAccountChange(account, !account.verified)}
                          title={!canChange
                            ? account.verificationBlockedReason ?? 'Cambio no disponible'
                            : undefined}
                          type="button"
                        >
                          {account.verified ? 'Retirar' : 'Poner palomita'}
                        </button>
                        {!canChange && account.verificationBlockedReason && (
                          <small>{account.verificationBlockedReason}</small>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            {accountsLoading && (
              <p className={styles.tableLoading}>Actualizando padrón…</p>
            )}
          </div>

          <div className={styles.accountPagination}>
            <span>
              {accountsData.pagination.total} resultado(s) · Página{' '}
              {accountsData.pagination.page} de {accountsData.pagination.totalPages}
            </span>
            <div>
              <button
                disabled={accountsLoading || accountPage <= 1}
                onClick={() => setAccountPage(current => Math.max(1, current - 1))}
                type="button"
              >
                Anterior
              </button>
              <button
                disabled={
                  accountsLoading
                  || accountPage >= accountsData.pagination.totalPages
                }
                onClick={() => setAccountPage(current => current + 1)}
                type="button"
              >
                Siguiente
              </button>
            </div>
          </div>
        </div>
      )}

      {view === 'history' && (
        <div className={styles.list} role="tabpanel">
          {history.length > 0 && (
            <div className={styles.historySearch}>
              <label htmlFor="history-search">Buscar en el historial</label>
              <div>
                <input
                  id="history-search"
                  onChange={event => setHistoryQuery(event.target.value)}
                  placeholder="Negocio, responsable o ID de cuenta"
                  type="search"
                  value={historyQuery}
                />
                <span>{filteredHistory.length} resultado(s)</span>
              </div>
            </div>
          )}
          {history.length === 0 && (
            <p className={styles.state}>Todavía no hay decisiones registradas.</p>
          )}
          {history.length > 0 && filteredHistory.length === 0 && (
            <p className={styles.state}>No encontramos una cuenta con esa búsqueda.</p>
          )}
          {filteredHistory.map(entry => {
            const expanded = expandedHistory === entry.id;
            const currentState = entry.currentVerified
              ? 'Verificación activa'
              : entry.canRestore
                ? 'Sin verificación · disponible para reactivar'
                : 'Sin verificación';

            return (
              <article className={`${styles.card} ${styles.historyCard}`} key={entry.id}>
                <div className={styles.business}>
                  <div>
                    <p className={styles.eyebrow}>{entry.business.category ?? 'Negocio'}</p>
                    <h2>{entry.business.name}</h2>
                  </div>
                  <span className={`${styles.decision} ${styles[entry.action]}`}>
                    {actionLabel[entry.action]}
                  </span>
                </div>

                <dl className={styles.historyDetails}>
                  <div>
                    <dt>Fecha</dt>
                    <dd><time dateTime={entry.decidedAt}>{formatDate(entry.decidedAt)}</time></dd>
                  </div>
                  <div>
                    <dt>Responsable</dt>
                    <dd>{entry.business.responsibleName ?? '—'}</dd>
                  </div>
                  <div>
                    <dt>ID de cuenta</dt>
                    <dd><code>{entry.userId}</code></dd>
                  </div>
                  <div>
                    <dt>Estado actual</dt>
                    <dd>{currentState}</dd>
                  </div>
                </dl>

                {entry.reason ? (
                  <div className={styles.reason}>
                    <strong>Motivo</strong>
                    <p>{entry.reason}</p>
                  </div>
                ) : (
                  <p className={styles.noReason}>Decisión registrada sin observaciones.</p>
                )}

                <div className={styles.historyToolbar}>
                  <button
                    aria-expanded={expanded}
                    className={styles.moreButton}
                    disabled={!entry.request}
                    onClick={() => setExpandedHistory(expanded ? null : entry.id)}
                    type="button"
                  >
                    {entry.request ? (expanded ? 'Ocultar detalles' : 'Ver más') : 'Sin expediente'}
                  </button>

                  {entry.canRevoke && revoking !== entry.id && (
                    <button
                      className={styles.revoke}
                      disabled={working !== null}
                      onClick={() => {
                        setRestoring(null);
                        setRevoking(entry.id);
                        setRevokeReason('');
                      }}
                      type="button"
                    >
                      Retirar verificación
                    </button>
                  )}

                  {entry.canRestore && restoring !== entry.id && (
                    <button
                      className={styles.restore}
                      disabled={working !== null}
                      onClick={() => {
                        setRevoking(null);
                        setRestoring(entry.id);
                      }}
                      type="button"
                    >
                      Volver a verificar
                    </button>
                  )}
                </div>

                {expanded && entry.request && (
                  <VerificationDossier request={entry.request} onPreview={setPreview} />
                )}

                {entry.canRevoke && revoking === entry.id && (
                  <div className={`${styles.decisionBox} ${styles.revokeBox}`}>
                    <label htmlFor={`revoke-${entry.id}`}>
                      Motivo para retirar la verificación
                    </label>
                    <textarea
                      id={`revoke-${entry.id}`}
                      maxLength={500}
                      onChange={event => setRevokeReason(event.target.value)}
                      placeholder="Explica por qué esta cuenta ya no debe estar verificada."
                      value={revokeReason}
                    />
                    <p>La cuenta perderá su insignia, pero el expediente seguirá en el historial.</p>
                    <div className={styles.actions}>
                      <button
                        onClick={() => {
                          setRevoking(null);
                          setRevokeReason('');
                        }}
                        type="button"
                      >
                        Cancelar
                      </button>
                      <button
                        className={styles.revoke}
                        disabled={working === `revoke:${entry.userId}`}
                        onClick={() => decide(entry.userId, 'revoke', revokeReason)}
                        type="button"
                      >
                        Confirmar retiro
                      </button>
                    </div>
                  </div>
                )}

                {entry.canRestore && restoring === entry.id && (
                  <div className={`${styles.decisionBox} ${styles.restoreBox}`}>
                    <strong>¿Volver a verificar esta cuenta?</strong>
                    <p>La insignia se activará de inmediato y la reactivación quedará auditada.</p>
                    <div className={styles.actions}>
                      <button onClick={() => setRestoring(null)} type="button">
                        Cancelar
                      </button>
                      <button
                        className={styles.restore}
                        disabled={working === `restore:${entry.userId}`}
                        onClick={() => decide(entry.userId, 'restore')}
                        type="button"
                      >
                        Confirmar reactivación
                      </button>
                    </div>
                  </div>
                )}
              </article>
            );
          })}
        </div>
      )}

      {accountDetail && (
        <div aria-label="Datos completos de la cuenta" aria-modal="true" className={styles.modal} onClick={() => setAccountDetail(null)} role="dialog">
          <article className={styles.accountDetail} onClick={event => event.stopPropagation()}>
            <button aria-label="Cerrar" className={styles.close} onClick={() => setAccountDetail(null)} type="button">×</button>
            <p className={styles.eyebrow}>Expediente de cuenta</p>
            <h2>{String(accountDetail.account.name ?? accountDetail.account.id)}</h2>
            <p className={styles.detailSafety}>Se muestran todos los datos administrativos consultables. Credenciales, codigos y tokens secretos no se exponen.</p>
            <DetailSection data={accountDetail.account} title="Perfil y negocio" />
            <DetailSection data={accountDetail.verification} title="Verificacion" />
            <DetailSection data={accountDetail.activity} title="Actividad registrada" />
            <DetailSection data={accountDetail.badges.length ? { badges: accountDetail.badges } : null} title="Insignias permanentes" />
            <DetailSection data={accountDetail.adminHistory.length ? { changes: accountDetail.adminHistory } : null} title="Cambios administrativos" />
            <DetailSection data={accountDetail.verificationHistory.length ? { decisions: accountDetail.verificationHistory } : null} title="Historial de verificacion" />
            <section className={styles.detailSection}>
              <h3>Documentos y evidencias</h3>
              {accountDetail.documents.length ? (
                <div className={styles.documents}>{accountDetail.documents.map(document => (
                  <button className={styles.document} key={document.id} onClick={() => setPreview(document)} type="button">
                    {isImage(document) ? <img alt={documentLabel[document.type] ?? 'Documento'} src={document.url} /> : <span className={styles.pdf}>PDF</span>}
                    <span>{documentLabel[document.type] ?? document.type}</span>
                  </button>
                ))}</div>
              ) : <p>Sin documentos registrados.</p>}
            </section>
          </article>
        </div>
      )}

      {accountChange && (
        <div
          aria-label="Confirmar cambio de verificación"
          aria-modal="true"
          className={styles.modal}
          onClick={() => {
            if (!working) setAccountChange(null);
          }}
          role="dialog"
        >
          <form
            className={styles.accountConfirmation}
            onClick={event => event.stopPropagation()}
            onSubmit={event => {
              event.preventDefault();
              saveAccountVerification();
            }}
          >
            <p className={styles.eyebrow}>Acción administrativa protegida</p>
            <h2>
              {accountChange.targetVerified
                ? 'Poner palomita azul'
                : 'Retirar palomita azul'}
            </h2>
            <div className={styles.confirmAccount}>
              <strong>{accountChange.account.name}</strong>
              <span>
                {accountRoleLabel[accountChange.account.role]}
                {' · '}
                {accountChange.account.email ?? accountChange.account.id}
              </span>
            </div>
            <p className={styles.confirmWarning}>
              {accountChange.targetVerified
                ? 'La cuenta aparecerá públicamente como verificada de inmediato.'
                : 'La cuenta perderá la insignia en todos sus perfiles y publicaciones.'}
            </p>
            <label className={styles.confirmReason}>
              <span>Motivo obligatorio</span>
              <textarea
                autoFocus
                maxLength={500}
                minLength={10}
                onChange={event => setAccountReason(event.target.value)}
                placeholder={
                  accountChange.targetVerified
                    ? 'Explica por qué corresponde reactivar la verificación.'
                    : 'Explica por qué debe retirarse la verificación.'
                }
                required
                value={accountReason}
              />
              <small>{accountReason.trim().length}/500 · mínimo 10</small>
            </label>
            <label className={styles.confirmCheck}>
              <input
                checked={accountConfirmed}
                onChange={event => setAccountConfirmed(event.target.checked)}
                type="checkbox"
              />
              <span>
                Confirmo que revisé la cuenta correcta y entiendo el cambio.
              </span>
            </label>
            <div className={styles.actions}>
              <button
                disabled={working !== null}
                onClick={() => setAccountChange(null)}
                type="button"
              >
                Cancelar
              </button>
              <button
                className={accountChange.targetVerified
                  ? styles.addVerification
                  : styles.removeVerification}
                disabled={
                  working !== null
                  || accountReason.trim().length < 10
                  || !accountConfirmed
                }
                type="submit"
              >
                {working
                  ? 'Guardando…'
                  : accountChange.targetVerified
                    ? 'Confirmar palomita'
                    : 'Confirmar retiro'}
              </button>
            </div>
          </form>
        </div>
      )}

      {preview && (
        <div
          aria-label="Vista de documento"
          aria-modal="true"
          className={styles.modal}
          onClick={() => setPreview(null)}
          role="dialog"
        >
          <div className={styles.preview} onClick={event => event.stopPropagation()}>
            <button
              aria-label="Cerrar"
              className={styles.close}
              onClick={() => setPreview(null)}
              type="button"
            >
              ×
            </button>
            {isImage(preview)
              ? <img alt={documentLabel[preview.type] ?? 'Documento'} src={preview.url} />
              : <a href={preview.url} rel="noreferrer" target="_blank">Abrir PDF en otra pestaña</a>}
          </div>
        </div>
      )}
    </section>
  );
}
