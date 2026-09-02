'use client';

import { useEffect, useState } from 'react';

import styles from './revision.module.css';
import StaticMiniMap from './static-mini-map';

const apiBase = '/revision-8f4d9c2a/api';

type Document = { id: string; type: string; url: string; mimeType?: string };
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
type HistoryAction = 'approved' | 'rejected' | 'revoked';
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
  if (!response.ok) throw new Error(payload.error || fallback);
  return payload;
}

export default function RevisionQueue() {
  const [requests, setRequests] = useState<Request[]>([]);
  const [history, setHistory] = useState<HistoryEntry[]>([]);
  const [view, setView] = useState<'pending' | 'history'>('pending');
  const [loading, setLoading] = useState(true);
  const [notice, setNotice] = useState<Notice>(null);
  const [rejecting, setRejecting] = useState<string | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  const [revoking, setRevoking] = useState<number | null>(null);
  const [revokeReason, setRevokeReason] = useState('');
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

  useEffect(() => {
    Promise.all([loadPending(), loadHistory()])
      .catch(error => setNotice({
        kind: 'error',
        text: error instanceof Error ? error.message : 'Ocurrió un error.',
      }))
      .finally(() => setLoading(false));
  }, []);

  async function decide(
    id: string,
    action: 'approve' | 'reject' | 'revoke',
    reason?: string,
  ) {
    const trimmedReason = reason?.trim() ?? '';
    if (action !== 'approve' && !trimmedReason) {
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
          headers: { 'Content-Type': 'application/json' },
          body: action === 'approve'
            ? undefined
            : JSON.stringify({ reason: trimmedReason }),
        },
      );
      await payloadOrError<ErrorPayload>(response, 'No se pudo guardar la decisión.');

      if (action !== 'revoke') {
        setRequests(current => current.filter(request => request.id !== id));
      }
      setRejecting(null);
      setRejectReason('');
      setRevoking(null);
      setRevokeReason('');

      try {
        await loadHistory();
        setNotice({
          kind: 'success',
          text: action === 'approve'
            ? 'Cuenta aceptada. La decisión quedó guardada en el historial.'
            : action === 'reject'
              ? 'Solicitud rechazada. El motivo quedó guardado en el historial.'
              : 'La verificación fue retirada y el motivo quedó registrado.',
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

      {view === 'history' && (
        <div className={styles.list} role="tabpanel">
          {history.length === 0 && (
            <p className={styles.state}>Todavía no hay decisiones registradas.</p>
          )}
          {history.map(entry => (
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
                  <dd>{entry.currentVerified ? 'Verificación activa' : 'Sin verificación'}</dd>
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

              {entry.canRevoke && revoking !== entry.id && (
                <div className={styles.actions}>
                  <button
                    className={styles.revoke}
                    disabled={working !== null}
                    onClick={() => {
                      setRevoking(entry.id);
                      setRevokeReason('');
                    }}
                    type="button"
                  >
                    Quitar verificación
                  </button>
                </div>
              )}

              {entry.canRevoke && revoking === entry.id && (
                <div className={`${styles.decisionBox} ${styles.revokeBox}`}>
                  <label htmlFor={`revoke-${entry.id}`}>Motivo para quitar la verificación</label>
                  <textarea
                    id={`revoke-${entry.id}`}
                    maxLength={500}
                    onChange={event => setRevokeReason(event.target.value)}
                    placeholder="Explica por qué esta cuenta ya no debe estar verificada."
                    value={revokeReason}
                  />
                  <p>Esta acción quitará la insignia de verificación de la cuenta.</p>
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
            </article>
          ))}
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
