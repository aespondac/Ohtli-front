import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/trips/trip_screens.dart' deferred as trips;
import '../services/notification_text.dart';
import '../theme/colors.dart';
import 'deferred_view.dart';
import 'ohtli_ui.dart';

/// Pide cambiar de pestaña desde cualquier pantalla (HomePage la escucha).
/// Índices de HomePage: 0 Explorar, 1 Mis viajes, 2 Perfil, 3 Amigos, 5 Lugares, 6 Notificaciones.
class OhtliAlerts {
  OhtliAlerts._();
  static final ValueNotifier<int?> requestedTab = ValueNotifier<int?>(null);

  /// Cierra lo que esté encima (paneles, pantallas empujadas) y va a la pestaña.
  static void openTab(BuildContext context, int index) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    requestedTab.value = null;
    requestedTab.value = index;
  }
}

/// ¿El trabajo de IA ya tiene propuestas para elegir? (mismo criterio que Mis viajes)
bool itineraryJobReady(Map<String, dynamic> data) {
  final status = (data['status'] ?? '').toString();
  final res = data['result'] is Map ? Map<String, dynamic>.from(data['result'] as Map) : const <String, dynamic>{};
  final options = (res['options'] as List<dynamic>?) ?? const [];
  final chosen = data['created_trip_id'] != null || status == 'chosen' || status == 'dismissed';
  return !chosen && options.isNotEmpty;
}

bool itineraryJobFailed(Map<String, dynamic> data) {
  final status = (data['status'] ?? '').toString();
  return status == 'failed' || status == 'error';
}

/// Avisos flotantes en vivo mientras usas la app:
/// - cada notificación nueva (solicitudes, reacciones, comentarios, felicitaciones…);
/// - cuando tus rutas con IA terminan de procesarse (o fallan), que además quedan en la campana.
/// Lo que ya existía al abrir la app no se anuncia.
class OhtliLiveAlerts extends StatefulWidget {
  final String uid;
  final Widget child;

  const OhtliLiveAlerts({super.key, required this.uid, required this.child});

  @override
  State<OhtliLiveAlerts> createState() => _OhtliLiveAlertsState();
}

class _AlertItem {
  final String id;
  final Map<String, dynamic> data;
  _AlertItem(this.id, this.data);
}

