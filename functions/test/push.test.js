'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const push = require('../push');

test('texto de los tipos conocidos', () => {
  const base = { senderName: 'Ana', tripTitle: 'Coyoacán', tripId: 't1' };
  const cases = {
    friend_request: 'Ana te envió una solicitud de amistad.',
    co_author_added: 'Ana te agregó como coautor en su viaje: "Coyoacán".',
    new_publication: 'Ana publicó un nuevo viaje: "Coyoacán".',
    surprise_plan: 'Ana te preparó un plan sorpresa: "Coyoacán".',
    itinerary_ready: 'Tus rutas con IA están listas para elegir.',
    group_trip_invite: 'Ana te invitó a planear juntos "Coyoacán".',
    group_trip_ready: 'Las rutas de "Coyoacán" están listas: vota por tu favorita.',
    group_trip_created: 'El plan "Coyoacán" quedó listo: ya pueden editarlo juntos.',
    group_trip_cancelled: 'Se canceló el plan "Coyoacán": nadie aceptó a tiempo.',
  };
  for (const [type, body] of Object.entries(cases)) {
    const r = push.describePush({ ...base, type });
    assert.equal(r.body, body, type);
    assert.ok(r.title.length > 0, type);
  }
  assert.equal(push.describePush({ type: 'friend_request', senderName: 'Ana', status: 'accepted' }).body, 'Ana y tú ahora son amigos.');
  assert.equal(push.describePush({ type: 'group_trip_ready', message: 'Voten ya' }).body, 'Voten ya');
});

test('tipo desconocido: texto genérico', () => {
  assert.deepEqual(push.describePush({ type: 'algo_nuevo', senderName: 'Luis' }), { title: 'Ohtli', body: 'Luis tiene algo para ti.' });
  assert.deepEqual(push.describePush({}), { title: 'Solicitud de amistad', body: 'Viajero Ohtli te envió una solicitud de amistad.' });
});

test('a dónde lleva el aviso', () => {
  assert.equal(push.urlForNotification('me', { type: 'itinerary_ready' }), '/mis-viajes');
  assert.equal(push.urlForNotification('me', { type: 'group_trip_invite', tripId: 't' }), '/notificaciones');
  assert.equal(push.urlForNotification('me', { type: 'new_publication', tripId: 't', senderId: 'ana' }), '/?tripId=t&authorId=ana');
  assert.equal(push.urlForNotification('me', { type: 'trip_comment', tripId: 't' }), '/?tripId=t&authorId=me');
  assert.equal(push.urlForNotification('me', { type: 'co_author_added', tripId: 't', tripOwnerId: 'o' }), '/?tripId=t&authorId=o');
  assert.equal(push.urlForNotification('me', { type: 'friend_request' }), '/notificaciones');
});

test('datos del mensaje: solo textos y recortados', () => {
  const p = push.pushPayload({ title: 'x'.repeat(200), body: 'Hola', url: '/a', tag: 'n-1', kind: 'cheer' });
  for (const v of Object.values(p)) assert.equal(typeof v, 'string');
  assert.equal(p.title.length, 90);
});

test('envío: borra los tokens muertos y respeta «Recibir notificaciones»', async () => {
  const deleted = [];
  let privacy = true;
  const tokens = ['vivo', 'muerto'];
  const db = {
    collection: () => ({ doc: () => ({ collection: (name) => (name === 'push_tokens'
      ? { get: async () => ({ empty: false, docs: tokens.map((id) => ({ id })) }), doc: (id) => ({ delete: async () => deleted.push(id) }) }
      : { doc: () => ({ get: async () => ({ exists: true, get: () => privacy }) }) }) }) }),
  };
  const messaging = {
    sendEachForMulticast: async ({ tokens: t }) => ({
      successCount: 1, failureCount: 1,
      responses: t.map((id) => (id === 'vivo' ? { success: true } : { success: false, error: { code: 'messaging/registration-token-not-registered' } })),
    }),
  };
  const r = await push.sendToUser(db, messaging, 'u', { title: 't' });
  assert.deepEqual(r, { sent: 1, failed: 1, pruned: 1 });
  assert.deepEqual(deleted, ['muerto']);
  privacy = false;
  assert.equal((await push.sendToUser(db, messaging, 'u', {})).skipped, 'notificaciones apagadas');
});
