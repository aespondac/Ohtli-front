const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

/**
 * Helper to strip markdown characters and formatting to yield a clean description text.
 */
function stripMarkdown(text) {
  if (!text) return '';
  return text
    .replace(/(\*\*|__)(.*?)\1/g, '$2')          // bold
    .replace(/(\*|_)(.*?)\1/g, '$2')             // italics
    .replace(/~~(.*?)~~/g, '$2')                 // strikethrough
    .replace(/`{1,3}(.*?)\`{1,3}/g, '$1')        // code blocks
    .replace(/\[(.*?)\]\((.*?)\)/g, '$1')        // markdown links
    .replace(/[#*+\-`\[\]\(\){}~]/g, '')         // remaining syntax characters
    .replace(/\s+/g, ' ')                        // collapse whitespace
    .trim();
}

exports.serveTripMeta = functions.https.onRequest(async (req, res) => {
  const pathParts = req.path.split('/').filter(Boolean); // Remove empty strings
  // Expected path format: /viajes/authorId/tripId
  // pathParts will be: ['viajes', 'authorId', 'tripId']
  
  let authorId = null;
  let tripId = null;

  if (pathParts.length >= 3 && pathParts[0] === 'viajes') {
    authorId = pathParts[1];
    tripId = pathParts[2];
  }

  // If we couldn't parse the IDs, redirect humans or return simple empty response for bots
  if (!authorId || !tripId) {
    const userAgent = req.headers['user-agent'] || '';
    const isBot = /facebookexternalhit|twitterbot|whatsapp|slackbot|telegrambot|google\-structured\-data\-testing\-tool|linkedinbot|embedly|quora link preview|rogue/i.test(userAgent);
    
    if (isBot) {
      return res.status(404).send('Not Found');
    } else {
      return res.redirect(302, `https://${req.hostname}/`);
    }
  }

  const userAgent = req.headers['user-agent'] || '';
  const isBot = /facebookexternalhit|twitterbot|whatsapp|slackbot|telegrambot|google\-structured\-data\-testing\-tool|linkedinbot|embedly|quora link preview|rogue/i.test(userAgent);

  if (isBot) {
    try {
      const db = admin.firestore();
      const tripDoc = await db.collection('users').doc(authorId).collection('trips').doc(tripId).get();

      if (tripDoc.exists) {
        const tripData = tripDoc.data();
        
        // Only show previews for published public trips
        if (tripData && tripData.status === 'published' && tripData.visibility === 'public') {
          const title = tripData.title || 'Bitácora de Viaje | Ohtli';
          const rawDescription = tripData.description || 'El viaje empieza aquí. Sigue mis pasos en Ohtli.';
          const description = stripMarkdown(rawDescription);
          const coverUrl = tripData.coverUrl || `https://${req.hostname}/assets/logo.svg`;

          // Generate dynamic HTML with meta tags
          res.status(200).send(`<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>${title}</title>
    <meta name="description" content="${description}">
    
    <!-- Open Graph / Facebook -->
    <meta property="og:type" content="website">
    <meta property="og:title" content="${title}">
    <meta property="og:description" content="${description}">
    <meta property="og:image" content="${coverUrl}">
    <meta property="og:url" content="https://${req.hostname}/viajes/${authorId}/${tripId}">
    
    <!-- Twitter -->
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="${title}">
    <meta name="twitter:description" content="${description}">
    <meta name="twitter:image" content="${coverUrl}">
  </head>
  <body>
    <h1>${title}</h1>
    <p>${description}</p>
    <img src="${coverUrl}" alt="Cover Image" />
  </body>
</html>`);
          return;
        }
      }
      
      // If trip doesn't exist or is not public, return fallback default tags
      res.status(200).send(`<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Ohtli | El viaje empieza aquí</title>
    <meta name="description" content="Diseña tu camino, explora bitácoras y comparte aventuras con tus amigos.">
    <meta property="og:title" content="Ohtli | El viaje empieza aquí">
    <meta property="og:description" content="Diseña tu camino, explora bitácoras y comparte aventuras con tus amigos.">
  </head>
  <body>
    <h1>Ohtli</h1>
  </body>
</html>`);
    } catch (error) {
      console.error('Error serving trip meta tags:', error);
      res.status(500).send('Internal Server Error');
    }
  } else {
    // Human visitor: redirect to the SPA router on root path
    res.redirect(302, `https://${req.hostname}/?tripId=${tripId}&authorId=${authorId}`);
  }
});

