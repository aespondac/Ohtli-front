#!/usr/bin/env node
/**
 * Crea o actualiza `public_profiles/{uid}` a partir de `users/{uid}` para las cuentas que
 * ya existían antes de esa colección.
 *
 * `users/{uid}` solo lo lee su dueño (firestore.rules); lo que ven los demás (nombre,
 * foto, usertag, título, portada, momentos, perfil privado y baja) se copia aquí. La app
 * mantiene la copia al día cada vez que el usuario guarda su perfil
 * (lib/services/public_profiles.dart), así que este script solo hace falta una vez.
 *
 * Correrlo ANTES de publicar el front que lee `public_profiles`.
 *
 * Por defecto solo informa qué cambiaría. Para aplicar los cambios:
 *   cd functions && npm install
 *   gcloud auth application-default login
 *   node scripts/backfill_public_profiles.js --apply
 */
const PROJECT_ID = process.env.GCLOUD_PROJECT || 'othli-497404';
// Mismos campos que PublicProfiles.fields y que permite la regla de /public_profiles.
const PUBLIC_FIELDS = [
  'displayName',
  'photoURL',
  'coverURL',
  'coverUrl',
  'usertag',
  'activeTitleId',
  'possessedTitles',
  'moments',
  'createdAt',
  'profilePrivate',
  'isDeleted',
];

const APPLY = process.argv.includes('--apply');

function pickPublic(data) {
  const out = {};
  for (const k of PUBLIC_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(data, k)) out[k] = data[k];
  }
  return out;
}

async function main() {
  const admin = require('firebase-admin');
  admin.initializeApp({ projectId: PROJECT_ID });
  const db = admin.firestore();
  const users = await db.collection('users').get();
  let written = 0;
  for (const doc of users.docs) {
    const visible = pickPublic(doc.data());
    console.log(`${APPLY ? 'COPIANDO' : '[simulación]'} ${doc.id}: [${Object.keys(visible).join(', ')}]`);
    if (APPLY) {
      await db.collection('public_profiles').doc(doc.id).set(
        { ...visible, uid: doc.id, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true },
      );
    }
    written++;
  }
  console.log(`${written} perfiles ${APPLY ? 'copiados' : 'por copiar (usa --apply)'}.`);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = { pickPublic, PUBLIC_FIELDS };
