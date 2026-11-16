'use strict';

// ---------------------------------------------------------------------------
// "Enviar comentarios": la app guarda cada comentario en app_feedback/{id}
// (lib/services/feedback_service.dart) y aquí se convierte en un correo para el equipo.
//
// El correo no se manda desde este código: se escribe un documento en la colección que
// procesa la extensión oficial "Trigger Email from Firestore" (firebase/firestore-send-email),
// que tiene la conexión SMTP guardada en Secret Manager. Así no hay contraseñas en el repo.
//
// Llega al correo de privacidad de Ohtli (DEFAULT_TO). Debe ser el mismo que
// LegalInfo.privacyEmail en lib/screens/legal/legal_content.dart: functions/ no puede importar
// Dart, así que test/feedback.test.js compara los dos y falla si se separan.
// Para cambiarlo sin desplegar, private_config/feedback (Firestore, sin acceso desde la app):
//   { to: "correo@dominio"  |  ["uno@…", "otro@…"],  mailCollection?: "mail" }
// El destinatario nunca viene de la app: así nadie puede usar esto para mandar correos a otros.
// ---------------------------------------------------------------------------

const DEFAULT_TO = 'privacidad@ohtli.quest';

const CATEGORY_LABELS = { idea: 'Idea', bug: 'Algo falla', other: 'Otro' };

// Correos por persona y hora: más allá de esto el comentario se guarda pero no se manda.
const RATE_LIMIT = 10;
const RATE_WINDOW_MS = 60 * 60 * 1000;

function escapeHtml(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function oneLine(s, max) {
  const t = String(s == null ? '' : s).replace(/\s+/g, ' ').trim();
  return t.length > max ? `${t.slice(0, max - 1)}…` : t;
}

/** Destinatarios válidos de private_config/feedback.to (texto o lista). */
function recipientsOf(config) {
  const raw = config && config.to;
  const list = Array.isArray(raw) ? raw : (typeof raw === 'string' ? raw.split(',') : []);
  return list.map((e) => String(e).trim()).filter((e) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e));
}

/** Correo (asunto, texto y HTML) para un comentario. */
function buildFeedbackMail(data, { id, createdAt } = {}) {
  const d = data || {};
  const category = CATEGORY_LABELS[d.category] || CATEGORY_LABELS.other;
  const message = String(d.message || '').trim();
  const screen = String(d.screen || '—');
  const subject = `[Ohtli · ${category}] ${oneLine(message, 70) || 'Comentario'}`;

  const rows = [
    ['Tipo', category],
    ['Pantalla', screen],
    ['Cuenta (uid)', d.uid || '—'],
    ['Versión', d.appVersion || '—'],
    ['Navegador', d.browser || '—'],
    ['Ventana', d.viewport || '—'],
    ['Idioma', d.language || '—'],
  ];
  const ctx = d.context && typeof d.context === 'object' ? d.context : {};
  for (const [k, v] of Object.entries(ctx)) rows.push([k, String(v)]);
  if (createdAt) rows.push(['Fecha', createdAt]);
  if (id) rows.push(['Id', id]);

  const text = `${message}\n\n${rows.map(([k, v]) => `${k}: ${v}`).join('\n')}\n`;
  const html =
    `<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#222">` +
    `<p style="white-space:pre-wrap;font-size:15px;line-height:1.5">${escapeHtml(message)}</p>` +
    `<table style="border-collapse:collapse;margin-top:16px;font-size:13px;color:#555">` +
    rows
      .map(([k, v]) => `<tr><td style="padding:2px 12px 2px 0;font-weight:bold">${escapeHtml(k)}</td><td style="padding:2px 0">${escapeHtml(v)}</td></tr>`)
      .join('') +
    `</table></div>`;
  return { subject, text, html };
}

/** Siguiente estado del límite por persona. `allowed` dice si este comentario se manda. */
function nextRate(prev, nowMs) {
  const start = prev && typeof prev.windowStart === 'number' ? prev.windowStart : 0;
  const count = prev && typeof prev.count === 'number' ? prev.count : 0;
  if (nowMs - start >= RATE_WINDOW_MS) return { allowed: true, state: { windowStart: nowMs, count: 1 } };
  if (count >= RATE_LIMIT) return { allowed: false, state: { windowStart: start, count } };
  return { allowed: true, state: { windowStart: start, count: count + 1 } };
}

/** Procesa app_feedback/{id} recién creado. Devuelve qué pasó (para el log). */
async function handleFeedback(db, snap, id, nowMs = Date.now()) {
  const data = (snap && snap.data && snap.data()) || {};
  const uid = typeof data.uid === 'string' ? data.uid : '';
  if (!uid || !String(data.message || '').trim()) return 'vacío';

  const configSnap = await db.collection('private_config').doc('feedback').get();
  const config = configSnap.exists ? configSnap.data() : null;
  const configured = recipientsOf(config);
  const to = configured.length > 0 ? configured : [DEFAULT_TO];

  const rateRef = db.collection('feedback_rate').doc(uid);
  const allowed = await db.runTransaction(async (tx) => {
    const cur = await tx.get(rateRef);
    const r = nextRate(cur.exists ? cur.data() : null, nowMs);
    tx.set(rateRef, r.state);
    return r.allowed;
  });
  if (!allowed) return 'límite por hora alcanzado';

  const ts = data.createdAt && typeof data.createdAt.toDate === 'function' ? data.createdAt.toDate() : new Date(nowMs);
  const mail = buildFeedbackMail(data, {
    id,
    createdAt: ts.toLocaleString('es-MX', { timeZone: 'America/Mexico_City' }),
  });
  const collection = (config && typeof config.mailCollection === 'string' && config.mailCollection) || 'mail';
  // Mismo id que el comentario: si la función se reintenta no sale un correo repetido.
  await db.collection(collection).doc(`feedback_${id}`).set({ to, message: mail });
  return 'correo en cola';
}

module.exports = { DEFAULT_TO, buildFeedbackMail, recipientsOf, nextRate, handleFeedback, escapeHtml, RATE_LIMIT, RATE_WINDOW_MS };
