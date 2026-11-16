import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../config/admin.dart' show isSuperUser;
import '../labs/lab_access.dart';
import '../labs/lab_title.dart';
import '../labs/labs_top_bar.dart';
import '../widgets/labs_invite_page.dart';
import 'user_private_data.dart';

/// Momentos en que Ohtli invita a la persona a participar en los estudios de Ohtli Labs.
enum LabsInviteMoment {
  /// Cerró el editor de su primer viaje armado con una opción elegida de la IA.
  aiTrip,

  /// Creó su primer plan con IA en grupo con amigos.
  aiGroup,
}

extension LabsInviteMomentX on LabsInviteMoment {
  /// Clave dentro de `labs_invite` en `users/{uid}/private/account`.
  String get key => switch (this) {
        LabsInviteMoment.aiTrip => 'ai_trip',
        LabsInviteMoment.aiGroup => 'ai_group',
      };
}

/// Invitación a Ohtli Labs: una vista a pantalla completa que se muestra UNA sola vez por
/// momento ([LabsInviteMoment]) y nunca más si la persona ya es tester o ya respondió algún
/// estudio. La marca vive en `users/{uid}/private/account.labs_invite` (no en el navegador),
/// así no se repite en otro dispositivo ni al borrar datos del sitio.
///
/// Aceptar hace lo mismo que el consentimiento de lab.ohtli.quest: crea `lab_members/{uid}`
/// con rol `tester` (las reglas solo permiten esa alta propia y sin correo ni nombre) y abre
/// los estudios abiertos en Labs.
class LabsInvite {
  LabsInvite._();

  static const String field = 'labs_invite';
  static const String acceptedKey = 'accepted';
  static const String doneKey = 'done';

  static bool _busy = false;

  /// Decide si toca mostrar la invitación con las marcas guardadas y el estado en Labs.
  static bool shouldShow(Map<String, dynamic>? flags, LabsInviteMoment moment,
      {required bool isLabParticipant, required bool answeredStudy}) {
    if (isLabParticipant || answeredStudy) return false;
    final f = flags ?? const {};
    if (f[acceptedKey] != null || f[doneKey] != null) return false;
    return f[moment.key] == null;
  }

  /// Es un viaje que salió de una opción elegida de rutas con IA ([saveOptionAsTrip]).
  static bool isAiTrip({String? recommendationJobId, List<String> recommendedPoiIds = const []}) =>
      (recommendationJobId != null && recommendationJobId.isNotEmpty) || recommendedPoiIds.isNotEmpty;

  /// Muestra la invitación sobre [navigator] si corresponde. No lanza: cualquier error de red o
  /// de permisos solo hace que esta vez no se muestre.
  static Future<void> maybeShow(NavigatorState navigator, LabsInviteMoment moment,
      {Duration delay = const Duration(milliseconds: 450)}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || isSuperUser(user) || _busy) return;
    _busy = true;
    try {
      final privRef = UserPrivateData.privateRef(user.uid);
      final priv = await privRef.get();
      final raw = priv.data()?[field];
      final flags = raw is Map ? Map<String, dynamic>.from(raw) : null;
      if (!shouldShow(flags, moment, isLabParticipant: false, answeredStudy: false)) return;

      final member = await LabAccess.memberDoc(user.uid).get();
      final answered = (await FirebaseFirestore.instance
              .collection('lab_responses')
              .where('uid', isEqualTo: user.uid)
              .limit(1)
              .get())
          .docs
          .isNotEmpty;
      if (member.exists || answered) {
        // Ya participa (o participó): no se le vuelve a invitar en ningún momento.
        if (answered) unawaited(LabTitle.grant(user.uid));
        await privRef.set({field: {doneKey: FieldValue.serverTimestamp()}}, SetOptions(merge: true));
        return;
      }

      // La marca va antes de mostrarla: si recarga o cierra la pestaña, no se repite.
      await privRef.set({field: {moment.key: FieldValue.serverTimestamp()}}, SetOptions(merge: true));
      await Future<void>.delayed(delay);
      if (!navigator.mounted) return;
      final accepted = await navigator.push<bool>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LabsInvitePage(moment: moment, onAccept: () => _accept(user)),
      ));
      if (accepted == true) {
        await privRef.set({field: {acceptedKey: FieldValue.serverTimestamp()}}, SetOptions(merge: true));
        openStudies();
      }
    } catch (e) {
      debugPrint('[LabsInvite] no se mostró la invitación: $e');
    } finally {
      _busy = false;
    }
  }

  /// Alta como tester (igual que el consentimiento de Labs). Si ya tenía rol, no lo toca: las
  /// reglas solo permiten crear el documento, así un miembro no queda degradado a tester.
  static Future<void> _accept(User user) async {
    final m = await LabAccess.memberDoc(user.uid).get();
    if (!m.exists) await LabAccess.joinAsTester(user);
  }

  /// Abre los estudios abiertos de Labs en otra pestaña (la sesión llega por SSO); si el
  /// navegador bloquea la ventana, en esta misma.
  static void openStudies() {
    if (!kIsWeb) return;
    final url = LabsTopBar.urlFor(LabsSection.participate);
    final opened = web.window.open(url, '_blank');
    if (opened == null) web.window.location.href = url;
  }
}
