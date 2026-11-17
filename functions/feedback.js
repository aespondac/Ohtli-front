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

// Mi cuenta → Administración → Comentarios de la app
const ADMIN_URL = 'https://ohtli.quest/cuenta';

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

const SECTION_LABELS = {
  user: { nombre: 'Nombre', correo: 'Correo', correoVerificado: 'Verificado', acceso: 'Acceso', cuentaDesde: 'Cuenta desde', uid: 'uid' },
  device: {
    navegador: 'Navegador', pantalla: 'Pantalla', ventana: 'Ventana', densidad: 'Densidad', tactil: 'Táctil',
    idioma: 'Idioma', zonaHoraria: 'Zona horaria', nucleos: 'Núcleos', memoria: 'Memoria', conexion: 'Conexión',
    red: 'Red', instalada: 'Instalada', userAgent: 'User agent',
  },
  system: { version: 'Versión', modo: 'Compilación', renderer: 'Motor', ruta: 'Ruta', tema: 'Tema', letra: 'Letra', abiertaHace: 'Abierta hace', errores: 'Errores' },
};

function mapRows(obj, labels = {}) {
  const m = obj && typeof obj === 'object' ? obj : {};
  const keys = [...Object.keys(labels).filter((k) => k in m), ...Object.keys(m).filter((k) => !(k in labels))];
  return keys.map((k) => [labels[k] || k, String(m[k])]);
}

function htmlTable(rows) {
  return (
    `<table style="border-collapse:collapse;font-size:13px;color:#555">` +
    rows
      .map(([k, v]) => `<tr><td style="padding:2px 12px 2px 0;font-weight:bold;vertical-align:top;white-space:nowrap">${escapeHtml(k)}</td><td style="padding:2px 0">${escapeHtml(v)}</td></tr>`)
      .join('') +
    `</table>`
  );
}

/**
 * Correo (asunto, texto y HTML) para un comentario. [images]: URLs de las capturas (con token),
 * que se muestran en el correo y enlazan a la imagen completa.
 */
function buildFeedbackMail(data, { id, createdAt, images = [], adminUrl } = {}) {
  const d = data || {};
  const category = CATEGORY_LABELS[d.category] || CATEGORY_LABELS.other;
  const message = String(d.message || '').trim();
  const screen = String(d.screen || '—');
  const user = d.user && typeof d.user === 'object' ? d.user : {};
  const who = user.nombre || user.correo || '';
  const subject = `[Ohtli · ${category}] ${oneLine(message, 70) || 'Comentario'}`;

  const summary = [
    ['Tipo', category],
    ['De', who ? `${who}${user.correo && user.correo !== who ? ` <${user.correo}>` : ''}` : (d.uid || '—')],
    ['Pantalla', screen],
    ['Versión', d.appVersion || '—'],
  ];
  const ctx = d.context && typeof d.context === 'object' ? d.context : {};
  for (const [k, v] of Object.entries(ctx)) summary.push([k, String(v)]);
  if (createdAt) summary.push(['Fecha', createdAt]);
  if (id) summary.push(['Id', id]);

  const device = mapRows(
    d.device && Object.keys(d.device).length ? d.device : { navegador: d.browser, ventana: d.viewport, idioma: d.language },
    SECTION_LABELS.device,
  ).filter(([, v]) => v && v !== 'undefined');
  const sections = [
    ['Cuenta', mapRows({ ...user, uid: d.uid || user.uid }, SECTION_LABELS.user)],
    ['Dispositivo', device],
    ['Estado de Ohtli', mapRows(d.system, SECTION_LABELS.system)],
  ].filter(([, rows]) => rows.length > 0);
  const errors = Array.isArray(d.errors) ? d.errors : [];

  const text =
    `${message}\n\n${summary.map(([k, v]) => `${k}: ${v}`).join('\n')}\n` +
    sections.map(([t, rows]) => `\n${t}\n${rows.map(([k, v]) => `  ${k}: ${v}`).join('\n')}`).join('\n') +
    (errors.length ? `\n\nErrores recientes\n${errors.map((e) => `  ${e.at || ''} ${e.where || ''}: ${e.message || ''}`).join('\n')}` : '') +
    (images.length ? `\n\nCapturas\n${images.map((u) => `  ${u}`).join('\n')}` : '') +
    (adminUrl ? `\n\nRevísalo en ${adminUrl}` : '') +
    '\n';

  const h = (t) => `<h3 style="font-size:12px;letter-spacing:1px;text-transform:uppercase;color:#888;margin:22px 0 6px">${escapeHtml(t)}</h3>`;
  const html =
    `<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#222;max-width:680px">` +
    `<p style="white-space:pre-wrap;font-size:15px;line-height:1.5">${escapeHtml(message)}</p>` +
    htmlTable(summary) +
    (images.length
      ? h(`Capturas · ${images.length}`) +
        images
          .map((u) => `<a href="${escapeHtml(u)}"><img src="${escapeHtml(u)}" alt="Captura" style="max-width:300px;max-height:420px;border:1px solid #ddd;border-radius:8px;margin:0 8px 8px 0"></a>`)
          .join('')
      : '') +
    sections.map(([t, rows]) => h(t) + htmlTable(rows)).join('') +
    (errors.length
      ? h(`Errores recientes · ${errors.length}`) +
        `<pre style="font-size:12px;background:#fdf3ec;padding:10px;border-radius:8px;white-space:pre-wrap">${escapeHtml(
          errors.map((e) => `${e.at || ''} ${e.where || ''}\n${e.message || ''}`).join('\n\n'),
        )}</pre>`
      : '') +
    (adminUrl ? `<p style="margin-top:22px"><a href="${escapeHtml(adminUrl)}">Revisarlo en el panel de Ohtli</a></p>` : '') +
    `</div>`;
  return { subject, text, html };
}

/**
 * URL de descarga (con el token de Firebase) de cada captura, para verla desde el correo.
 * Las que no tengan token o no existan se omiten.
 */
async function imageUrls(bucket, paths) {
  if (!bucket || !Array.isArray(paths)) return [];
  const out = [];
  for (const p of paths.slice(0, 3)) {
    if (typeof p !== 'string' || !p.startsWith('app_feedback/')) continue;
    try {
      const [meta] = await bucket.file(p).getMetadata();
      const token = String((meta && meta.metadata && meta.metadata.firebaseStorageDownloadTokens) || '').split(',')[0];
      if (!token) continue;
      out.push(`https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(p)}?alt=media&token=${token}`);
    } catch (e) {
      console.warn('[feedback] sin URL para', p, e.message);
    }
  }
  return out;
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
async function handleFeedback(db, snap, id, nowMs = Date.now(), bucket = null) {
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
    images: await imageUrls(bucket, data.screenshots),
    adminUrl: ADMIN_URL,
  });
  const collection = (config && typeof config.mailCollection === 'string' && config.mailCollection) || 'mail';
  // Mismo id que el comentario: si la función se reintenta no sale un correo repetido.
  await db.collection(collection).doc(`feedback_${id}`).set({ to, message: mail });
  return 'correo en cola';
}

module.exports = { DEFAULT_TO, buildFeedbackMail, imageUrls, recipientsOf, nextRate, handleFeedback, escapeHtml, RATE_LIMIT, RATE_WINDOW_MS };