class _OhtliLiveAlertsState extends State<OhtliLiveAlerts> {
  StreamSubscription? _notifSub;
  StreamSubscription? _jobsSub;
  bool _notifBaselined = false;
  Set<String>? _jobsDone;
  final List<_AlertItem> _visible = [];
  final Map<String, Timer> _timers = {};

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant OhtliLiveAlerts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _cancel();
      _notifBaselined = false;
      _jobsDone = null;
      _listen();
    }
  }

  @override
  void dispose() {
    _cancel();
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  void _cancel() {
    _notifSub?.cancel();
    _jobsSub?.cancel();
  }

  void _listen() {
    final db = FirebaseFirestore.instance;
    final notifications = db.collection('users').doc(widget.uid).collection('notifications');

    _notifSub = notifications.orderBy('timestamp', descending: true).limit(15).snapshots().listen((snap) {
      if (!_notifBaselined) {
        _notifBaselined = true;
        return;
      }
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null || data['read'] == true) continue;
        // Planes sorpresa: solo cuando ya se pueden abrir.
        final ts = data['timestamp'];
        if (data['type'] == 'surprise_plan' && ts is Timestamp && DateTime.now().isBefore(ts.toDate())) continue;
        _show(_AlertItem(change.doc.id, data));
      }
    }, onError: (e) => debugPrint('[Avisos] notificaciones: $e'));

    _jobsSub = db.collection('itinerary_jobs').where('user_id', isEqualTo: widget.uid).snapshots().listen((snap) {
      final done = <String>{
        for (final d in snap.docs)
          if (itineraryJobReady(d.data()) || itineraryJobFailed(d.data())) d.id,
      };
      final before = _jobsDone;
      _jobsDone = done;
      if (before == null) return; // Punto de partida: no se anuncia lo que ya estaba listo.
      for (final d in snap.docs) {
        if (!done.contains(d.id) || before.contains(d.id)) continue;
        final data = d.data();
        final failed = itineraryJobFailed(data);
        final origin = (data['origin_name'] as String?)?.trim();
        final options = ((data['result'] as Map?)?['options'] as List?)?.length ?? 3;
        // Queda en la campana; el aviso flotante llega por el escucha de notificaciones.
        notifications
            .doc('itinerary_${d.id}')
            .set({
              'type': failed ? 'itinerary_failed' : 'itinerary_ready',
              'job_id': d.id,
              'message': failed
                  ? 'No pudimos terminar tus rutas con IA. Intenta de nuevo.'
                  : '¡Listo! Tienes $options rutas con IA${origin != null && origin.isNotEmpty ? ' desde $origin' : ''} para elegir.',
              'read': false,
              'timestamp': FieldValue.serverTimestamp(),
            })
            .catchError((e) => debugPrint('[Avisos] trabajo de IA: $e'));
      }
    }, onError: (e) => debugPrint('[Avisos] trabajos de IA: $e'));
  }

  void _show(_AlertItem item) {
    if (!mounted || _visible.any((v) => v.id == item.id)) return;
    setState(() {
      _visible.insert(0, item);
      while (_visible.length > 3) {
        _timers.remove(_visible.removeLast().id)?.cancel();
      }
    });
    _timers[item.id] = Timer(const Duration(seconds: 7), () => _dismiss(item.id));
  }

  void _dismiss(String id) {
    _timers.remove(id)?.cancel();
    if (mounted) setState(() => _visible.removeWhere((v) => v.id == id));
  }

  void _open(_AlertItem item) {
    _dismiss(item.id);
    final data = item.data;
    final type = data['type'] as String?;
    FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('notifications').doc(item.id).update({'read': true}).catchError((_) {});
    final tripId = data['tripId'] as String?;
    if (type == 'itinerary_ready' || type == 'itinerary_failed') {
      OhtliAlerts.openTab(context, 1);
    } else if (tripId != null) {
      final owner =
          (data['tripOwnerId'] as String?) ??
          ((type == 'new_publication' || type == 'surprise_plan') ? data['senderId'] as String? : widget.uid) ??
          widget.uid;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DeferredView(
            load: trips.loadLibrary,
            builder: (_) => trips.TripViewerPage(tripId: tripId, authorId: owner),
          ),
        ),
      );
    } else {
      OhtliAlerts.openTab(context, 6);
    }
  }

  String _ctaFor(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'friend_request':
        return data['status'] == 'pending' ? 'Responder' : 'Ver';
      case 'trip_comment':
        return 'Responder';
      case 'surprise_plan':
        return 'Abrir sorpresa';
      case 'itinerary_ready':
        return 'Ver propuestas';
      case 'itinerary_failed':
        return 'Intentar de nuevo';
      default:
        return data['tripId'] != null ? 'Ver viaje' : 'Ver';
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: MediaQuery.of(context).padding.top + (isMobile ? 8 : 18),
          right: isMobile ? 12 : 22,
          left: isMobile ? 12 : null,
          child: SizedBox(
            width: isMobile ? null : 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in _visible)
                  _Toast(
                    key: ValueKey(item.id),
                    look: describeNotification(item.data),
                    photo: item.data['senderPhoto'] as String?,
                    cta: _ctaFor(item.data),
                    onOpen: () => _open(item),
                    onClose: () => _dismiss(item.id),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Toast extends StatefulWidget {
  final NotificationLook look;
  final String? photo;
  final String cta;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  const _Toast({super.key, required this.look, required this.photo, required this.cta, required this.onOpen, required this.onClose});

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    final initials = look.sender.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

    final Widget avatar = look.fromSystem
        ? Container(
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: look.color, shape: BoxShape.circle),
            child: SvgPicture.asset('assets/icon_isologo.svg', colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
          )
        : Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: OhtliColors.stormyTeal),
                child: ClipOval(
                  child: widget.photo != null && widget.photo!.isNotEmpty
                      ? Image.network(
                          widget.photo!,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Center(
                            child: Text(
                              initials,
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            initials,
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ),
                ),
              ),
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    color: look.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: OhtliColors.cardBg, width: 2),
                  ),
                  child: Icon(look.icon, size: 10, color: Colors.white),
                ),
              ),
            ],
          );

    return FadeTransition(
      opacity: _c,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -0.35), end: Offset.zero).animate(curved),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Semantics(
            liveRegion: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: OhtliUi.softShadow(color: look.color, raised: true),
              ),
              child: Material(
                color: OhtliColors.cardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(color: look.color.withValues(alpha: 0.35)),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onOpen,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        avatar,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  style: GoogleFonts.inter(fontSize: 13.5, color: OhtliColors.onyx.withValues(alpha: 0.82), height: 1.4),
                                  children: [
                                    if (!look.fromSystem)
                                      TextSpan(
                                        text: '${look.sender} ',
                                        style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 14.5, color: OhtliColors.onyx),
                                      ),
                                    TextSpan(text: look.message),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              OhtliPrimaryButton(compact: true, highlight: look.fromSystem, label: widget.cta, onPressed: widget.onOpen),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar aviso',
                          icon: Icon(Icons.close_rounded, size: 18, color: OhtliColors.subtleText),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
