import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/trips/trip_screens.dart' deferred as trips;
import '../services/group_trip_service.dart';
import '../theme/colors.dart';
import '../utils/friendly_errors.dart';
import 'deferred_view.dart';
import 'ohtli_ui.dart';

/// Ideas rápidas para la intención de quien se suma a un plan con IA.
const List<String> kIntentionIdeas = [
  'Cafés y librerías',
  'Museos y arte',
  'Comida callejera',
  'Parques y naturaleza',
  'Mercados',
  'Vida nocturna',
];

/// Razones rápidas para no ir a un plan en grupo.
const List<String> kDeclineReasons = [
  'Tengo otro compromiso',
  'No me queda la fecha',
  'Se sale de mi presupuesto',
  'No me late el plan',
  'Me siento mal',
];

/// Pide la razón para no ir (al rechazar la invitación o al retirarse). null si se cancela.
Future<String?> askDeclineReason(BuildContext context, {required bool leaving, required String hostName}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DeclineReasonSheet(leaving: leaving, hostName: hostName),
  );
}

class _DeclineReasonSheet extends StatefulWidget {
  const _DeclineReasonSheet({required this.leaving, required this.hostName});
  final bool leaving;
  final String hostName;

  @override
  State<_DeclineReasonSheet> createState() => _DeclineReasonSheetState();
}

class _DeclineReasonSheetState extends State<_DeclineReasonSheet> {
  final TextEditingController _other = TextEditingController();
  String? _picked;

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String get _reason {
    final extra = _other.text.trim();
    if (_picked == null) return extra;
    return extra.isEmpty ? _picked! : '$_picked. $extra';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: OhtliColors.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: OhtliColors.cardBorder, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 18),
                Text(widget.leaving ? '¿Por qué te retiras?' : '¿Por qué no puedes ir?',
                    style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                const SizedBox(height: 6),
                Text(
                  widget.leaving
                      ? 'Le avisamos a ${widget.hostName} y al grupo. Tu voto y tus gustos dejan de contar.'
                      : 'Le avisamos a ${widget.hostName} y al grupo con esta razón.',
                  style: OhtliUi.body(size: 13.5),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in kDeclineReasons)
                      OhtliChoiceChip(
                        label: r,
                        selected: _picked == r,
                        onTap: () => setState(() => _picked = _picked == r ? null : r),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _other,
                  maxLength: 140,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _picked == null ? 'U otra razón' : 'Algo más (opcional)',
                    filled: true,
                    fillColor: OhtliColors.cloudDancer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OhtliSecondaryButton(label: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
                    OhtliPrimaryButton(
                      label: widget.leaving ? 'Retirarme' : 'Enviar',
                      icon: Icons.person_off_rounded,
                      onPressed: _reason.isEmpty ? null : () => Navigator.of(context).pop(_reason),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Abre lo que toca de una solicitud de viaje en grupo: responder la invitación o, si ya
/// existe el viaje y eres parte, el viaje.
Future<void> openGroupTrip(BuildContext context, String groupId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  GroupTrip? g;
  try {
    g = await GroupTripService.get(groupId);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo abrir la invitación.'))));
    }
    return;
  }
  if (!context.mounted) return;
  if (g == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Esta invitación ya no existe.')));
    return;
  }
  final joined = uid == g.hostId || g.responseOf(uid) == 'accepted';
  if (joined && g.tripId != null) {
    openGroupTripTrip(context, g);
    return;
  }
  if (joined && !g.isManual) {
    openGroupTripLobby(context, g.id);
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => GroupInviteSheet(groupId: groupId),
  );
}

/// Sala del plan con IA en grupo (respuestas, rutas y votación).
void openGroupTripLobby(BuildContext context, String groupId) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => DeferredView(
      load: trips.loadLibrary,
      builder: (_) => trips.GroupTripPage(groupId: groupId),
    ),
  ));
}

void openGroupTripTrip(BuildContext context, GroupTrip g) {
  final tripId = g.tripId;
  if (tripId == null) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => DeferredView(
      load: trips.loadLibrary,
      builder: (_) => trips.TripViewerPage(tripId: tripId, authorId: g.hostId),
    ),
  ));
}

/// Hoja para responder una invitación a planear en grupo.
class GroupInviteSheet extends StatefulWidget {
  final String groupId;
  const GroupInviteSheet({super.key, required this.groupId});

  @override
  State<GroupInviteSheet> createState() => _GroupInviteSheetState();
}

