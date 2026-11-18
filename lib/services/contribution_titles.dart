import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'public_profiles.dart';

/// Títulos por aportar a los lugares de Ohtli. Los de enviar los da la app al momento; los de
/// aprobación los da el motor al aprobar (api/admin_places.py, mismos ids y textos).
class ContributionTitle {
  final String id;
  final String name;
  final String description;
  const ContributionTitle(this.id, this.name, this.description);
}

/// Donar una foto. Nemactia: dar, ofrecer.
const kTitleDonor = ContributionTitle('nemactia', 'Nemactia', 'Donó una foto de un lugar para que todos lo conozcan mejor.');

/// Su foto donada fue aprobada. Tlanemactli: el don, lo que se ofrece.
const kTitleDonorApproved =
    ContributionTitle('tlanemmaca', 'Tlanemmaca', 'Su foto donada ya es la imagen de un lugar en Ohtli.');

/// Reportar un lugar. Tlamatini: la persona que sabe.
const kTitleReporter = ContributionTitle('tlamatini', 'Tlamatini', 'Avisó qué faltaba o estaba mal en un lugar de Ohtli.');

/// Su reporte fue aprobado. Altepetl: el pueblo, la ciudad.
const kTitleReporterApproved = ContributionTitle('altepetl', 'Altepetl', 'Su reporte ayudó a corregir un lugar de la ciudad.');

/// Sugirió un lugar que no estaba y fue aprobado. Calpulli: el barrio, la casa grande.
const kTitleNewPlace = ContributionTitle('calpulli', 'Calpulli', 'Sumó a Ohtli un lugar que no estaba.');

const List<ContributionTitle> kContributionTitles = [
  kTitleDonor,
  kTitleDonorApproved,
  kTitleReporter,
  kTitleReporterApproved,
  kTitleNewPlace,
];

ContributionTitle? contributionTitleOf(String? id) {
  for (final t in kContributionTitles) {
    if (t.id == id) return t;
  }
  return null;
}

class ContributionTitles {
  ContributionTitles._();

  /// Da el título si aún no lo tiene (conserva «viajero», el de todas las cuentas). Devuelve true
  /// si se acaba de ganar. No lanza.
  static Future<bool> grant(String uid, ContributionTitle title) async {
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final current = (await ref.get()).data()?['possessedTitles'] as List?;
      if (current != null && current.contains(title.id)) return false;
      final titles = <String>[for (final t in current ?? const []) t.toString()];
      if (titles.isEmpty) titles.add('viajero');
      titles.add(title.id);
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
      debugPrint('[Títulos] no se otorgó ${title.id}: $e');
      return false;
    }
  }

  /// Superusuario: deja el catálogo `titles/{id}` al día con estos títulos.
  static Future<void> ensureCatalog() async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final t in kContributionTitles) {
        batch.set(FirebaseFirestore.instance.collection('titles').doc(t.id), {'name': t.name, 'description': t.description},
            SetOptions(merge: true));
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[Títulos] no se actualizó el catálogo: $e');
    }
  }
}
