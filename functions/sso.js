/**
 * SSO entre subdominios de Ohtli (ohtli.quest → lab.ohtli.quest, …).
 *
 * Firebase Auth guarda la sesión por origen, así que cada subdominio tendría que
 * iniciar sesión por separado. El puente funciona con un código de un solo uso:
 *
 *   1. El subdominio sin sesión manda al usuario a https://ohtli.quest/sso?return=<url>.
 *   2. En ohtli.quest (donde ya hay sesión) la app llama a POST /__sso/issue con su
 *      ID token. Aquí se valida el token y se guarda un código aleatorio que vale
 *      60 s, ligado al uid y al origen de destino (solo se guarda su hash).
 *   3. ohtli.quest vuelve a <url>#ohtli_sso=<código> (en el fragmento: no llega a
 *      ningún servidor ni a los logs).
 *   4. El subdominio llama a POST /__sso/redeem con el código. Si es válido, no ha
 *      caducado, no se había usado y el origen coincide, se borra y se responde con
 *      un custom token de Firebase, con el que el subdominio inicia sesión.
 *
 * Ambos endpoints se sirven en el mismo origen que la app (rewrite de Hosting
 * /__sso/** → ssoBridge), por eso no hay CORS: solo se aceptan peticiones cuyo
 * Origin sea https://ohtli.quest o un subdominio *.ohtli.quest.
 *
 * Requisito de despliegue: la cuenta de servicio con la que corre la función debe
 * poder firmar tokens (rol "Service Account Token Creator" sobre sí misma) para
 * que createCustomToken funcione.
 */
const crypto = require('crypto');

const MAIN_HOST = 'ohtli.quest';
const CODE_TTL_MS = 60 * 1000;
const CODE_RE = /^[A-Za-z0-9_-]{43}$/; // 32 bytes en base64url

/** https://ohtli.quest o https://<sub>.ohtli.quest, sin puerto ni credenciales. */
function parseOhtliOrigin(value) {
  try {
    const u = new URL(String(value || ''));
    if (u.protocol !== 'https:' || u.port || u.username || u.password) return null;
    const host = u.hostname.toLowerCase();
    if (host !== MAIN_HOST && !host.endsWith('.' + MAIN_HOST)) return null;
    return { origin: u.origin, host };
  } catch (_) {
    return null;
  }
}

const hashCode = (code) => crypto.createHash('sha256').update(code).digest('hex');

function makeHandler(admin) {
  const db = () => admin.firestore();

  return async (req, res) => {
    res.set('Cache-Control', 'no-store');
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'method_not_allowed' });
      return;
    }
    const caller = parseOhtliOrigin(req.get('Origin'));
    if (!caller) {
      res.status(403).json({ error: 'origin_not_allowed' });
      return;
    }
    const action = req.path.split('/').filter(Boolean).pop();
    const body = req.body && typeof req.body === 'object' ? req.body : {};

    try {
      if (action === 'issue') {
        // Solo el dominio principal emite códigos, y solo para un subdominio.
        if (caller.host !== MAIN_HOST) {
          res.status(403).json({ error: 'issuer_not_allowed' });
          return;
        }
        const target = parseOhtliOrigin(body.target);
        if (!target || target.host === MAIN_HOST) {
          res.status(400).json({ error: 'invalid_target' });
          return;
        }
        const match = (req.get('Authorization') || '').match(/^Bearer (.+)$/);
        if (!match) {
          res.status(401).json({ error: 'missing_token' });
          return;
        }
        let decoded;
        try {
          decoded = await admin.auth().verifyIdToken(match[1], true);
        } catch (_) {
          res.status(401).json({ error: 'invalid_token' });
          return;
        }
        const code = crypto.randomBytes(32).toString('base64url');
        const now = Date.now();
        await db().collection('sso_codes').doc(hashCode(code)).set({
          uid: decoded.uid,
          target: target.origin,
          createdAt: admin.firestore.Timestamp.fromMillis(now),
          expiresAt: admin.firestore.Timestamp.fromMillis(now + CODE_TTL_MS),
        });
        // Limpieza oportunista de códigos caducados que nadie canjeó.
        db().collection('sso_codes')
          .where('expiresAt', '<', admin.firestore.Timestamp.fromMillis(now - CODE_TTL_MS))
          .limit(20)
          .get()
          .then((snap) => Promise.all(snap.docs.map((d) => d.ref.delete())))
          .catch((e) => console.warn('sso cleanup', e.message));
        res.json({ code });
        return;
      }

      if (action === 'redeem') {
        const code = String(body.code || '');
        if (!CODE_RE.test(code)) {
          res.status(400).json({ error: 'invalid_code' });
          return;
        }
        const ref = db().collection('sso_codes').doc(hashCode(code));
        const uid = await db().runTransaction(async (tx) => {
          const snap = await tx.get(ref);
          if (!snap.exists) return null;
          const data = snap.data();
          tx.delete(ref); // un solo uso, pase lo que pase
          if (!data.expiresAt || data.expiresAt.toMillis() < Date.now()) return null;
          if (data.target !== caller.origin) return null;
          return data.uid;
        });
        if (!uid) {
          res.status(410).json({ error: 'code_expired_or_used' });
          return;
        }
        const token = await admin.auth().createCustomToken(uid, { ohtli_sso: true });
        res.json({ token });
        return;
      }

      res.status(404).json({ error: 'not_found' });
    } catch (e) {
      console.error('ssoBridge', action, e);
      res.status(500).json({ error: 'sso_unavailable' });
    }
  };
}

module.exports = { makeHandler, parseOhtliOrigin, hashCode, CODE_TTL_MS };
