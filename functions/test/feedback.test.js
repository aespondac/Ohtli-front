'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fb = require('../feedback');

test('correo con el mensaje, el contexto y sin HTML inyectado', () => {
  const m = fb.buildFeedbackMail({
    uid: 'u1', message: 'La ruta <b>2</b> no carga', category: 'bug', screen: 'planear_con_ia',
    appVersion: '1.0.0', browser: 'Chrome · macOS', context: { paso: 'routeTriadCarousel', job_id: 'j1' },
  }, { id: 'abc' });
  assert.equal(m.subject, '[Ohtli · Algo falla] La ruta <b>2</b> no carga');
  assert.match(m.text, /^La ruta <b>2<\/b> no carga\n/);
  assert.match(m.text, /Pantalla: planear_con_ia/);
  assert.match(m.text, /job_id: j1/);
  assert.match(m.html, /La ruta &lt;b&gt;2&lt;\/b&gt; no carga/);
  assert.ok(!m.html.includes('<b>2</b>'));
});

test('asunto corto y tipo desconocido como Otro', () => {
  const m = fb.buildFeedbackMail({ message: 'x'.repeat(200), category: 'raro' });
  assert.ok(m.subject.startsWith('[Ohtli · Otro] '));
  assert.ok(m.subject.length < 100);
});

test('destinatarios: texto, lista y basura', () => {
  assert.deepEqual(fb.recipientsOf({ to: 'a@b.com' }), ['a@b.com']);
  assert.deepEqual(fb.recipientsOf({ to: ['a@b.com', 'no-es-correo', ' c@d.mx '] }), ['a@b.com', 'c@d.mx']);
  assert.deepEqual(fb.recipientsOf({ to: 'a@b.com, c@d.mx' }), ['a@b.com', 'c@d.mx']);
  assert.deepEqual(fb.recipientsOf(null), []);
});

test('límite por persona y hora', () => {
  let state = null;
  const t0 = 1_000_000;
  for (let i = 0; i < fb.RATE_LIMIT; i++) {
    const r = fb.nextRate(state, t0 + i);
    assert.equal(r.allowed, true);
    state = r.state;
  }
  assert.equal(fb.nextRate(state, t0 + 100).allowed, false);
  assert.equal(fb.nextRate(state, t0 + fb.RATE_WINDOW_MS).allowed, true);
});

function fakeDb(config) {
  const store = {};
  const ref = (col, id) => ({
    path: `${col}/${id}`,
    async get() { return snapOf(`${col}/${id}`); },
    async set(v) { store[`${col}/${id}`] = v; },
  });
  const snapOf = (p) => ({ exists: p in store, data: () => store[p] });
  if (config) store['private_config/feedback'] = config;
  return {
    store,
    collection: (col) => ({ doc: (id) => ref(col, id) }),
    async runTransaction(fn) {
      return fn({ get: async (r) => snapOf(r.path), set: (r, v) => { store[r.path] = v; } });
    },
  };
}
const snap = (d) => ({ data: () => d });

test('sin configuración llega al correo de privacidad', async () => {
  const db = fakeDb(null);
  const r = await fb.handleFeedback(db, snap({ uid: 'u', message: 'hola' }), 'f1');
  assert.equal(r, 'correo en cola');
  assert.deepEqual(db.store['mail/feedback_f1'].to, [fb.DEFAULT_TO]);
});

test('el destinatario es el mismo que LegalInfo.privacyEmail de la app', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const dart = fs.readFileSync(path.join(__dirname, '..', '..', 'lib', 'screens', 'legal', 'legal_content.dart'), 'utf8');
  const m = dart.match(/static const privacyEmail = '([^']+)'/);
  assert.ok(m, 'no se encontró LegalInfo.privacyEmail');
  assert.equal(fb.DEFAULT_TO, m[1]);
});

test('con destinatario deja el correo en la cola de la extensión', async () => {
  const db = fakeDb({ to: 'equipo@ohtli.test' });
  const r = await fb.handleFeedback(db, snap({ uid: 'u', message: 'hola', category: 'idea', screen: 'mi_cuenta' }), 'f1');
  assert.equal(r, 'correo en cola');
  const mail = db.store['mail/feedback_f1'];
  assert.deepEqual(mail.to, ['equipo@ohtli.test']);
  assert.equal(mail.message.subject, '[Ohtli · Idea] hola');
  assert.equal(db.store['feedback_rate/u'].count, 1);
});