class _GroupInviteSheetState extends State<GroupInviteSheet> {
  final TextEditingController _intention = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _intention.dispose();
    super.dispose();
  }

  Future<void> _respond(GroupTrip g, bool accept) async {
    String reason = '';
    if (!accept) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final r = await askDeclineReason(context, leaving: g.responseOf(uid) == 'accepted', hostName: g.hostName);
      if (r == null || !mounted) return;
      reason = r;
    }
    setState(() => _sending = true);
    try {
      await GroupTripService.respond(g, accept: accept, intention: _intention.text, reason: reason);
      if (!mounted) return;
      final nav = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      nav.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(accept
            ? (g.isManual ? 'Te sumaste a «${g.title}». Ya puedes editarlo.' : 'Te sumaste. Te avisamos cuando estén las rutas para votar.')
            : 'Le avisamos a ${g.hostName} que no vas.'),
      ));
      if (accept && g.isManual && g.tripId != null) openGroupTripTrip(nav.context, g);
      if (accept && !g.isManual) openGroupTripLobby(nav.context, g.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo enviar tu respuesta.'))));
    }
  }

  String _date(DateTime d) {
    const months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    return '${d.day} de ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: OhtliColors.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: StreamBuilder<GroupTrip?>(
            stream: GroupTripService.watch(widget.groupId),
            builder: (context, snap) {
              final g = snap.data;
              if (g == null) {
                return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal)));
              }
              final answer = g.responseOf(uid);
              final accepted = g.acceptedIds;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: OhtliColors.cardBorder, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.15),
                          backgroundImage: g.hostPhoto != null ? NetworkImage(g.hostPhoto!) : null,
                          child: g.hostPhoto == null
                              ? Text(g.hostName.isNotEmpty ? g.hostName[0].toUpperCase() : '?',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal))
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            g.isManual ? '${g.hostName} te invita a planear juntos' : '${g.hostName} te invita a un plan con IA',
                            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(g.title, style: OhtliUi.title(size: 22)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (g.travelDate != null) OhtliMetaPill(icon: Icons.event_rounded, label: _date(g.travelDate!)),
                        OhtliMetaPill(icon: Icons.groups_rounded, label: '${accepted.length + 1} de ${g.invitedIds.length + 1} van'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Quiénes ya van: el organizador y quienes aceptaron
                    _GoingAvatars(group: g, uids: [g.hostId, ...accepted]),
                    if (answer != 'pending') ...[
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Icon(answer == 'accepted' ? Icons.check_circle_rounded : Icons.cancel_rounded,
                              size: 18, color: answer == 'accepted' ? OhtliColors.stormyTeal : OhtliColors.subtleText),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(answer == 'accepted' ? 'Ya aceptaste.' : 'Dijiste que no puedes ir. Si cambias de idea, acepta abajo.',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
                          ),
                        ],
                      ),
                    ],
                    if (!g.isManual && answer != 'accepted') ...[
                      const SizedBox(height: 20),
                      Text('TU INTENCIÓN (OPCIONAL)', style: OhtliUi.eyebrow(OhtliColors.subtleText)),
                      const SizedBox(height: 8),
                      Text('Se suma a la de ${g.hostName} sin cambiarla.', style: OhtliUi.body(size: 12.5)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final idea in kIntentionIdeas)
                            OhtliChoiceChip(
                              label: idea,
                              selected: _intention.text == idea,
                              onTap: () => setState(() => _intention.text = _intention.text == idea ? '' : idea),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _intention,
                        maxLength: 200,
                        maxLines: 2,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '¿Qué te gustaría hacer ese día?',
                          filled: true,
                          fillColor: OhtliColors.cloudDancer,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (answer == 'accepted')
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OhtliSecondaryButton(label: 'Ya no puedo ir', onPressed: _sending ? null : () => _respond(g, false)),
                          g.tripId != null
                            ? OhtliPrimaryButton(
                                label: 'Abrir el plan',
                                icon: Icons.arrow_forward_rounded,
                                onPressed: () {
                                  final nav = Navigator.of(context);
                                  nav.pop();
                                  openGroupTripTrip(nav.context, g);
                                },
                              )
                            : OhtliPrimaryButton(label: 'Listo', onPressed: () => Navigator.of(context).pop()),
                        ],
                      )
                    else
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (answer == 'pending')
                            OhtliSecondaryButton(label: 'No puedo', onPressed: _sending ? null : () => _respond(g, false)),
                          OhtliPrimaryButton(
                            label: 'Aceptar',
                            icon: Icons.check_rounded,
                            loading: _sending,
                            onPressed: _sending ? null : () => _respond(g, true),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}


/// Fotos encimadas de quienes ya van al plan, con sus nombres al lado.
class _GoingAvatars extends StatelessWidget {
  final GroupTrip group;
  final List<String> uids;

  const _GoingAvatars({required this.group, required this.uids});

  static const int _maxShown = 6;
  static const double _radius = 18;
  static const double _overlap = 12;

  String _firstName(String uid) {
    final name = group.nameOf(uid).trim();
    return name.isEmpty ? 'Viajero Ohtli' : name.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final shown = uids.take(_maxShown).toList();
    final extra = uids.length - shown.length;
    final names = uids.map(_firstName).toList();
    final caption = switch (names.length) {
      1 => 'Va ${names[0]}',
      2 => 'Van ${names[0]} y ${names[1]}',
      _ => 'Van ${names[0]}, ${names[1]} y ${names.length - 2} más',
    };
    final count = shown.length + (extra > 0 ? 1 : 0);
    final step = _radius * 2 - _overlap;
    return Semantics(
      label: caption,
      child: Row(
        children: [
          SizedBox(
            width: _radius * 2 + step * (count - 1),
            height: _radius * 2,
            child: Stack(
              children: [
                for (int i = 0; i < shown.length; i++)
                  Positioned(left: step * i, child: _avatar(shown[i])),
                if (extra > 0)
                  Positioned(
                    left: step * shown.length,
                    child: _ring(
                      CircleAvatar(
                        radius: _radius - 2,
                        backgroundColor: OhtliColors.cardBorder,
                        child: Text('+$extra',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ExcludeSemantics(
              child: Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(Widget child) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: OhtliColors.cardBg, shape: BoxShape.circle),
        child: child,
      );

  Widget _avatar(String uid) {
    final photo = uid == group.hostId ? group.hostPhoto : group.members[uid]?.photo;
    final name = group.nameOf(uid);
    return _ring(
      CircleAvatar(
        radius: _radius - 2,
        backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.15),
        backgroundImage: photo != null ? NetworkImage(photo) : null,
        child: photo == null
            ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: OhtliColors.stormyTeal))
            : null,
      ),
    );
  }
}
