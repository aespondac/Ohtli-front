/**
 * Directorio de contactos de perfiles públicos (buscar en Amigos por correo o teléfono).
 *
 * Solo esta función escribe en contact_directory (las reglas lo prohíben a los clientes),
 * y solo con datos que Firebase Auth tiene VERIFICADOS:
 *   - teléfono: el que la persona vinculó a su cuenta con un código por SMS;
 *   - correo: el de la cuenta, si está verificado.
 * Así nadie puede registrar el número o el correo de otra persona.
 *
 * POST /__directory/sync con el ID token (header Authorization: Bearer … o cuerpo
 * {idToken}). Lee la privacidad en users/{uid}/private/account (privacy_public y
 * contact_discoverable), publica los hashes que tocan y borra los que ya no.
 *
 * Los hashes son sha256("ohtli:<tipo>:<valor normalizado>"), igual que en la app
 * (lib/services/profile_directory.dart): el dato nunca se guarda en claro.
 */
const crypto = require('crypto');

const MAIN_HOST = 'ohtli.quest';

function hashOf(kind, value) {
  return crypto.createHash('sha256').update(`ohtli:${kind}:${value}`, 'utf8').digest('hex');
}

/** +52 y los últimos 10 dígitos (México), o null. */
function normalizePhone(raw) {
  const digits = String(raw || '').replace(/\D/g, '');
  if (digits.length < 10) return null;
  return '+52' + digits.slice(-10);
}

function normalizeEmail(raw) {
  const e = String(raw || '').trim().toLowerCase();
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) ? e : null;
}

function allowedOrigin(value) {
  if (!value) return true; // misma petición de Hosting sin Origin
  try {
    const u = new URL(value);
    const host = u.hostname.toLowerCase();
    return u.protocol === 'https:' && (host === MAIN_HOST || host.endsWith('.' + MAIN_HOST) || host.endsWith('.web.app') || host.endsWith('.firebaseapp.com'));
  } catch (_) {
    return false;
  }
}

function makeHandler(admin) {
  const db = admin.firestore();
  return async (req, res) => {
    res.set('Cache-Control', 'no-store');
    if (req.method !== 'POST') return res.status(405).json({ error: 'method' });
    if (!allowedOrigin(req.get('origin'))) return res.status(403).json({ error: 'origin' });

    const header = req.get('authorization') || '';
    const idToken = header.startsWith('Bearer ') ? header.slice(7) : (req.body && req.body.idToken);
    if (!idToken) return res.status(401).json({ error: 'auth' });

    let uid;
    try {
      uid = (await admin.auth().verifyIdToken(String(idToken))).uid;
    } catch (_) {
      return res.status(401).json({ error: 'auth' });
    }

    try {
      const [user, privSnap] = await Promise.all([
        admin.auth().getUser(uid),
        db.doc(`users/${uid}/private/account`).get(),
      ]);
      const priv = privSnap.exists ? privSnap.data() : {};
      const isPublic = priv.privacy_public !== false;
      const allow = priv.contact_discoverable !== false;

      const want = new Set();
      if (isPublic && allow) {
        const phone = normalizePhone(user.phoneNumber); // solo existe si se verificó por SMS
        if (phone) want.add(hashOf('phone', phone));
        const email = user.emailVerified ? normalizeEmail(user.email) : null;
        if (email) want.add(hashOf('email', email));
      }

      const had = new Set(Array.isArray(priv.directory_hashes) ? priv.directory_hashes.map(String) : []);
      const batch = db.batch();
      for (const h of had) {
        if (want.has(h)) continue;
        const ref = db.doc(`contact_directory/${h}`);
        const doc = await ref.get();
        if (doc.exists && doc.get('uid') === uid) batch.delete(ref);
      }
      const kept = [];
      for (const h of want) {
        const ref = db.doc(`contact_directory/${h}`);
        const doc = await ref.get();
        // Un dato verificado pertenece a una sola cuenta; si otra lo tenía (p. ej. cambió
        // de número), el verificado más reciente gana.
        batch.set(ref, { uid, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
        if (doc.exists && doc.get('uid') !== uid) {
          console.log('[directory] dato reasignado al dueño verificado');
        }
        kept.push(h);
      }
      batch.set(db.doc(`users/${uid}/private/account`), {
        directory_hashes: kept,
        phone_verified: Boolean(user.phoneNumber),
      }, { merge: true });
      await batch.commit();
      return res.json({ ok: true, published: kept.length });
    } catch (e) {
      console.error('[directory] sync', e);
      return res.status(500).json({ error: 'internal' });
    }
  };
}

module.exports = { makeHandler, hashOf, normalizePhone, normalizeEmail };
