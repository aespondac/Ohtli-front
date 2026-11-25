import 'package:flutter/material.dart';

import '../theme/colors.dart';
import 'trip_social_service.dart' show tapbackOf;

/// Cómo se presenta una notificación (en la lista y en el aviso flotante).
class NotificationLook {
  /// Quién la manda ("Ohtli" en las del sistema).
  final String sender;
  final String message;
  final IconData icon;
  final Color color;

  /// La manda la app, no una persona (se dibuja con el logo).
  final bool fromSystem;

  const NotificationLook({required this.sender, required this.message, required this.icon, required this.color, this.fromSystem = false});
}

/// Qué búsqueda de rutas es (para no repetir el mismo aviso): el punto de partida si no es
/// el genérico, o lo que se pidió. null si no hay nada que la distinga.
String? itineraryJobLabel(Map<String, dynamic> job) {
  final req = job['request'] is Map ? Map<String, dynamic>.from(job['request'] as Map) : const <String, dynamic>{};
  final origin = ((job['origin_name'] ?? req['origin_name']) as String?)?.trim() ?? '';
  if (origin.isNotEmpty && origin.toLowerCase() != 'ciudad de méxico') return 'desde $origin';
  var mood = (req['mood_text'] as String?)?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
  if (mood.isEmpty) return null;
  if (mood.length > 40) mood = '${mood.substring(0, 39).trimRight()}…';
  return 'para «$mood»';
}

/// Texto del aviso cuando termina una búsqueda de rutas con IA.
String itineraryJobMessage(Map<String, dynamic> job, {required bool failed}) {
  final label = itineraryJobLabel(job);
  if (failed) {
    return label == null ? 'No pudimos terminar tus rutas con IA. Intenta de nuevo.' : 'No pudimos terminar tus rutas $label. Intenta de nuevo.';
  }
  final options = ((job['result'] as Map?)?['options'] as List?)?.length ?? 3;
  return '¡Listo! Tienes $options rutas con IA${label == null ? '' : ' $label'} para elegir.';
}

/// Varios avisos iguales de rutas seguidos se muestran como uno solo.
String itineraryGroupedMessage(String type, int count) => type == 'itinerary_failed'
    ? 'No pudimos terminar $count búsquedas de rutas con IA. Intenta de nuevo.'
    : 'Terminaron $count búsquedas de rutas con IA: tienes propuestas para elegir.';

