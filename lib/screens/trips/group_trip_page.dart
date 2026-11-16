import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/group_trip_service.dart';
import '../../services/trip_transfers.dart';
import '../../theme/colors.dart';
import '../../widgets/group_trip_sheet.dart';
import '../../widgets/osrm_map_widget.dart';
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

  Future<void> _run(Future<bool> Function() action, String failure) async {
    setState(() => _busy = true);
    final ok = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
  }

  Future<void> _leave(GroupTrip g) async {
    final reason = await askDeclineReason(context, leaving: true, hostName: g.hostName);
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await GroupTripService.respond(g, accept: false, reason: reason);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Te retiraste de «${g.title}». Le avisamos a ${g.hostName}.')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo registrar tu salida. Intenta de nuevo.')));
    }
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

  /// Burbuja de una persona con su estado en la votación: ✓ votó, reloj pendiente.
  Widget _voteBubble(GroupTrip g, String uid, {double radius = 18}) {
    final voted = g.votes.containsKey(uid);
    final photo = uid == g.hostId ? g.hostPhoto : g.members[uid]?.photo;
    final badge = voted ? OhtliColors.stormyTeal : OhtliColors.subtleText;
    return Tooltip(
      message: '${g.nameOf(uid)} · ${voted ? 'ya votó' : 'falta su voto'}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: voted ? OhtliColors.stormyTeal : OhtliColors.cardBorder, width: 2),
            ),
            child: Opacity(opacity: voted ? 1 : 0.55, child: _avatar(g.nameOf(uid), photo, radius: radius)),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(color: badge, shape: BoxShape.circle, border: Border.all(color: OhtliColors.cardBg, width: 2)),
              child: Icon(voted ? Icons.check_rounded : Icons.schedule_rounded, size: 11, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

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
        color = OhtliColors.accent;
        title = 'Esperando respuestas';
        text = 'Las rutas se arman cuando todos respondan o al terminar el tiempo, con los gustos de quienes acepten.';
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
        color = OhtliColors.accent;
        title = 'Votación abierta';
        final voted = g.voters.where(g.votes.containsKey).length;
        text = 'Votaron $voted de ${g.voters.length}. Se cierra cuando voten todos o al terminar el tiempo'
            '${isHost ? '; tú, como organizador, puedes cerrarla antes.' : '.'}';
        if (g.voters.contains(uid)) {
          actions.add(OhtliPrimaryButton(
            label: g.votes.containsKey(uid) ? 'Ver las rutas y mi voto' : 'Ver las rutas y votar',
            icon: g.votes.containsKey(uid) ? Icons.check_rounded : Icons.how_to_vote_rounded,
            highlight: !g.votes.containsKey(uid),
            onPressed: () => _openVoting(g),
          ));
        }
        // Solo quien creó el plan puede cerrar antes de tiempo (el motor también lo exige)
        if (isHost) {
          actions.add(OhtliSecondaryButton(
            label: 'Cerrar la votación ya',
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
        color = OhtliColors.warning;
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

    if (!isHost && mine == 'accepted' && g.status != 'cancelled') {
      actions.add(OhtliSecondaryButton(label: 'Ya no puedo ir', onPressed: _busy ? null : () => _leave(g)));
    }
    final deadline = switch (g.status) {
      'inviting' => g.respondBy,
      'voting' => g.voteBy,
      _ => null,
    };

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
          if (deadline != null) ...[
            const SizedBox(height: 14),
            _Countdown(
              until: deadline,
              label: g.status == 'voting' ? 'La votación cierra en' : 'Tiempo para responder',
              endedLabel: g.status == 'voting' ? 'Cerrando la votación…' : 'Armando las rutas…',
              color: color,
            ),
          ],
          if (text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(text, style: OhtliUi.body(size: 13.5)),
          ],
          if (g.status == 'voting' && g.voters.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final u in g.voters) _voteBubble(g, u, radius: 17)],
            ),
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
      _ => ('Sin responder', OhtliColors.accent),
    };
    final intention = g.intentions[uid];
    final reason = answer == 'declined' ? g.declineReasons[uid] : null;
    final votes = g.status == 'voting' && g.voters.contains(uid);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          votes ? _voteBubble(g, uid) : _avatar(name, photo),
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
                if (reason != null && reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(reason, style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText)),
                  ),
                if (votes)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(g.votes.containsKey(uid) ? 'Ya votó' : 'Falta su voto',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: g.votes.containsKey(uid) ? OhtliColors.stormyTeal : OhtliColors.subtleText)),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
        ],
      ),
    );
  }

  static Map<String, dynamic>? _point(Object? raw, String name) {
    if (raw is! Map) return null;
    final lat = raw['lat'] ?? raw['latitude'];
    final lng = raw['lng'] ?? raw['longitude'];
    if (lat is! num || lng is! num) return null;
    return {'name': name, 'lat': lat.toDouble(), 'lng': lng.toDouble()};
  }

  /// Lo que pidió el organizador: de dónde a dónde, cómo se mueven, presupuesto o lugares y la
  /// idea del día, con un minimapa del inicio y el fin.
  Widget _planDetails(GroupTrip g) {
    final p = g.params;
    final originName = (p['origin_name'] ?? '').toString().trim();
    final start = _point(p['origin'], originName.isEmpty ? 'Punto de partida' : originName);
    final topology = (p['topology'] ?? '').toString();
    final destName = (p['destination_name'] ?? '').toString().trim();
    var end = topology == 'anillo' ? start : _point(p['destination'], destName.isEmpty ? 'Punto final' : destName);
    if (end != null && start != null && end['lat'] == start['lat'] && end['lng'] == start['lng'] && topology != 'anillo') {
      end = null; // ruta abierta sin final fijo: termina en la última parada
    }
    final mode = plannerModeOf(p['transport_mode']?.toString());
    final limitByPlaces = p['limit_by'] == 'places';
    final budget = (p['budget'] as num?)?.round();
    final places = (p['max_places'] as num?)?.toInt();
    final saving = p['budget_strategy'] == 'ahorro';
    final mood = (p['mood_text'] ?? '').toString().trim();

    Widget fact(IconData icon, String title, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: OhtliColors.stormyTeal),
              const SizedBox(width: 12),
              SizedBox(
                width: 92,
                child: Text(title, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
              ),
              Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: OhtliColors.onyx))),
            ],
          ),
        );

    final facts = Column(
      children: [
        fact(Icons.trip_origin_rounded, 'Inicio', start?['name'] as String? ?? 'Por definir'),
        fact(
          Icons.flag_rounded,
          'Fin',
          topology == 'anillo'
              ? 'Regresan al punto de inicio'
              : (end != null ? end['name'] as String : 'En la última parada'),
        ),
        fact(mode.icon, 'Cómo se mueven', mode.label),
        if (limitByPlaces && places != null)
          fact(Icons.place_outlined, 'Lugares', '$places paradas')
        else if (budget != null)
          fact(Icons.payments_outlined, 'Presupuesto', '\$$budget MXN por persona${saving ? ' · modo ahorro' : ''}'),
        if (mood.isNotEmpty) fact(Icons.edit_note_rounded, 'La idea', mood.replaceAll('\nIntereses:', ' · Intereses:')),
      ],
    );

    final map = start == null
        ? null
        : ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: OsrmMapWidget(
              stops: const [],
              startPoint: start,
              endPoint: end,
              height: 190,
              compact: true,
              isDark: OhtliSettings.instance.isDarkMode,
              modeIcon: mode.icon,
              modeLabel: mode.label,
              googleTravelMode: mode.googleTravelMode,
            ),
          );

    return OhtliSurface(
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(builder: (context, c) {
        if (map == null) return facts;
        if (c.maxWidth < 560) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [map, const SizedBox(height: 10), facts]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Padding(padding: const EdgeInsets.only(left: 4, right: 8), child: facts)),
            SizedBox(width: 260, child: map),
          ],
        );
      }),
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
                  if (g.params.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('EL PLAN', style: OhtliUi.eyebrow(OhtliColors.subtleText)),
                    const SizedBox(height: 6),
                    _planDetails(g),
                  ],
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

