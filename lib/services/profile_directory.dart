import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'public_profiles.dart';

/// Cómo encontrar perfiles públicos además de por nombre:
///
/// - **Usertag** (`@mariana.lopez`): público y único. `usertags/{tag}` → `{uid}` y el campo
///   `usertag` en `users/{uid}`.
/// - **Correo y teléfono**: son privados, así que nunca se guardan en claro. En
///   `contact_directory/{sha256}` solo va el hash del dato normalizado y el uid. Nadie puede
///   listar la colección (reglas): solo consultar un correo o teléfono exacto.
///
/// Correo y teléfono solo se publican si el perfil es público, la persona lo permite
/// (`contact_discoverable`, por defecto sí) y están verificados (el teléfono por SMS).
/// Los publica la función contactDirectory, no la app.
class ProfileDirectory {
  ProfileDirectory._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static final RegExp _tagPattern = RegExp(r'^[a-z0-9._]{3,20}$');

  /// Teléfono en formato +52XXXXXXXXXX (10 dígitos de México), o null si no lo parece.
  static String? normalizePhone(String? raw) {
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return null;
    return '+52${digits.substring(digits.length - 10)}';
  }

  static String? normalizeEmail(String? raw) {
    final e = raw?.trim().toLowerCase() ?? '';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e) ? e : null;
  }

  /// Contienen a Ohtli o suplantan a personal o autoridades: nadie puede usarlos.
  /// (Las mismas raíces están en firestore.rules.)
  static const List<String> reservedRoots = [
    'ohtli', 'admin', 'soporte', 'support', 'oficial', 'official', 'staff', 'moderador', 'moderator',
  ];

  /// Reservados como usertag completo.
  static const Set<String> reservedExact = {
    'root', 'system', 'sistema', 'api', 'www', 'app', 'labs', 'null', 'undefined', 'help', 'ayuda',
    'equipo', 'team', 'seguridad', 'security', 'gob', 'gobierno', 'cdmx', 'presidencia', 'policia',
    'sat', 'imss', 'ine', 'verificado', 'verified', 'mod', 'info', 'contacto', 'contact', 'legal',
  };

  /// Prohibidos por ley o por las reglas de la plataforma: groserías, odio, violencia,
  /// delitos, contenido sexual. Se buscan también con sustituciones (0→o, 1→i, 3→e…).
  static const List<String> prohibitedRoots = [
    'puta', 'puto', 'pendej', 'verga', 'chinga', 'culero', 'mierda', 'cabron', 'pinche',
    'joto', 'maricon', 'marica', 'nazi', 'hitler', 'kkk', 'fuck', 'shit', 'bitch', 'nigg',
    'faggot', 'cunt', 'whore', 'porn', 'xxx', 'nude', 'pedofil', 'pederast', 'violador',
    'rape', 'narco', 'sicario', 'cartel', 'terroris', 'yihad', 'jihad', 'suicid', 'cocaina',
    'cocaine', 'heroina',
  ];

  static String _deLeet(String t) => t
      .replaceAll(RegExp(r'[._]'), '')
      .replaceAll('0', 'o')
      .replaceAll('1', 'i')
      .replaceAll('3', 'e')
      .replaceAll('4', 'a')
      .replaceAll('5', 's')
      .replaceAll('7', 't')
      .replaceAll('8', 'b');

  /// Por qué no se permite un usertag (ya normalizado): 'reserved', 'prohibited' o null si se puede.
  static String? tagProblem(String tag) {
    final plain = _deLeet(tag);
    if (reservedExact.contains(tag) || reservedExact.contains(plain)) return 'reserved';
    if (reservedRoots.any((r) => tag.contains(r) || plain.contains(r))) return 'reserved';
    if (prohibitedRoots.any((r) => plain.contains(r) || tag.contains(r))) return 'prohibited';
    return null;
  }

  /// Usertag sin «@», en minúsculas; null si no es válido (3-20: letras, números, punto, guion bajo).
  static String? normalizeTag(String? raw) {
    var t = raw?.trim().toLowerCase() ?? '';
    if (t.startsWith('@')) t = t.substring(1);
    return _tagPattern.hasMatch(t) ? t : null;
  }

  static String hashOf(String kind, String value) => sha256.convert(utf8.encode('ohtli:$kind:$value')).toString();

  /// Qué buscó la persona: usertag, correo, teléfono o nombre.
  static ({String kind, String value})? classify(String query) {
    final q = query.trim();
    if (q.isEmpty) return null;
    if (q.startsWith('@')) {
      final t = normalizeTag(q);
      return t == null ? null : (kind: 'tag', value: t);
    }
    final email = normalizeEmail(q);
    if (email != null) return (kind: 'email', value: email);
    final digits = q.replaceAll(RegExp(r'[\s\-()+]'), '');
    if (RegExp(r'^\d{10,13}$').hasMatch(digits)) {
      final p = normalizePhone(digits);
      return p == null ? null : (kind: 'phone', value: p);
    }
    return (kind: 'name', value: q);
  }

  /// uid del perfil público que corresponde a un usertag, correo o teléfono exacto.
  static Future<String?> lookup(String kind, String value) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = kind == 'tag'
          ? await _db.collection('usertags').doc(value).get()
          : await _db.collection('contact_directory').doc(hashOf(kind, value)).get();
      return doc.data()?['uid'] as String?;
    } catch (e) {
      debugPrint('[Directorio] búsqueda $kind: $e');
      return null;
    }
  }

  /// ¿Está libre el usertag (o ya es tuyo)?
  static Future<bool> isTagAvailable(String tag, String uid) async {
    final doc = await _db.collection('usertags').doc(tag).get();
    return !doc.exists || doc.data()?['uid'] == uid;
  }

  /// Reserva el usertag para [uid] y libera el anterior. Lanza [StateError] si ya es de otra persona.
  static Future<void> claimTag(String uid, String rawTag) async {
    final tag = normalizeTag(rawTag);
    if (tag == null) throw StateError('Usa de 3 a 20 letras, números, punto o guion bajo.');
    if (tagProblem(tag) != null) throw StateError('Ese usertag no está disponible.');
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final tagRef = _db.collection('usertags').doc(tag);
      final existing = await tx.get(tagRef);
      if (existing.exists && existing.data()?['uid'] != uid) {
        throw StateError('Ese usertag ya lo tiene alguien más.');
      }
      final user = await tx.get(userRef);
      final old = user.data()?['usertag'] as String?;
      if (old != null && old != tag) tx.delete(_db.collection('usertags').doc(old));
      if (!existing.exists) tx.set(tagRef, {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
      tx.set(userRef, {'usertag': tag}, SetOptions(merge: true));
    });
    await PublicProfiles.mirror(uid, {'usertag': tag});
  }

  /// Pide al servidor publicar o retirar tu correo y teléfono según tu privacidad.
  /// Solo la función contactDirectory escribe el directorio y solo con datos verificados
  /// por Firebase Auth (teléfono por SMS, correo verificado). Se llama al guardar datos
  /// privados (UserPrivateData.save) y al verificar el teléfono.
  static Future<void> sync(String uid) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || me.uid != uid) return;
    try {
      final token = await me.getIdToken();
      final res = await http
          .post(Uri.base.resolve('/__directory/sync'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: '{}')
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) debugPrint('[Directorio] sync ${res.statusCode}');
    } catch (e) {
      debugPrint('[Directorio] sync: $e');
    }
  }
}
