'use strict';
// Pruebas del aviso «hora de salir» del servidor. Correr con: npm test (en functions/).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const tf = require('../trip_follow');

// Los mismos casos que prueba la app (test/trip_follow_leave_alert_test.dart).
const fixture = fs.readFileSync(path.join(__dirname, '../../test/fixtures/leave_alert_cases.dart'), 'utf8');
const cases = JSON.parse(fixture.slice(fixture.indexOf("r'''") + 4, fixture.lastIndexOf("'''")));
const minutes = (s) => { const [h, m, sec] = s.split(':').map(Number); return h * 60 + m + (sec || 0) / 60; };

for (const c of cases) {
  test(`caso compartido: ${c.name}`, () => {
    const a = tf.leaveAlertFor(c.sections, minutes(c.now), []);
    const got = a && { alert: a.alert, stopId: a.stopId, nextId: a.nextId, leaveBy: tf.hhmm(a.leaveBy), travelMins: a.travelMins, title: a.title, body: a.body };
    assert.deepEqual(got, c.expected);
  });
}

test('cada aviso sale una sola vez; «ya es hora» cancela el «pronto»', () => {
  const c = cases.find((x) => x.expected && x.expected.alert === 'soon');
  const now = minutes(c.now);
  assert.equal(tf.leaveAlertFor(c.sections, now, [`soon:${c.expected.stopId}`]), null);
  assert.equal(tf.leaveAlertFor(c.sections, now, [`now:${c.expected.stopId}`]), null);
  const later = tf.leaveAlertFor(c.sections, minutes(c.expected.leaveBy) + 1, [`soon:${c.expected.stopId}`]);
  assert.equal(later.alert, 'now');
});

test('coordenadas del catálogo cuando la parada no las trae', () => {
  const sections = [
    { id: 'a', type: 'place', title: 'A', arrivedAt: '10:00', poiId: 'p1' },
    { id: 't', type: 'transfer', mode: 'walking', durationMins: 1 },
    { id: 'b', type: 'place', title: 'B', arrivalTime: '12:00', lat: 19.4326, lng: -99.1332 },
  ];
  assert.equal(tf.travelMinutesTo(sections, sections[2], sections[0]), 1);
  const viaCatalog = tf.travelMinutesTo(sections, sections[2], sections[0], { a: { lat: 19.4352, lng: -99.1412 } });
  assert.equal(viaCatalog, 15);
});

test('hora local por zona y por desfase', () => {
  const at = new Date('2026-11-15T18:30:15Z');
  assert.deepEqual(tf.localClock(at, 'America/Mexico_City', null), { day: '2026-11-15', minutes: 12 * 60 + 30 + 0.25 });
  assert.deepEqual(tf.localClock(at, 'Zona/Inexistente', -360), { day: '2026-11-15', minutes: 12 * 60 + 30 + 0.25 });
  assert.equal(tf.localClock(new Date('2026-11-16T05:10:00Z'), 'America/Mexico_City').day, '2026-11-15');
});
