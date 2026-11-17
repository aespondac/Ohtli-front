import 'package:cloud_firestore/cloud_firestore.dart';

import 'feedback_service.dart';
import 'place_feedback_service.dart';

/// Las tres secciones de la bandeja de administración.
enum AdminInboxSection {
  donations('donations', 'Donaciones'),
  reports('reports', 'Reportes'),
  feedback('feedback', 'Comentarios');

  const AdminInboxSection(this.key, this.label);

  /// Campo en `admin_settings/notifications` (y en functions/feedback.js).
  final String key;
  final String label;
}

/// Contadores de lo que espera revisión y si cada sección avisa por correo.
///
/// Los avisos por correo se guardan en `admin_settings/notifications`
/// (`{donations: bool, reports: bool, feedback: bool}`), que solo el superusuario lee y cambia;
/// las Cloud Functions lo consultan antes de mandar cada correo. Sin valor guardado, avisa.
class AdminInbox {
  AdminInbox._();

  static DocumentReference<Map<String, dynamic>> get _settings =>
      FirebaseFirestore.instance.collection('admin_settings').doc('notifications');

  /// Lee los interruptores; lo que no está guardado cuenta como encendido.
  static Map<AdminInboxSection, bool> emailFlagsOf(Map<String, dynamic>? data) => {
        for (final s in AdminInboxSection.values) s: data?[s.key] != false,
      };

  static Stream<Map<AdminInboxSection, bool>> watchEmailFlags() =>
      _settings.snapshots().map((d) => emailFlagsOf(d.data()));

  static Future<void> setEmail(AdminInboxSection section, bool on) =>
      _settings.set({section.key: on, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

  /// Cuántos esperan revisión en cada sección.
  static Stream<int> watchPending(AdminInboxSection section) => switch (section) {
        AdminInboxSection.donations => _placePending(kFeedbackPhoto),
        AdminInboxSection.reports => _placePending(kFeedbackReport),
        AdminInboxSection.feedback => FeedbackService.watchNewCount(),
      };

  static Stream<int> _placePending(String type) => FirebaseFirestore.instance
      .collection('place_feedback')
      .where('status', isEqualTo: kFeedbackPending)
      .where('type', isEqualTo: type)
      .snapshots()
      .map((q) => q.size);
}
