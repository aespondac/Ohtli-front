#!/usr/bin/env node
/**
 * Título «Altepetlahtolli»: se gana al responder cualquier estudio de Ohtli Labs.
 *
 * 1. Crea `titles/altepetlahtolli` en el catálogo (las reglas no dejan escribirlo desde la app).
 * 2. Se lo da a quien ya respondió algún estudio (`lab_responses`) antes de que existiera:
 *    lo agrega a `users/{uid}.possessedTitles` y a `public_profiles/{uid}.possessedTitles`.
 *
 * Desde ahora la app lo otorga sola al enviar una respuesta (lib/labs/lab_title.dart).
 * Debe coincidir con kLabTitleId / kLabTitleName / kLabTitleDescription.
 *
 * Por defecto solo informa qué cambiaría. Para aplicar:
 *   cd functions && npm install
 *   gcloud auth application-default login
 *   node scripts/seed_title_altepetlahtolli.js --apply
 */
const PROJECT_ID = process.env.GCLOUD_PROJECT || 'othli-497404';
const TITLE_ID = 'altepetlahtolli';
const TITLE = {
  name: 'Altepetlahtolli',
  description: 'Respondió un estudio de Ohtli Labs: su voz ayudó a mejorar Ohtli.',
};
const APPLY = process.argv.includes('--apply');

async function main() {
  const admin = require('firebase-admin');
  admin.initializeApp({ projectId: PROJECT_ID });
  const db = admin.firestore();
  const { FieldValue } = admin.firestore;

  const titleRef = db.collection('titles').doc(TITLE_ID);
  const existing = await titleRef.get();
  console.log(existing.exists ? `titles/${TITLE_ID} ya existe: se actualiza nombre y descripción` : `titles/${TITLE_ID} se crea`);
  if (APPLY) await titleRef.set(TITLE, { merge: true });

  const uids = new Set();
  for (const d of (await db.collection('lab_responses').select('uid').get()).docs) {
    const uid = d.get('uid');
    if (typeof uid === 'string' && uid) uids.add(uid);
  }
  let granted = 0;
  for (const uid of uids) {
    const user = await db.collection('users').doc(uid).get();
    if (!user.exists) continue;
    const titles = user.get('possessedTitles') || [];
    if (titles.includes(TITLE_ID)) continue;
    granted++;
    const add = titles.length ? [TITLE_ID] : ['viajero', TITLE_ID];
    if (APPLY) {
      await user.ref.set({ possessedTitles: FieldValue.arrayUnion(...add) }, { merge: true });
      await db.collection('public_profiles').doc(uid).set(
        { uid, possessedTitles: FieldValue.arrayUnion(...add), updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
    }
  }
  console.log(`${uids.size} cuentas respondieron algún estudio; ${granted} ${APPLY ? 'recibieron' : 'recibirían'} el título.`);
  if (!APPLY) console.log('Nada se escribió. Usa --apply para aplicar.');
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
