'use strict';

// Avisos push (FCM) de Ohtli: texto de cada notificación y envío a los dispositivos de una persona.
// Los tokens viven en users/{uid}/push_tokens/{token} (los escribe lib/services/push_service.dart).
// Los mensajes son solo de datos: ohtli_sw.js arma la notificación (título, cuerpo, ícono y url).

const TAPBACKS = { heart: '❤️', haha: '😂', surprise: '😮', hundred: '💯', fire: '🔥', photo: '📸' };

// Errores con los que FCM dice que el token ya no sirve (se borra).
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

function clip(text, max) {
  const s = String(text || '').replace(/\s+/g, ' ').trim();
  return s.length > max ? `${s.slice(0, max - 1).trimEnd()}…` : s;
}

function str(v) {
  return typeof v === 'string' && v.trim() ? v.trim() : null;
}

/**
 * Versión compacta de describeNotification (lib/services/notification_text.dart): título y
 * cuerpo del aviso del sistema. Los tipos que no conoce usan un texto genérico.
 */
function describePush(data) {
  const d = data || {};
  const type = str(d.type) || 'friend_request';
  const sender = clip(str(d.senderName) || 'Viajero Ohtli', 60);
  const trip = clip(str(d.tripTitle) || 'su itinerario', 80);
  const kind = d.isPlan === true ? 'plan' : 'viaje';
  const message = str(d.message);

  switch (type) {
    case 'friend_request':
      if (d.status === 'accepted') return { title: 'Nueva amistad', body: `${sender} y tú ahora son amigos.` };
      return { title: 'Solicitud de amistad', body: `${sender} te envió una solicitud de amistad.` };
    case 'new_publication':
      return { title: d.isPlan === true ? 'Nuevo plan' : 'Nuevo viaje', body: `${sender} publicó un nuevo ${kind}: "${trip}".` };
    case 'surprise_plan':
      return { title: 'Tienes un plan sorpresa 🎁', body: `${sender} te preparó un plan sorpresa: "${trip}".` };
    case 'co_author_added':
      return { title: 'Ahora eres coautor', body: `${sender} te agregó como coautor en su ${kind}: "${trip}".` };
    case 'trip_comment': {
      const comment = clip(d.commentText, 120);
      return { title: `Comentario en "${trip}"`, body: comment ? `${sender}: «${comment}»` : `${sender} comentó en tu viaje.` };
    }
    case 'trip_reaction': {
      const emoji = TAPBACKS[d.reaction] || '❤️';
      return {
        title: 'Nueva reacción',
        body: d.onComment === true ? `${sender} reaccionó ${emoji} a tu mensaje en "${trip}".` : `${sender} reaccionó ${emoji} a tu viaje "${trip}".`,
      };
    }
    case 'cheer':
      return d.tripId
        ? { title: '¡Felicidades! 🎉', body: `${sender} te felicitó por tu viaje "${trip}".` }
        : { title: 'Te saludaron 👋', body: `${sender} te saludó.` };
    case 'itinerary_ready':
      return { title: str(d.title) || 'Tus rutas con IA están listas', body: message || 'Tus rutas con IA están listas para elegir.' };
    case 'itinerary_failed':
      return { title: 'No pudimos terminar tus rutas', body: message || 'No pudimos terminar tus rutas con IA. Intenta de nuevo.' };
    case 'group_trip_invite':
      return { title: 'Viaje en grupo', body: `${sender} te invitó a planear juntos "${trip}".` };
    case 'group_trip_accepted':
      return { title: 'Se sumó a tu plan', body: `${sender} se sumó a tu plan "${trip}".` };
    case 'group_trip_declined':
      return { title: 'No podrá ir', body: `${sender} no podrá ir a "${trip}".` };
    case 'group_trip_ready':
      return { title: 'Ya pueden votar', body: message || `Las rutas de "${trip}" están listas: vota por tu favorita.` };
    case 'group_trip_created':
      return { title: 'Su plan quedó listo', body: message || `El plan "${trip}" quedó listo: ya pueden editarlo juntos.` };
    case 'group_trip_cancelled':
      return { title: 'Plan cancelado', body: message || `Se canceló el plan "${trip}": nadie aceptó a tiempo.` };
    default:
      return { title: str(d.title) || 'Ohtli', body: message || `${sender} tiene algo para ti.` };
  }
}

/** A dónde lleva el aviso al tocarlo (mismo criterio que OhtliLiveAlerts._open). */
function urlForNotification(uid, data) {
  const d = data || {};
  const type = str(d.type) || '';
  if (type === 'itinerary_ready' || type === 'itinerary_failed') return '/mis-viajes';
  // Los planes en grupo se responden desde Notificaciones.
  if (type.startsWith('group_trip_')) return '/notificaciones';
  const tripId = str(d.tripId);
  if (tripId) {
    const owner = str(d.tripOwnerId) || ((type === 'new_publication' || type === 'surprise_plan') ? str(d.senderId) : null) || uid;
    return `/?tripId=${encodeURIComponent(tripId)}&authorId=${encodeURIComponent(owner)}`;
  }
  return '/notificaciones';
}

/** Datos del mensaje push (FCM solo acepta textos). */
function pushPayload({ title, body, url, tag, kind }) {
  return {
    title: clip(title, 90),
    body: clip(body, 240),
    url: url || '/',
    tag: tag || '',
    kind: kind || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-maskable-192.png',
  };
}

/**
 * Manda [payload] a todos los dispositivos de [uid] y borra los tokens que FCM ya no reconoce.
 * Respeta el interruptor «Recibir notificaciones» de Cuenta (privacy_notifications).
 */
async function sendToUser(db, messaging, uid, payload, { ttlSeconds = 86400 } = {}) {
  const tokensRef = db.collection('users').doc(uid).collection('push_tokens');
  const snap = await tokensRef.get();
  if (snap.empty) return { sent: 0, failed: 0, pruned: 0, skipped: 'sin tokens' };

  const priv = await db.collection('users').doc(uid).collection('private').doc('account').get();
  if (priv.exists && priv.get('privacy_notifications') === false) {
    return { sent: 0, failed: 0, pruned: 0, skipped: 'notificaciones apagadas' };
  }

  const tokens = snap.docs.map((d) => d.id);
  const res = await messaging.sendEachForMulticast({
    tokens,
    data: payload,
    webpush: { headers: { Urgency: 'high', TTL: String(ttlSeconds) } },
  });
  const dead = [];
  res.responses.forEach((r, i) => {
    if (r.success) return;
    const code = r.error && r.error.code;
    if (DEAD_TOKEN_CODES.has(code)) dead.push(tokens[i]);
    else console.warn('[push] envío fallido', uid, code, r.error && r.error.message);
  });
  await Promise.all(dead.map((t) => tokensRef.doc(t).delete().catch(() => {})));
  return { sent: res.successCount, failed: res.failureCount, pruned: dead.length };
}

module.exports = { describePush, urlForNotification, pushPayload, sendToUser, DEAD_TOKEN_CODES };