const INFRASTRUCTURE_NAME_REGEX = /(\b(s[oó]lo\s+entrada|only\s+entrance|s[oó]lo\s+salida|only\s+exit|no\s+exit|no\s+entry|sin\s+salida|entrada\s+y\s+salida|staff\s+only)\b|^(entrada|salida|acceso|puerta|port[oó]n|reja|barrera|torniquetes?|caseta|vigilancia|taquillas?|estacionamiento|parking|ba[ñn]os?|sanitarios?|wc|cajero|atm|m[oó]dulo\s+de\s+informaci[oó]n|informaci[oó]n|mapa|letrero|and[eé]n)(\b|\s|:|-|\/)|\b(entrada\s+principal|entrada\s+peatonal|entrada\s+vehicular|acceso\s+peatonal|acceso\s+vehicular|acceso\s+principal|puerta\s+\d+|acceso\s+\d+|entrada\s+\d+|gate\s+\d+|main\s+entrance)\b)/i;

const BLOCKED_POI_IDS = new Set(['2005860965', 'osm_2005860965']);
const GENERIC_POI_NAMES = new Set(['', 'lugar', 'lugar sin nombre', 'sin nombre', 'poi', 'unnamed', 'n/a', 'null', 'none']);

async function purgeInvalidPoisInLocalFirestore() {
  const db = admin.firestore();
  const purged = { pois: [], pois_lab: [] };
  for (const colName of ['pois', 'pois_lab']) {
    try {
      const colRef = db.collection(colName);
      for (const blockedId of ['osm_2005860965', '2005860965']) {
        const snap = await colRef.doc(blockedId).get();
        if (snap.exists) {
          await colRef.doc(blockedId).delete();
          purged[colName].push(blockedId);
        }
      }
      const allDocs = await colRef.get();
      for (const doc of allDocs.docs) {
        const data = doc.data() || {};
        const name = String(data.name || '').trim();
        const tags = data.tags || {};
        const isInvalidId = BLOCKED_POI_IDS.has(doc.id) || BLOCKED_POI_IDS.has(String(data.poi_id || '').trim());
        const isInvalidName = name.length < 3 || GENERIC_POI_NAMES.has(name.toLowerCase()) || INFRASTRUCTURE_NAME_REGEX.test(name);
        const hasEntranceOrBarrier = Boolean(tags.entrance || tags.barrier);
        if (isInvalidId || isInvalidName || hasEntranceOrBarrier) {
          await colRef.doc(doc.id).delete();
          if (!purged[colName].includes(doc.id)) {
            purged[colName].push(doc.id);
          }
        }
      }
    } catch (err) {
      console.error(`Error purging ${colName}:`, err);
    }
  }
  return purged;
}

exports.apiGateway = functions.https.onRequest(async (req, res) => {
  // Configuración de CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, PUT, DELETE');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // replicate/cleanup también purgan el Firestore local, pero solo después de que el motor
  // aceptó la petición (exige el ID token de un miembro de Ohtli Labs): una petición anónima
  // no debe poder disparar la purga.
  const purgesLocal = req.path.includes('/recolector/cleanup') || req.path.includes('/recolector/replicate');
  let localPurged = null;

  // El backend Yollotl Engine está desplegado en Cloud Run / Cloud Functions Gen2
  const targetHost = 'https://api-xluju5gywq-uc.a.run.app';
  
  // Como el rewrite en Firebase Hosting incluye /api/... y /v1/..., usamos req.url o req.path directamente
  const targetUrl = targetHost + req.url;

  try {
    const fetchResponse = await fetch(targetUrl, {
      method: req.method,
      headers: {
        'Content-Type': req.get('Content-Type') || 'application/json',
        'Accept': req.get('Accept') || '*/*',
        // El motor valida el ID token de Firebase (endpoints con sesión y de laboratorio).
        ...(req.get('Authorization') ? { 'Authorization': req.get('Authorization') } : {}),
      },
      body: req.method !== 'GET' && req.method !== 'HEAD' ? req.rawBody : undefined
    });

    const data = await fetchResponse.text();
    if (purgesLocal && fetchResponse.ok) {
      localPurged = await purgeInvalidPoisInLocalFirestore();
    }
    
    // Copy some relevant headers back
    res.set('Content-Type', fetchResponse.headers.get('Content-Type') || 'application/json');
    const cacheControl = fetchResponse.headers.get('Cache-Control');
    if (cacheControl) {
      res.set('Cache-Control', cacheControl);
    } else if (req.path.startsWith('/v1/pois') && req.method === 'GET') {
      res.set('Cache-Control', 'public, max-age=180, s-maxage=300');
    }
    if (localPurged && req.path.includes('/recolector/cleanup')) {
      try {
        const parsed = JSON.parse(data);
        parsed.local_firestore_purged = localPurged;
        res.status(fetchResponse.status).send(JSON.stringify(parsed));
        return;
      } catch (_) {}
    }
    res.status(fetchResponse.status).send(data);
  } catch (error) {
    console.error('API Gateway Error:', error);
    res.status(500).send({ error: 'Gateway Error', details: error.toString() });
  }
});

