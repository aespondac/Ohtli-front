import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/group_trip_service.dart';
import '../../theme/colors.dart';
import '../../widgets/group_trip_sheet.dart';
import '../../widgets/ohtli_service_icon.dart';
import '../../widgets/ohtli_ui.dart';
import 'trip_planner_page.dart';
import 'trip_viewer_page.dart';

/// Sala del plan con IA en grupo: quién va, en qué va (respuestas, rutas, votación) y el
/// viaje que salió.
class GroupTripPage extends StatefulWidget {
  final String groupId;
  const GroupTripPage({super.key, required this.groupId});

  @override
  State<GroupTripPage> createState() => _GroupTripPageState();
}

class _GroupTripPageState extends State<GroupTripPage> {
  late final Stream<GroupTrip?> _stream = GroupTripService.watch(widget.groupId);
  bool _busy = false;

  static const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  String _when(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final hh = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (day == today) return 'hoy a las $hh';
    if (day == today.add(const Duration(days: 1))) return 'mañana a las $hh';
    return 'el ${d.day} de ${_months[d.month - 1]} a las $hh';
  }

  Future<void> _run(Future<bool> Function() action, String failure) async {
    setState(() => _busy = true);
    final ok = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
  }

  void _openVoting(GroupTrip g) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripPlannerPage(groupTripId: g.id)));
  }

  void _openTrip(GroupTrip g) {
    final tripId = g.tripId;
    if (tripId == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripViewerPage(tripId: tripId, authorId: g.hostId)));
  }

  Widget _avatar(String name, String? photo, {double radius = 18}) => CircleAvatar(
        radius: radius,
        backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.15),
        backgroundImage: photo != null ? NetworkImage(photo) : null,
        child: photo == null
            ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.outfit(fontSize: radius * 0.75, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal))
            : null,
      );

  Widget _statusCard(GroupTrip g, String uid) {
    final isHost = uid == g.hostId;
    final mine = g.responseOf(uid);
    late final IconData icon;
    late final Color color;
    late final String title;
    late final String text;
    final actions = <Widget>[];

    switch (g.status) {
      case 'inviting':
        icon = Icons.hourglass_top_rounded;
        color = OhtliColors.cempasuchil;
        title = 'Esperando respuestas';
        text = g.respondBy != null
            ? 'Las rutas se arman cuando todos respondan o ${_when(g.respondBy!)}, con los gustos de quienes acepten.'
            : 'Las rutas se arman cuando todos respondan, con los gustos de quienes acepten.';
        if (!isHost && mine != 'accepted') {
          actions.add(OhtliPrimaryButton(
            label: mine == 'declined' ? 'Cambiar mi respuesta' : 'Responder',
            icon: Icons.how_to_reg_rounded,
            onPressed: () => openGroupTrip(context, g.id),
          ));
        }
        if (isHost) {
          actions.add(OhtliPrimaryButton(
            label: g.acceptedIds.isEmpty ? 'Esperando que alguien acepte' : 'Generar ya con ${g.acceptedIds.length + 1}',
            icon: Icons.auto_awesome_rounded,
            loading: _busy,
            onPressed: _busy || g.acceptedIds.isEmpty ? null : () => _run(() => GroupTripService.generate(g.id), 'No se pudieron generar las rutas. Intenta de nuevo.'),
          ));
        }
      case 'generating':
        icon = Icons.auto_awesome_rounded;
        color = OhtliColors.stormyTeal;
        title = 'Armando 3 rutas';
        text = g.generationError != null
            ? 'Hubo un problema al generar; lo intentamos de nuevo en unos minutos.'
            : 'Con los gustos de quienes aceptaron (sin mostrárselos a nadie) y las intenciones del grupo.';
      case 'voting':
        icon = Icons.how_to_vote_rounded;
        color = OhtliColors.cempasuchil;
        title = 'Votación abierta';
        final voted = g.voters.where(g.votes.containsKey).length;
        text = 'Votaron $voted de ${g.voters.length}.${g.voteBy != null ? ' Cierra ${_when(g.voteBy!)} o cuando voten todos.' : ''}';
        if (g.voters.contains(uid)) {
          actions.add(OhtliPrimaryButton(
            label: g.votes.containsKey(uid) ? 'Ver las rutas y mi voto' : 'Ver las rutas y votar',
            icon: Icons.alt_route_rounded,
            highlight: !g.votes.containsKey(uid),
            onPressed: () => _openVoting(g),
          ));
        }
        if (isHost) {
          actions.add(OhtliSecondaryButton(
            label: 'Cerrar la votación',
            onPressed: _busy ? null : () => _run(() => GroupTripService.close(g.id), 'No se pudo cerrar la votación. Intenta de nuevo.'),
          ));
        }
      case 'created':
        icon = Icons.event_available_rounded;
        color = OhtliColors.stormyTeal;
        title = '¡El plan quedó listo!';
        text = g.winner != null ? 'Ganó la opción ${g.winner! + 1}. Ya pueden editarlo juntos.' : 'Ya pueden editarlo juntos.';
        if (g.tripId != null && (isHost || mine == 'accepted')) {
          actions.add(OhtliPrimaryButton(label: 'Abrir el plan', icon: Icons.arrow_forward_rounded, onPressed: () => _openTrip(g)));
        }
      case 'cancelled':
        icon = Icons.event_busy_rounded;
        color = OhtliColors.xoconostle;
        title = 'Se canceló';
        text = g.cancelReason == 'generation_failed'
            ? 'No pudimos generar las rutas. Pueden intentarlo de nuevo desde el asistente.'
            : 'Nadie aceptó a tiempo.';
      default:
        icon = Icons.groups_rounded;
        color = OhtliColors.stormyTeal;
        title = 'Plan en grupo';
        text = '';
    }

    return OhtliSurface(
      radius: 22,
      padding: const EdgeInsets.all(18),
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OhtliServiceIcon(icon: icon, color: color, size: 44, soft: true),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx))),
              if (g.status == 'generating') const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: OhtliColors.stormyTeal)),
            ],
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(text, style: OhtliUi.body(size: 13.5)),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, children: actions),
          ],
        ],
      ),
    );
  }

  Widget _memberRow(GroupTrip g, String uid, {required bool host}) {
    final name = g.nameOf(uid);
    final photo = host ? g.hostPhoto : g.members[uid]?.photo;
    final answer = host ? 'host' : g.responseOf(uid);
    final (String label, Color color) = switch (answer) {
      'host' => ('Organiza', OhtliColors.stormyTeal),
      'accepted' => ('Va', OhtliColors.stormyTeal),
      'declined' => ('No va', OhtliColors.subtleText),
      _ => ('Sin responder', OhtliColors.cempasuchil),
    };
    final intention = g.intentions[uid];
    final voted = g.status == 'voting' && g.votes.containsKey(uid);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(name, photo),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
                if (intention != null && intention.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('«$intention»', style: GoogleFonts.inter(fontSize: 12.5, fontStyle: FontStyle.italic, color: OhtliColors.subtleText)),
                  ),
              ],
            ),
          ),
          if (voted) ...[
            const Icon(Icons.how_to_vote_rounded, size: 15, color: OhtliColors.cempasuchil),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: OhtliColors.stormyTeal),
        title: Text('Plan en grupo', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
      ),
      body: StreamBuilder<GroupTrip?>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('No tienes acceso a este plan.', style: OhtliUi.body())));
          }
          final g = snap.data;
          if (g == null) {
            return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Text(g.title, style: OhtliUi.title(size: 26)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (g.travelDate != null)
                        OhtliMetaPill(icon: Icons.event_rounded, label: '${g.travelDate!.day} de ${_months[g.travelDate!.month - 1]}'),
                      OhtliMetaPill(icon: Icons.groups_rounded, label: '${g.acceptedIds.length + 1} van'),
                      OhtliMetaPill(icon: Icons.auto_awesome_rounded, label: 'Plan con IA'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _statusCard(g, uid),
                  const SizedBox(height: 24),
                  Text('QUIÉNES VAN', style: OhtliUi.eyebrow(OhtliColors.subtleText)),
                  const SizedBox(height: 6),
                  OhtliSurface(
                    radius: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Column(
                      children: [
                        _memberRow(g, g.hostId, host: true),
                        for (final u in g.invitedIds) _memberRow(g, u, host: false),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
