import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/admin.dart' show isSuperUser;

/// Roles de Ohtli Labs.
///  admin       superusuario: todo, incluida la publicación abierta y la gestión de miembros
///  researcher  miembro del laboratorio: ejecuta pruebas, ve todo lo privado y redacta artículos
///  tester      participante: responde estudios y ve lo liberado para testers
enum LabRole { none, tester, researcher, admin }

extension LabRoleX on LabRole {
  bool get isMember => this == LabRole.researcher || this == LabRole.admin;
  bool get isTester => this != LabRole.none;
  String get label => switch (this) {
        LabRole.admin => 'Administración',
        LabRole.researcher => 'Miembro del laboratorio',
        LabRole.tester => 'Tester',
        LabRole.none => 'Visitante',
      };
}

/// Niveles de visibilidad de corridas, agregados y artículos (la pipeline de publicación).
class LabVisibility {
  static const private = 'private'; // solo miembros del laboratorio
  static const testers = 'testers'; // miembros y testers registrados
  static const public = 'public'; // cualquiera, sin iniciar sesión

  static const all = [private, testers, public];

  static String of(Map<String, dynamic> d) {
    final v = d['visibility'];
    if (v is String && all.contains(v)) return v;
    return d['published'] == true ? public : private; // corridas anteriores a la pipeline
  }

  static String label(String v) => switch (v) {
        testers => 'Testers',
        public => 'Público',
        _ => 'Privado (laboratorio)',
      };

  static IconData icon(String v) => switch (v) {
        testers => Icons.group_outlined,
        public => Icons.public_rounded,
        _ => Icons.lock_outline_rounded,
      };
}

LabRole _parse(dynamic r) => switch (r) {
      'admin' => LabRole.admin,
      'researcher' => LabRole.researcher,
      'tester' => LabRole.tester,
      _ => LabRole.none,
    };

/// Rol de la sesión en Labs (lo fija LabsAppPage); decide qué controles se muestran en la
/// consola y en los experimentos. Las reglas de Firestore y el motor son los que protegen.
LabRole currentLabRole = LabRole.none;

class LabAccess {
  LabAccess._();
  static final _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> memberDoc(String uid) => _db.collection('lab_members').doc(uid);
  static DocumentReference<Map<String, dynamic>> inviteDoc(String email) =>
      _db.collection('lab_invites').doc(email.trim().toLowerCase());

  /// Rol del usuario. Si tiene una invitación pendiente para su correo, la acepta.
  static Future<LabRole> roleOf(User? user) async {
    if (user == null) return LabRole.none;
    if (isSuperUser(user)) return LabRole.admin;
    try {
      final m = await memberDoc(user.uid).get();
      var role = m.exists ? _parse(m.data()?['role']) : LabRole.none;
      final email = (user.email ?? '').toLowerCase();
      if (email.isNotEmpty && user.emailVerified && (role == LabRole.none || role == LabRole.tester)) {
        final inv = await inviteDoc(email).get();
        if (inv.exists) {
          final invited = _parse(inv.data()?['role']);
          if (invited.index > role.index) {
            await memberDoc(user.uid).set({
              'role': invited.name,
              // El correo y el nombre solo para el equipo (aparecen en la lista de miembros); a los
              // testers no se les guardan, como promete el consentimiento.
              if (invited.isMember) 'email': email,
              if (invited.isMember) 'displayName': user.displayName ?? '',
              'via': 'invite',
              'joinedAt': FieldValue.serverTimestamp(),
            });
            role = invited;
          }
          // La invitación ya se usó: si se quedara, al quitar a la persona (o si deja de ser tester)
          // roleOf la volvería a aceptar en su siguiente visita.
          try {
            await inviteDoc(email).delete();
          } catch (_) {}
        }
      }
      return role;
    } catch (_) {
      return LabRole.none;
    }
  }

  /// Alta como tester (con consentimiento). No guarda correo ni nombre.
  static Future<void> joinAsTester(User user) => memberDoc(user.uid).set({
        'role': 'tester',
        'via': 'self',
        'consent': true,
        'joinedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> leave(User user) => memberDoc(user.uid).delete();

  /// Quitar del laboratorio: borra el rol y la invitación de su correo (si no, roleOf la volvía
  /// a aceptar y la persona recuperaba el acceso).
  static Future<void> removeMember(String uid, String? email) async {
    await memberDoc(uid).delete();
    final e = (email ?? '').trim();
    if (e.isNotEmpty) await inviteDoc(e).delete();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMembers() =>
      _db.collection('lab_members').where('role', whereIn: ['researcher', 'admin']).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchInvites() => _db.collection('lab_invites').snapshots();

  static Future<int> testerCount() async {
    final q = await _db.collection('lab_members').where('role', isEqualTo: 'tester').count().get();
    return q.count ?? 0;
  }

  static Future<void> invite(String email, String role) => inviteDoc(email).set({
        'role': role,
        'invitedBy': FirebaseAuth.instance.currentUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
}