// SSO entre subdominios (ohtli.quest → lab.ohtli.quest). Ver functions/sso.js.
exports.ssoBridge = functions.https.onRequest(require('./sso').makeHandler(admin));

// Directorio de contactos verificados de perfiles públicos. Ver functions/directory.js.
exports.contactDirectory = functions.https.onRequest(require('./directory').makeHandler(admin));

// ---------------------------------------------------------------------------
// Avisos push (FCM): llegan aunque Ohtli esté cerrado. Ver functions/push.js,
// functions/trip_follow.js, lib/services/push_service.dart y web/ohtli_sw.js.
// ---------------------------------------------------------------------------
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { Timestamp } = require('firebase-admin/firestore');
const push = require('./push');
const tripFollow = require('./trip_follow');

// Un aviso con fecha en el futuro (plan sorpresa que se abre después) espera aquí su hora.
const PUSH_QUEUE = 'push_queue';

async function sendNotificationPush(db, uid, notifId, data) {
  const { title, body } = push.describePush(data);
  const payload = push.pushPayload({
    title,
    body,
    url: push.urlForNotification(uid, data),
    tag: `n-${notifId}`,
    kind: String(data.type || ''),
  });
  return push.sendToUser(db, admin.messaging(), uid, payload);
}

// Cada aviso nuevo de la campana (users/{uid}/notifications) se manda también como push.
exports.pushOnNotification = onDocumentCreated(
  { document: 'users/{uid}/notifications/{notifId}', region: 'us-central1', memory: '256MiB', maxInstances: 10 },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() || {};
    const { uid, notifId } = event.params;
    if (data.read === true || data.push === false) return;
    const db = admin.firestore();
    const ts = data.timestamp;
    if (ts instanceof Timestamp && ts.toMillis() > Date.now() + 60 * 1000) {
      await db.collection(PUSH_QUEUE).doc(`${uid}_${notifId}`).set({ uid, notifId, sendAt: ts });
      console.log('[push] en espera', uid, notifId, ts.toDate().toISOString());
      return;
    }
    const res = await sendNotificationPush(db, uid, notifId, data);
    console.log('[push] aviso', data.type, uid, notifId, JSON.stringify(res));
  }
);

// Cada 5 minutos: avisos de «hora de salir» del modo viaje y avisos en espera que ya tocan.
exports.pushTick = onSchedule(
  { schedule: 'every 5 minutes', region: 'us-central1', memory: '256MiB', timeoutSeconds: 120, maxInstances: 1, retryCount: 0 },
  async () => {
    const db = admin.firestore();
    const now = new Date();

    const follows = await db.collection('trip_follows').where('enabled', '==', true).limit(500).get();
    for (const doc of follows.docs) {
      try {
        const r = await tripFollow.checkFollow(db, admin.messaging(), doc, now, push);
        if (r !== 'nada que avisar' && r !== 'sin parada abierta') console.log('[push] seguir viaje', doc.id, r);
      } catch (e) {
        console.error('[push] seguir viaje', doc.id, e);
      }
    }

    const due = await db.collection(PUSH_QUEUE).where('sendAt', '<=', Timestamp.fromDate(now)).limit(200).get();
    for (const q of due.docs) {
      const { uid, notifId } = q.data();
      try {
        const n = await db.collection('users').doc(uid).collection('notifications').doc(notifId).get();
        // Si ya la borraron o la leyeron, no se manda.
        if (n.exists && n.get('read') !== true) {
          const res = await sendNotificationPush(db, uid, notifId, n.data());
          console.log('[push] aviso en espera', uid, notifId, JSON.stringify(res));
        }
        await q.ref.delete();
      } catch (e) {
        console.error('[push] aviso en espera', q.id, e);
      }
    }
  }
);
