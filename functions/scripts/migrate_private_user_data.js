#!/usr/bin/env node
/**
 * Mueve los datos personales de cada perfil público `users/{uid}` a su documento
 * privado `users/{uid}/private/account` y los borra del público.
 *
 * Campos: email, phone, addresses, privacy_share, privacy_notifications, privacy_public.
 * También mueve el perfil de gustos (taste_vector, cultural_profile, ejes, receta…).
 * Para cuentas dadas de baja (isDeleted == true) copia también `isDeleted` al privado,
 * que es lo que usa la app para restaurar una cuenta por correo.
 *
 * "Perfil público" (privacy_public) antes no tenía efecto y venía apagado por defecto:
 * todos los perfiles quedan públicos (privacy_public: true, profilePrivate: false).
 *
 * Por defecto solo informa qué cambiaría. Para aplicar los cambios:
 *   cd functions && npm install
 *   gcloud auth application-default login
 *   node scripts/migrate_private_user_data.js --apply
 */
const admin = require('firebase-admin');

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'othli-497404';
const PRIVATE_FIELDS = [
  'email',
  'phone',
  'addresses',
  'privacy_share',
  'privacy_notifications',
  'privacy_public',
  'cultural_profile',
  'taste_axes',
  'taste_axes_preview',
  'taste_recipe',
  'taste_vector',
  'taste_vector_dim',
  'taste_model',
  'taste_updated_at',
  'embedding_vector',
];
const APPLY = process.argv.includes('--apply');

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();
const { FieldValue } = admin.firestore;

async function main() {
  const users = await db.collection('users').get();
  let moved = 0;
  let untouched = 0;

  for (const doc of users.docs) {
    const data = doc.data();
    const legacyKeys = PRIVATE_FIELDS.filter((k) => Object.prototype.hasOwnProperty.call(data, k));
    const deletedFlag = data.isDeleted === true;
    if (legacyKeys.length === 0 && !deletedFlag) {
      untouched++;
      continue;
    }

    const privateRef = doc.ref.collection('private').doc('account');
    const privateSnap = await privateRef.get();
    const existing = privateSnap.exists ? privateSnap.data() : {};

    // Lo que ya está en el privado manda: solo se copian campos que falten
    const toCopy = {};
    for (const k of legacyKeys) {
      if (k === 'privacy_public') continue; // se reinicia a público (ver arriba)
      if (!Object.prototype.hasOwnProperty.call(existing, k)) toCopy[k] = data[k];
    }
    if (!Object.prototype.hasOwnProperty.call(existing, 'privacy_public')) toCopy.privacy_public = true;
    if (deletedFlag && existing.isDeleted !== true) toCopy.isDeleted = true;

    console.log(
      `${APPLY ? 'MIGRANDO' : '[simulación]'} ${doc.id}: copia [${Object.keys(toCopy).join(', ')}]` +
        ` · borra del público [${legacyKeys.join(', ')}]`,
    );

    if (APPLY) {
      const batch = db.batch();
      if (Object.keys(toCopy).length > 0) {
        batch.set(privateRef, { ...toCopy, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      }
      if (legacyKeys.length > 0) {
        const removal = {};
        for (const k of legacyKeys) removal[k] = FieldValue.delete();
        if (data.profilePrivate === undefined) removal.profilePrivate = existing.privacy_public === false;
        batch.update(doc.ref, removal);
      }
      await batch.commit();
    }
    moved++;
  }

  console.log(
    `\n${users.size} perfiles revisados · ${moved} ${APPLY ? 'migrados' : 'por migrar'} · ${untouched} sin datos privados`,
  );
  if (!APPLY) console.log('Nada se modificó. Ejecuta con --apply para aplicar los cambios.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
