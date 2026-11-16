'use strict';

// «Seguir mi viaje» desde el servidor: avisos «Sal en N min de X» y «Es hora de salir de X» aunque
// Ohtli esté cerrado. Es un port de leavePlanFor, travelMinutesTo y leaveAlertAt de
// lib/services/trip_follow.dart (sin la ubicación en vivo, que solo existe con la app abierta) y del
// texto de _checkLeaveAlert (lib/screens/trips/trip_viewer_page.dart). Si cambias uno, cambia el otro:
// test/fixtures/leave_plan_cases.json lo comprueban las pruebas de los dos lados.
//
// Las horas se manejan como minutos desde la medianoche del día local de la persona: el plan es de
// un solo día (la etapa «durante» es el día del viaje) y las horas del plan son "HH:mm".

// Velocidad (km/h) y verbo de cada medio: kTransferModes de lib/services/trip_transfers.dart.
const MODES = {
  walking: [4.5, 'a pie'],
  metro: [25, 'en metro'],
  metrobus: [18, 'en metrobús'],
  bus: [14, 'en camión'],
  bike: [13, 'en bici'],
  taxi: [20, 'en taxi'],
  car: [20, 'en auto'],
  cablebus: [18, 'en cablebús'],
  trolebus: [15, 'en trolebús'],
  tren_ligero: [25, 'en tren ligero'],
  suburbano: [50, 'en suburbano'],
  scooter: [14, 'en scooter'],
  trajinera: [4, 'en trajinera'],
  other: [15, ''],
};

const SOON_BEFORE_MIN = 10;
const NOW_WINDOW_MIN = 20;

function modeOf(id) {
  const key = Object.prototype.hasOwnProperty.call(MODES, id) ? id : 'walking';
  return { id: key, kmh: MODES[key][0], verb: MODES[key][1] };
}

