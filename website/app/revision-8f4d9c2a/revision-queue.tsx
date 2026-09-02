'use client';

import { useEffect, useState } from 'react';

import styles from './revision.module.css';

/**
 * Contrato esperado del backend del marketplace (otro dominio):
 *
 * GET  {API}/api/revision/verificaciones?status=pending
 *   -> { requests: [{ id, business: { name, category, responsibleName,
 *        description, phone }, documents: [{ id, type, url, mimeType }] }] }
 * POST {API}/api/revision/verificaciones/:id/approve -> { status: 'approved' }
 * POST {API}/api/revision/verificaciones/:id/reject  body: { reason: string }
 *   -> { status: 'rejected' }
 *
 * El backend debe permitir el origen de este sitio por CORS y autenticar esos
 * endpoints del lado del servidor. CORS no sustituye autenticación.
 */
const apiBase = '/revision-8f4d9c2a/api';

type Document = { id: string; type: string; url: string; mimeType?: string };
type Request = {
  id: string;
  business: {
    name: string;
    category?: string;
    responsibleName?: string;
    description?: string;
    phone?: string;
  };
  documents: Document[];
};

const documentLabel: Record<string, string> = {
  facade: 'Fachada',
  menu: 'Menú',
  responsible_ine_front: 'INE · frente',
  responsible_ine_back: 'INE · reverso',
  additional_evidence: 'Evidencia adicional',
};

function isImage(document: Document) {
  return document.mimeType?.startsWith('image/') || /\.(avif|gif|jpe?g|png|webp)$/i.test(document.url);
}

export default function RevisionQueue() {
  const [requests, setRequests] = useState<Request[]>([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [rejecting, setRejecting] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const [working, setWorking] = useState<string | null>(null);
  const [preview, setPreview] = useState<Document | null>(null);

  useEffect(() => {
    fetch(apiBase)
      .then(async response => {
        if (!response.ok) throw new Error('No se pudieron cargar las solicitudes.');
        return response.json() as Promise<{ requests: Request[] }>;
      })
      .then(data => setRequests(data.requests ?? []))
      .catch(error => setMessage(error instanceof Error ? error.message : 'Ocurrió un error.'))
      .finally(() => setLoading(false));
  }, []);

  async function decide(id: string, action: 'approve' | 'reject') {
    if (action === 'reject' && !reason.trim()) {
      setMessage('Escribe un motivo antes de rechazar la solicitud.');
      return;
    }
    setWorking(id);
    setMessage('');
    try {
      const response = await fetch(`${apiBase}?id=${encodeURIComponent(id)}&action=${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: action === 'reject' ? JSON.stringify({ reason: reason.trim() }) : undefined,
      });
      if (!response.ok) throw new Error('No se pudo guardar la decisión.');
      setRequests(current => current.filter(request => request.id !== id));
      setRejecting(null);
      setReason('');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Ocurrió un error.');
    } finally {
      setWorking(null);
    }
  }

  if (loading) return <p className={styles.state}>Cargando solicitudes…</p>;

  return (
    <section className={styles.queue} aria-live="polite">
      {message && <p className={styles.error}>{message}</p>}
      {!message && requests.length === 0 && <p className={styles.state}>No hay solicitudes pendientes.</p>}
      {requests.map(request => (
        <article className={styles.card} key={request.id}>
          <div className={styles.business}>
            <div>
              <p className={styles.eyebrow}>{request.business.category ?? 'Negocio'}</p>
              <h2>{request.business.name}</h2>
            </div>
            <span className={styles.pending}>Pendiente</span>
          </div>
          <dl className={styles.details}>
            <div><dt>Responsable</dt><dd>{request.business.responsibleName ?? '—'}</dd></div>
            <div><dt>Teléfono</dt><dd>{request.business.phone ?? '—'}</dd></div>
            {request.business.description && <div className={styles.description}><dt>Descripción</dt><dd>{request.business.description}</dd></div>}
          </dl>
          <div className={styles.documents}>
            {request.documents.map(document => (
              <button className={styles.document} key={document.id} onClick={() => setPreview(document)} type="button">
                {isImage(document) ? <img alt={documentLabel[document.type] ?? 'Documento'} src={document.url} /> : <span className={styles.pdf}>PDF</span>}
                <span>{documentLabel[document.type] ?? document.type}</span>
              </button>
            ))}
          </div>
          {rejecting === request.id ? (
            <div className={styles.rejectBox}>
              <label htmlFor={`reason-${request.id}`}>Motivo del rechazo</label>
              <textarea id={`reason-${request.id}`} value={reason} onChange={event => setReason(event.target.value)} placeholder="Indica qué debe corregirse." />
              <div className={styles.actions}><button type="button" onClick={() => { setRejecting(null); setReason(''); }}>Cancelar</button><button className={styles.reject} disabled={working === request.id} onClick={() => decide(request.id, 'reject')} type="button">Confirmar rechazo</button></div>
            </div>
          ) : (
            <div className={styles.actions}><button className={styles.approve} disabled={working === request.id} onClick={() => decide(request.id, 'approve')} type="button">Aprobar</button><button className={styles.reject} disabled={working === request.id} onClick={() => setRejecting(request.id)} type="button">Rechazar</button></div>
          )}
        </article>
      ))}
      {preview && <div className={styles.modal} role="dialog" aria-modal="true" aria-label="Vista de documento" onClick={() => setPreview(null)}><div className={styles.preview} onClick={event => event.stopPropagation()}><button className={styles.close} onClick={() => setPreview(null)} type="button" aria-label="Cerrar">×</button>{isImage(preview) ? <img alt={documentLabel[preview.type] ?? 'Documento'} src={preview.url} /> : <a href={preview.url} target="_blank" rel="noreferrer">Abrir PDF en otra pestaña</a>}</div></div>}
    </section>
  );
}
