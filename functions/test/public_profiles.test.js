// Las listas de campos del perfil visible deben coincidir en la app, las reglas y el backfill,
// y /users no puede volver a ser de lectura pública.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { pickPublic, PUBLIC_FIELDS } = require('../scripts/backfill_public_profiles');

const root = path.join(__dirname, '..', '..');
const rules = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
const dart = fs.readFileSync(path.join(root, 'lib', 'services', 'public_profiles.dart'), 'utf8');

function block(src, start) {
  const i = src.indexOf(start);
  assert.ok(i >= 0, `no se encontró ${start}`);
  let depth = 0;
  for (let j = i + start.length - 1; j < src.length; j++) {
    if (src[j] === '{') depth++;
    if (src[j] === '}' && --depth === 0) return src.slice(i, j + 1);
  }
  throw new Error('bloque sin cerrar');
}

test('users/{uid} solo lo lee su dueño (o la restauración por correo)', () => {
  const users = block(rules, 'match /users/{userId} {');
  const ownRules = users.split('match /social/graph')[0];
  assert.doesNotMatch(ownRules, /allow read:\s*if true/);
  assert.match(ownRules, /allow read: if request\.auth != null && \(\s*request\.auth\.uid == userId \|\| sameVerifiedEmailAs\(userId\)/);
});

test('la regla de public_profiles acepta exactamente los campos de la app y del backfill', () => {
  const pp = block(rules, 'match /public_profiles/{userId} {');
  const allowed = [...pp.match(/hasOnly\(\[([\s\S]*?)\]\)/)[1].matchAll(/'([^']+)'/g)].map((m) => m[1]);
  const dartFields = [...dart.match(/fields = \{([\s\S]*?)\};/)[1].matchAll(/'([^']+)'/g)].map((m) => m[1]);
  assert.deepStrictEqual([...dartFields].sort(), [...PUBLIC_FIELDS].sort());
  assert.deepStrictEqual([...allowed].sort(), [...PUBLIC_FIELDS, 'uid', 'updatedAt'].sort());
});

test('el backfill no copia datos privados', () => {
  const out = pickPublic({ displayName: 'Ana', phone: '55', addresses: [], taste_vector: [1], friends: ['b'], deletedAt: 1 });
  assert.deepStrictEqual(out, { displayName: 'Ana' });
});
