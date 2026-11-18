import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/public_profiles.dart';

/// Título de viajero que se gana al responder cualquier estudio de Ohtli Labs.
/// «Altepetlahtolli»: la palabra (tlahtolli) del pueblo o la ciudad (altepetl).
///
/// El catálogo vive en `titles/{id}` (solo se escribe desde la consola o con el Admin SDK:
/// functions/scripts/seed_title_altepetlahtolli.js); aquí solo se agrega a los títulos que
/// posee la persona (`users/{uid}.possessedTitles`, que su dueño escribe) y a su perfil visible.
const String kLabTitleId = 'altepetlahtolli';
const String kLabTitleName = 'Altepetlahtolli';
const String kLabTitleDescription = 'Respondió un estudio de Ohtli Labs: su voz ayudó a mejorar Ohtli.';

class LabTitle {
  LabTitle._();

  /// La lista de títulos con el de Labs (conserva «viajero», el de todas las cuentas).
  static List<String> withLabTitle(List<dynamic>? possessed) {
    final out = <String>[for (final t in possessed ?? const []) t.toString()];
    if (out.isEmpty) out.add('viajero');
    if (!out.contains(kLabTitleId)) out.add(kLabTitleId);
    return out;
  }

  /// Otorga el título si todavía no lo tiene. Devuelve true si se acaba de ganar. No lanza.
  static Future<bool> grant(String uid) async {
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final current = (await ref.get()).data()?['possessedTitles'] as List?;
      if (current != null && current.contains(kLabTitleId)) return false;
      final titles = withLabTitle(current);
      await ref.set({
        'possessedTitles': titles,
        // Cuándo lo ganó (la vitrina de Logros lo muestra); los poseedores los recuenta el motor.
        'achievementLog': {
          for (final t in titles.where((t) => !(current ?? const []).contains(t))) t: {'earnedAt': FieldValue.serverTimestamp()},
        },
      }, SetOptions(merge: true));
      await PublicProfiles.mirror(uid, {'possessedTitles': titles});
      return true;
    } catch (e) {
      debugPrint('[LabTitle] no se otorgó el título: $e');
      return false;
    }
  }

  /// Aviso de que ganó el título.
  static void announce(BuildContext context) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
      content: Text('¡Ganaste el título $kLabTitleName! Lo puedes poner en tu perfil de Ohtli.'),
    ));
  }
}