function parseClockMinutes(value) {
  if (value == null) return null;
  const m = /(\d{1,2}):(\d{2})/.exec(String(value));
  if (!m) return null;
  const h = parseInt(m[1], 10);
  const min = parseInt(m[2], 10);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

function hhmm(minutes) {
  const m = ((Math.floor(minutes) % 1440) + 1440) % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

function formatDuration(mins) {
  if (mins < 60) return `${mins} min`;
  const h = Math.floor(mins / 60);
  const r = mins % 60;
  return r === 0 ? `${h} h` : `${h} h ${r} min`;
}

function haversineKm(lat1, lng1, lat2, lng2) {
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(a));
}

function num(v) {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

/** Coordenadas de una parada como las lee PlaceSection.fromMap (lat/lng o location). */
function coordsOf(section) {
  if (!section) return null;
  let lat = num(section.lat);
  let lng = num(section.lng);
  if (lat == null && section.location && typeof section.location === 'object') {
    lat = num(section.location.lat ?? section.location.latitude);
    lng = num(section.location.lng ?? section.location.longitude);
  }
  return lat != null && lng != null ? { lat, lng } : null;
}

/** Traslado justo antes de la sección [index] (entre ella y la parada anterior), si existe. */
function transferBefore(sections, index) {
  for (let i = index - 1; i >= 0; i--) {
    const s = sections[i];
    if (s && s.type === 'transfer') return s;
    if (s && s.type === 'place') return null;
  }
  return null;
}

function transferMinutes(t) {
  const v = t ? num(t.durationMins) : null;
  return v == null ? null : Math.trunc(v);
}

/**
 * Minutos para llegar a [to] desde la parada [from] con el medio del traslado que va antes de [to];
 * sin ubicaciones, el tiempo que dice ese traslado. [coords] permite pasar las coordenadas que se
 * resolvieron en el catálogo (por id de sección).
 */
function travelMinutesTo(sections, to, from, coords = {}) {
  const t = transferBefore(sections, sections.indexOf(to));
  const toC = coordsOf(to) || coords[to.id] || null;
  const fromC = from ? (coordsOf(from) || coords[from.id] || null) : null;
  if (toC && fromC) {
    const mode = modeOf((t && t.mode) || 'walking');
    const km = haversineKm(fromC.lat, fromC.lng, toC.lat, toC.lng) * 1.3;
    const wait = (mode.id === 'metro' || mode.id === 'metrobus' || mode.id === 'bus') ? 8 : (mode.id === 'taxi' ? 5 : 0);
    const live = Math.max(1, Math.round((km / mode.kmh) * 60) + wait);
    return Math.max(live, transferMinutes(t) || 0);
  }
  return transferMinutes(t);
}

/**
 * Hora de salir de [here] (minutos del día): la llegada planeada a [next] menos el traslado; si no
 * se puede calcular, la salida planeada de [here].
 */
function leavePlanFor(here, next, travelMins) {
  const arriveBy = next ? parseClockMinutes(next.arrivalTime ?? next.arrival_time) : null;
  if (arriveBy != null && travelMins != null) return { leaveBy: arriveBy - travelMins, next, arriveBy, travelMins };
  const dep = parseClockMinutes(here.departureTime ?? here.departure_time);
  if (dep != null) return { leaveBy: dep, next: next || null, arriveBy, travelMins };
  return null;
}

/** 'soon' desde 10 min antes, 'now' a la hora y hasta 20 min después; después, nada. */
function leaveAlertAt(nowMin, leaveByMin) {
  if (nowMin < leaveByMin - SOON_BEFORE_MIN) return null;
  if (nowMin < leaveByMin) return 'soon';
  if (nowMin < leaveByMin + NOW_WINDOW_MIN) return 'now';
  return null;
}

/** Donde están (llegaron y no se han ido) y las paradas que faltan, como _hereStop/_pendingStops. */
function followState(sections) {
  const places = sections.filter((s) => s && s.type === 'place');
  let here = null;
  for (let i = places.length - 1; i >= 0; i--) {
    if (places[i].arrivedAt != null && places[i].leftAt == null) {
      here = places[i];
      break;
    }
  }
  const pending = places.filter((p) => p.arrivedAt == null && p !== here);
  return { here, pending };
}

/**
 * El aviso que toca a la hora [nowMin] (minutos del día, con fracción) o null. [sent] son las
 * claves ya avisadas ("soon:<id>", "now:<id>"), compartidas con el aviso local de la app.
 */
function leaveAlertFor(sections, nowMin, sent = [], coords = {}) {
  const { here, pending } = followState(sections);
  if (!here) return null;
  const next = pending.length ? pending[0] : null;
  const mins = next ? travelMinutesTo(sections, next, here, coords) : null;
  const plan = leavePlanFor(here, next, mins);
  if (!plan) return null;
  const alert = leaveAlertAt(nowMin, plan.leaveBy);
  if (!alert) return null;
  const key = `${alert}:${here.id}`;
  if (sent.includes(key) || sent.includes(`now:${here.id}`)) return null;

  const name = String(here.title || '').trim() || 'esta parada';
  const nextName = next ? (String(next.title || '').trim() || 'la siguiente parada') : '';
  let body;
  if (next && plan.arriveBy != null) {
    const mode = modeOf((transferBefore(sections, sections.indexOf(next)) || {}).mode || 'walking');
    const trip = plan.travelMins != null ? ` (unos ${formatDuration(plan.travelMins)}${mode.verb ? ` ${mode.verb}` : ''})` : '';
    body = `Para llegar a ${nextName} a las ${hhmm(plan.arriveBy)}${trip}.`;
  } else {
    body = `El plan era salir a las ${hhmm(plan.leaveBy)}${next ? ` rumbo a ${nextName}` : ''}.`;
  }
  const title = alert === 'soon'
    ? `Sal en ${Math.max(1, Math.ceil(plan.leaveBy - nowMin))} min de ${name}`
    : `Es hora de salir de ${name}`;
  return { key, alert, stopId: here.id, nextId: next ? next.id : null, leaveBy: plan.leaveBy, travelMins: plan.travelMins ?? null, title, body };
}

/**
 * Fecha ("YYYY-MM-DD") y minutos del día (con fracción) de [date] en la zona [tz]; si la zona no
 * sirve, con el desfase [offsetMin] (minutos al este de UTC).
 */
function localClock(date, tz, offsetMin) {
  if (tz) {
    try {
      const parts = new Intl.DateTimeFormat('en-CA', {
        timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit',
        hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
      }).formatToParts(date);
      const get = (t) => (parts.find((p) => p.type === t) || {}).value;
      const h = parseInt(get('hour'), 10) % 24;
      return { day: `${get('year')}-${get('month')}-${get('day')}`, minutes: h * 60 + parseInt(get('minute'), 10) + parseInt(get('second'), 10) / 60 };
    } catch (_) { /* zona desconocida: se usa el desfase */ }
  }
  const local = new Date(date.getTime() + (num(offsetMin) || 0) * 60000);
  return {
    day: local.toISOString().slice(0, 10),
    minutes: local.getUTCHours() * 60 + local.getUTCMinutes() + local.getUTCSeconds() / 60,
  };
}

/** Coordenadas de catálogo (pois/{poiId}.location) de las paradas que no las traen. */
async function catalogCoords(db, sections) {
  const out = {};
  const { here, pending } = followState(sections);
  for (const p of [here, pending[0]]) {
    if (!p || coordsOf(p) || !p.poiId) continue;
    try {
      const col = p.poiSource === 'suggestion' ? 'poi_suggestions' : 'pois';
      const doc = await db.collection(col).doc(String(p.poiId)).get();
      const loc = doc.exists ? doc.get('location') : null;
      if (loc && typeof loc.latitude === 'number') out[p.id] = { lat: loc.latitude, lng: loc.longitude };
      else if (loc && typeof loc === 'object') {
        const c = coordsOf({ location: loc });
        if (c && (c.lat !== 0 || c.lng !== 0)) out[p.id] = c;
      }
    } catch (_) { /* sin catálogo: se usa el traslado planeado */ }
  }
  return out;
}

/**
 * Revisa un seguimiento (trip_follows/{tripId_uid}) y manda el aviso de salida si toca.
 * Devuelve lo que hizo, para el registro.
 */
async function checkFollow(db, messaging, followDoc, now, { sendToUser, pushPayload }) {
  const f = followDoc.data() || {};
  const { uid, ownerId, tripId } = f;
  if (!uid || !ownerId || !tripId) return 'incompleto';
  const clock = localClock(now, f.tz, f.tzOffsetMin);
  if (f.day && clock.day > f.day) {
    await followDoc.ref.update({ enabled: false, endedBy: 'server-day' });
    return 'terminó el día';
  }
  if (f.day && clock.day < f.day) return 'aún no empieza';

  const tripRef = db.collection('users').doc(ownerId).collection('trips').doc(tripId);
  const [tripSnap, contentSnap] = await Promise.all([tripRef.get(), tripRef.collection('details').doc('content').get()]);
  const trip = tripSnap.exists ? tripSnap.data() : null;
  // Solo quien puede editar el viaje lo sigue: el servidor lee el contenido sin reglas.
  const member = trip && (trip.userId === uid || ownerId === uid || (Array.isArray(trip.coAuthorIds) && trip.coAuthorIds.includes(uid)));
  if (!member || trip.finishedAt) {
    await followDoc.ref.update({ enabled: false, endedBy: member ? 'server-finished' : 'server-not-member' });
    return member ? 'viaje terminado' : 'sin permiso';
  }
  const sections = Array.isArray(contentSnap.get('sections')) ? contentSnap.get('sections') : [];
  const sent = Array.isArray(f.sent) ? f.sent : [];
  const { here } = followState(sections);
  if (!here) return 'sin parada abierta';
  const coords = await catalogCoords(db, sections);
  const alert = leaveAlertFor(sections, clock.minutes, sent, coords);
  if (!alert) return 'nada que avisar';

  // Se marca antes de mandar: a lo más un aviso por clave aunque dos corridas se encimen.
  const { FieldValue } = require('firebase-admin/firestore');
  await followDoc.ref.update({ sent: FieldValue.arrayUnion(alert.key), lastAlertAt: FieldValue.serverTimestamp() });
  const payload = pushPayload({
    title: alert.title,
    body: alert.body,
    url: `/?tripId=${encodeURIComponent(tripId)}&authorId=${encodeURIComponent(ownerId)}`,
    // Mismo tag que el aviso local de la app: si llegan los dos, uno reemplaza al otro.
    tag: `leave-alert-${alert.stopId}`,
    kind: `leave_${alert.alert}`,
  });
  const res = await sendToUser(db, messaging, uid, payload, { ttlSeconds: 30 * 60 });
  return `${alert.key} → ${JSON.stringify(res)}`;
}

module.exports = {
  parseClockMinutes,
  hhmm,
  formatDuration,
  coordsOf,
  transferBefore,
  travelMinutesTo,
  leavePlanFor,
  leaveAlertAt,
  followState,
  leaveAlertFor,
  localClock,
  checkFollow,
};
