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
        color: OhtliColors.xoconostle,
        message: 'te preparó un plan sorpresa: "$tripTitle".',
      );
    case 'co_author_added':
      return NotificationLook(
        sender: sender,
        icon: Icons.group_add_rounded,
        color: OhtliColors.cempasuchil,
        message: 'te agregó como coautor en su ${isPlan ? "plan" : "viaje"}: "$tripTitle".',
      );
    case 'trip_comment':
      final comment = (data['commentText'] as String?) ?? '';
      return NotificationLook(
        sender: sender,
        icon: Icons.chat_bubble_rounded,
        color: const Color(0xFF3F7CAC),
        message: 'comentó en tu viaje "$tripTitle"${comment.isEmpty ? '.' : ': «$comment»'}',
      );
    case 'trip_reaction':
      final emoji = tapbackOf(data['reaction'] as String?)?.emoji ?? '❤️';
      return NotificationLook(
        sender: sender,
        icon: Icons.favorite_rounded,
        color: const Color(0xFFD64545),
        message: data['onComment'] == true ? 'reaccionó $emoji a tu mensaje en "$tripTitle".' : 'reaccionó $emoji a tu viaje "$tripTitle".',
      );
    case 'cheer':
      return NotificationLook(
        sender: sender,
        icon: Icons.celebration_rounded,
        color: OhtliColors.cempasuchil,
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
      return NotificationLook(
        sender: sender,
        icon: Icons.person_off_rounded,
        color: OhtliColors.subtleText,
        message: 'no podrá ir a "$tripTitle".',
      );
    case 'group_trip_ready':
      return NotificationLook(
        sender: 'Ohtli',
        fromSystem: true,
        icon: Icons.how_to_vote_rounded,
        color: OhtliColors.cempasuchil,
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
        color: OhtliColors.xoconostle,
        message: (data['message'] as String?) ?? 'Se canceló el plan "$tripTitle": nadie aceptó a tiempo.',
      );
    case 'itinerary_ready':
      return NotificationLook(
        sender: 'Ohtli',
        fromSystem: true,
        icon: Icons.auto_awesome_rounded,
        color: OhtliColors.cempasuchil,
        message: (data['message'] as String?) ?? 'Tus rutas con IA están listas para elegir.',
      );
    case 'itinerary_failed':
      return NotificationLook(
        sender: 'Ohtli',
        fromSystem: true,
        icon: Icons.error_outline_rounded,
        color: OhtliColors.xoconostle,
        message: (data['message'] as String?) ?? 'No pudimos terminar tus rutas con IA. Intenta de nuevo.',
      );
    default:
      return NotificationLook(sender: sender, icon: Icons.notifications_rounded, color: OhtliColors.stormyTeal, message: 'tiene algo para ti.');
  }
}