/// Cuenta regresiva en vivo hasta [until] (días, horas, minutos y segundos).
class _Countdown extends StatefulWidget {
  const _Countdown({required this.until, required this.label, required this.endedLabel, required this.color});
  final DateTime until;
  final String label;
  final String endedLabel;
  final Color color;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.until.difference(DateTime.now());
    if (left.isNegative) {
      _timer?.cancel();
      return Text(widget.endedLabel, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: widget.color));
    }
    final parts = <(int, String)>[
      if (left.inDays > 0) (left.inDays, 'd'),
      (left.inHours % 24, 'h'),
      (left.inMinutes % 60, 'min'),
      if (left.inDays == 0) (left.inSeconds % 60, 's'),
    ];
    Widget unit((int, String) p) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
          child: Text.rich(TextSpan(children: [
            TextSpan(
              text: p.$1.toString().padLeft(2, '0'),
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: OhtliColors.onyx,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            TextSpan(text: ' ${p.$2}', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: OhtliColors.subtleText)),
          ])),
        );
    return Semantics(
      label: '${widget.label} ${parts.map((p) => '${p.$1} ${p.$2}').join(' ')}',
      child: ExcludeSemantics(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            Text(widget.label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
            const SizedBox(width: 2),
            for (final p in parts) unit(p),
          ],
        ),
      ),
    );
  }
}