NotificationLook describeNotification(Map<String, dynamic> data) {
  final String type = (data['type'] as String?) ?? 'friend_request';
  final String sender = (data['senderName'] as String?) ?? 'Viajero Ohtli';
  final String status = (data['status'] as String?) ?? 'pending';
  final String tripTitle = (data['tripTitle'] as String?) ?? 'su itinerario';
  final bool isPlan = data['isPlan'] == true;

  switch (type) {
    case 'friend_request':
      return NotificationLook(
        sender: sender,
        icon: Icons.person_add_alt_1_rounded,
        color: OhtliColors.stormyTeal,
        message: status == 'pending'
            ? 'te envió una solicitud de amistad.'
            : status == 'accepted'
            ? 'y tú ahora son amigos.'
            : 'te envió una solicitud (rechazada).',
      );
    case 'new_publication':
      return NotificationLook(
        sender: sender,
        icon: Icons.auto_stories_rounded,
        color: OhtliColors.stormyTeal,
        message: 'publicó un nuevo ${isPlan ? "plan" : "viaje"}: "$tripTitle".',
      );
    case 'surprise_plan':
      return NotificationLook(
        sender: sender,
        icon: Icons.card_giftcard_rounded,
        color: OhtliColors.accent,
        message: 'te preparó un plan sorpresa: "$tripTitle".',
      );
    case 'co_author_added':
      return NotificationLook(
        sender: sender,
        icon: Icons.group_add_rounded,
        color: OhtliColors.accent,
        message: 'te agregó como coautor en su ${isPlan ? "plan" : "viaje"}: "$tripTitle".',
      );
    case 'trip_comment':
      final comment = (data['commentText'] as String?) ?? '';
      return NotificationLook(
        sender: sender,
        icon: Icons.chat_bubble_rounded,
        color: OhtliColors.stormyTeal,
        message: 'comentó en tu viaje "$tripTitle"${comment.isEmpty ? '.' : ': «$comment»'}',
      );
    case 'trip_reaction':
      final emoji = tapbackOf(data['reaction'] as String?)?.emoji ?? '❤️';
      return NotificationLook(
        sender: sender,
        icon: Icons.favorite_rounded,
        color: OhtliColors.accent,
        message: data['onComment'] == true ? 'reaccionó $emoji a tu mensaje en "$tripTitle".' : 'reaccionó $emoji a tu viaje "$tripTitle".',
      );
    case 'cheer':
      return NotificationLook(
        sender: sender,
        icon: Icons.celebration_rounded,
        color: OhtliColors.accent,
        message: data['tripId'] != null ? 'te felicitó por tu viaje "$tripTitle". 🎉' : 'te saludó. 👋',
      );
    case 'group_trip_invite':
      return NotificationLook(
        sender: sender,
        icon: Icons.groups_rounded,
        color: OhtliColors.stormyTeal,
        message: status == 'accepted'
            ? 'te invitó a planear "$tripTitle" (aceptaste).'
            : status == 'declined'
            ? 'te invitó a planear "$tripTitle" (no vas).'
            : 'te invitó a planear juntos "$tripTitle".',
      );
    case 'group_trip_accepted':
      return NotificationLook(
        sender: sender,
        icon: Icons.how_to_reg_rounded,
        color: OhtliColors.stormyTeal,
        message: 'se sumó a tu plan "$tripTitle".',
      );
    case 'group_trip_declined':
    case 'group_trip_left':
      final reason = (data['reason'] ?? '').toString().trim();
      final left = data['type'] == 'group_trip_left';
      return NotificationLook(
        sender: sender,
        icon: Icons.person_off_rounded,
        color: OhtliColors.subtleText,
        message: '${left ? 'se retiró de' : 'no podrá ir a'} "$tripTitle"${reason.isEmpty ? '.' : ': $reason.'}',
      );
    case 'place_photo_reviewed':
    case 'place_report_reviewed':
      final place = (data['poiName'] ?? 'el lugar').toString();
      final approved = data['approved'] == true;
      final photo = data['type'] == 'place_photo_reviewed';
      final reason = (data['reason'] ?? '').toString().trim();
      final titleName = (data['titleName'] ?? '').toString();
      return NotificationLook(
        sender: 'Ohtli',
        fromSystem: true,
        icon: photo ? Icons.volunteer_activism_rounded : Icons.flag_rounded,
        color: approved ? OhtliColors.stormyTeal : OhtliColors.subtleText,
        message: approved
            ? (photo ? 'Tu foto ya es la de $place. ¡Gracias por donarla!' : 'Corregimos $place con tu reporte. ¡Gracias!') +
                (titleName.isEmpty ? '' : ' Ganaste el título $titleName.')
            : (photo ? 'Esta vez no usamos tu foto de $place' : 'Revisamos tu reporte de $place y no hicimos cambios') +
                (reason.isEmpty ? '.' : ': $reason.'),
      );
    case 'saved_place_closed':
    case 'saved_place_reopened':
      final place = (data['poiName'] ?? 'Un lugar que guardaste').toString();
      final closed = data['type'] == 'saved_place_closed';
      return NotificationLook(
        sender: 'Ohtli',
        fromSystem: true,
        icon: closed ? Icons.block_rounded : Icons.storefront_rounded,
        color: closed ? OhtliColors.warningText : OhtliColors.stormyTeal,
        message: closed
            ? '$place, que tienes en Mis lugares, cerró definitivamente.'
            : '$place, que tienes en Mis lugares, volvió a abrir.',
      );
    case 'place_suggestion_approved':
      final titleName = (data['titleName'] ?? '').toString();
      return NotificationLook(
        sender: 'Ohtli',
        fromSystem: true,
        icon: Icons.add_location_alt_rounded,
        color: OhtliColors.stormyTeal,
        message: '${(data['poiName'] ?? 'El lugar que sugeriste').toString()} ya es parte de Ohtli.'
            '${titleName.isEmpty ? '' : ' Ganaste el título $titleName.'}',
      );
    case 'group_trip_remind_respond':
    case 'group_trip_remind_vote':
      return NotificationLook(
        sender: 'Ohtli',
        fromSystem: true,
        icon: Icons.alarm_rounded,
        color: OhtliColors.stormyTeal,
        message: data['type'] == 'group_trip_remind_vote'
            ? 'Queda 1 hora para votar la ruta de "$tripTitle".'
            : 'Queda 1 hora para responder la invitación a "$tripTitle".',
      );
    case 'group_trip_ready':
      return NotificationLook(
        sender: 'Ohtli',
        fromSystem: true,
        icon: Icons.how_to_vote_rounded,
        color: OhtliColors.accent,
        message: (data['message'] as String?) ?? 'Las rutas de "$tripTitle" están listas: vota por tu favorita.',
      );
    case 'group_trip_created':
      return NotificationLook(
        sender: 'Ohtli',
        fromSystem: true,
        icon: Icons.event_available_rounded,
        color: OhtliColors.stormyTeal,
        message: (data['message'] as String?) ?? 'El plan "$tripTitle" quedó listo: ya pueden editarlo juntos.',
      );
    case 'group_trip_cancelled':
      return NotificationLook(
        sender: 'Ohtli',
        fromSystem: true,
        icon: Icons.event_busy_rounded,
        color: OhtliColors.warning,
        message: (data['message'] as String?) ?? 'Se canceló el plan "$tripTitle": nadie aceptó a tiempo.',
      );
    case 'itinerary_ready':
      return NotificationLook(
        sender: 'Ohtli',
        fromSystem: true,
        icon: Icons.auto_awesome_rounded,
        color: OhtliColors.accent,
        message: (data['message'] as String?) ?? 'Tus rutas con IA están listas para elegir.',
      );
    case 'itinerary_failed':
      return NotificationLook(
        sender: 'Ohtli',
        fromSystem: true,
        icon: Icons.error_outline_rounded,
        color: OhtliColors.warning,
        message: (data['message'] as String?) ?? 'No pudimos terminar tus rutas con IA. Intenta de nuevo.',
      );
    default:
      return NotificationLook(sender: sender, icon: Icons.notifications_rounded, color: OhtliColors.stormyTeal, message: 'tiene algo para ti.');
  }
}
