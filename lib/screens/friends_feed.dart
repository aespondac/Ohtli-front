import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/trip_model.dart';
import '../theme/cdmx_photos.dart';
import '../theme/colors.dart';
import '../widgets/deferred_view.dart';
import '../widgets/ohtli_ui.dart';
import '../widgets/trip_polaroid.dart';
import 'trips/trip_screens.dart' deferred as trips;

/// Felicita a alguien (por un viaje) o lo saluda: le llega como notificación de tipo «cheer».
/// El id es fijo por remitente y viaje, así que no se repite; si ya existía, las reglas
/// no dejan sobrescribirla y se ignora.
Future<void> sendCheer({required String toUserId, String? tripId, String? tripTitle, String? tripOwnerId}) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null || me.uid == toUserId) return;
  try {
    await FirebaseFirestore.instance.collection('users').doc(toUserId).collection('notifications').doc('cheer_${me.uid}_${tripId ?? 'hola'}').set({
      'type': 'cheer',
      'senderId': me.uid,
      'senderName': me.displayName ?? 'Un viajero',
      'senderPhoto': me.photoURL,
      if (tripId != null) ...{'tripId': tripId, 'tripTitle': tripTitle ?? '', 'tripOwnerId': tripOwnerId ?? toUserId},
      'status': 'sent',
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    debugPrint('[Feed] felicitar: $e');
  }
}

/// Algo que hizo un amigo dentro de Ohtli.
class FriendActivity {
  final String userId;
  final String type; // 'published' | 'finished' | 'joined'
  final DateTime date;
  final Trip? trip;

  const FriendActivity({required this.userId, required this.type, required this.date, this.trip});

  /// Id estable para no felicitar dos veces lo mismo.
  String get key => trip != null ? '${trip!.userId}_${trip!.id}' : 'joined_$userId';
}

/// Arma la actividad a partir de los viajes publicados de cada amigo y de cuándo se unió.
/// Solo usa lo que las reglas dejan leer a otros: viajes publicados y públicos.
List<FriendActivity> buildFriendActivities(Map<String, List<Trip>> tripsByFriend, Map<String, DateTime?> joinedAt) {
  final out = <FriendActivity>[];
  tripsByFriend.forEach((uid, list) {
    for (final t in list) {
      if (t.isReleaseNotes || t.status != 'published' || t.visibility != 'public') continue;
      final finished = t.finishedAt;
      out.add(
        FriendActivity(
          userId: uid,
          type: finished != null ? 'finished' : 'published',
          date: finished != null && finished.isAfter(t.updatedAt) ? finished : t.updatedAt,
          trip: t,
        ),
      );
    }
  });
  joinedAt.forEach((uid, d) {
    if (d != null) out.add(FriendActivity(userId: uid, type: 'joined', date: d));
  });
  out.sort((a, b) => b.date.compareTo(a.date));
  return out.take(40).toList();
}

/// Feed tipo «lo que hacen tus amigos»: viajes que publican o terminan y quién se unió,
/// con un botón para felicitarlos (les llega como notificación).
class FriendsActivityFeed extends StatefulWidget {
  final List<String> friendIds;
  final Map<String, DocumentSnapshot> users;
  final void Function(String userId) onOpenProfile;
  final VoidCallback onShowSuggestions;
  final double padding;

  const FriendsActivityFeed({
    super.key,
    required this.friendIds,
    required this.users,
    required this.onOpenProfile,
    required this.onShowSuggestions,
    required this.padding,
  });

  @override
  State<FriendsActivityFeed> createState() => _FriendsActivityFeedState();
}

class _FriendsActivityFeedState extends State<FriendsActivityFeed> {
  final Map<String, List<Trip>> _tripsByFriend = {};
  final Set<String> _cheered = {};
  final Set<String> _loaded = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FriendsActivityFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.friendIds.any((id) => !_loaded.contains(id))) _load();
  }

  Future<void> _load() async {
    final pending = widget.friendIds.where((id) => !_loaded.contains(id)).take(40).toList();
    _loaded.addAll(pending);
    if (pending.isEmpty) {
      if (_loading && mounted) setState(() => _loading = false);
      return;
    }
    await Future.wait(
      pending.map((uid) async {
        try {
          // Solo filtros de igualdad: no necesita índice compuesto. Se ordena aquí.
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('trips')
              .where('status', isEqualTo: 'published')
              .where('visibility', isEqualTo: 'public')
              .limit(12)
              .get();
          _tripsByFriend[uid] = snap.docs.map((d) => Trip.fromMap(d.data(), d.id)).toList();
        } catch (e) {
          debugPrint('[Feed] viajes de $uid: $e');
        }
      }),
    );
    if (mounted) setState(() => _loading = false);
  }

  DateTime? _joined(String uid) {
    final data = widget.users[uid]?.data() as Map<String, dynamic>?;
    final raw = data?['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  Future<void> _cheer(FriendActivity a) async {
    if (_cheered.contains(a.key)) return;
    setState(() => _cheered.add(a.key));
    await sendCheer(toUserId: a.userId, tripId: a.trip?.id, tripTitle: a.trip?.title, tripOwnerId: a.trip?.userId);
  }

  void _openTrip(Trip trip) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeferredView(
          load: trips.loadLibrary,
          builder: (_) => trips.TripViewerPage(trip: trip, onBackToDashboard: () => Navigator.pop(context)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.padding;
    if (widget.friendIds.isEmpty) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(padding, 8, padding, 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: OhtliEmptyState(
            icon: Icons.dynamic_feed_rounded,
            title: 'Tu feed está esperando',
            message: 'Cuando tengas amigos, aquí verás los viajes que publican, los que terminan y quién se une a Ohtli.',
            action: OhtliPrimaryButton(
              compact: true,
              label: 'Buscar amigos',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: widget.onShowSuggestions,
            ),
          ),
        ),
      );
    }

    final activities = buildFriendActivities(
      {
        for (final id in widget.friendIds)
          if (_tripsByFriend[id] != null) id: _tripsByFriend[id]!,
      },
      {for (final id in widget.friendIds) id: _joined(id)},
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(padding, 4, padding, 48),
      children: [
        _FriendsRing(friendIds: widget.friendIds, users: widget.users, onOpenProfile: widget.onOpenProfile),
        const SizedBox(height: 22),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loading && activities.isEmpty)
                  for (var i = 0; i < 3; i++)
                    Container(
                      height: i == 0 ? 320 : 110,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: OhtliColors.cardBg,
                        borderRadius: BorderRadius.circular(OhtliUi.radiusCard),
                        border: Border.all(color: OhtliColors.cardBorder),
                      ),
                    )
                else if (activities.isEmpty)
                  const OhtliEmptyState(
                    icon: Icons.hourglass_empty_rounded,
                    title: 'Todo tranquilo por ahora',
                    message: 'Tus amigos aún no publican viajes. En cuanto lo hagan, aparecerán aquí.',
                  )
                else
                  for (final a in activities)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _ActivityCard(
                        activity: a,
                        user: widget.users[a.userId],
                        cheered: _cheered.contains(a.key),
                        onCheer: () => _cheer(a),
                        onOpenProfile: () => widget.onOpenProfile(a.userId),
                        onOpenTrip: a.trip == null ? null : () => _openTrip(a.trip!),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fila de fotos de tus amigos (como las historias) para entrar rápido a su perfil.
class _FriendsRing extends StatelessWidget {
  final List<String> friendIds;
  final Map<String, DocumentSnapshot> users;
  final void Function(String userId) onOpenProfile;

  const _FriendsRing({required this.friendIds, required this.users, required this.onOpenProfile});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: friendIds.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final id = friendIds[i];
          final data = users[id]?.data() as Map<String, dynamic>?;
          final name = (data?['displayName'] as String?) ?? '…';
          return Semantics(
            button: true,
            label: 'Perfil de $name',
            child: GestureDetector(
              onTap: () => onOpenProfile(id),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: SizedBox(
                  width: 72,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [OhtliColors.cempasuchil, OhtliColors.xoconostle, OhtliColors.stormyTeal, OhtliColors.cempasuchil],
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: OhtliColors.cloudDancer),
                          child: FeedAvatar(name: name, photoURL: data?['photoURL'] as String?, size: 60),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name.split(' ').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Foto redonda con iniciales de respaldo.
class FeedAvatar extends StatelessWidget {
  final String name;
  final String? photoURL;
  final double size;

  const FeedAvatar({super.key, required this.name, required this.photoURL, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final initials = name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final fallback = Center(
      child: Text(
        initials,
        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.34),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: OhtliColors.stormyTeal),
      child: ClipOval(
        child: photoURL != null && photoURL!.isNotEmpty ? Image.network(photoURL!, fit: BoxFit.cover, errorBuilder: (c, e, s) => fallback) : fallback,
      ),
    );
  }
}

String feedRelativeTime(DateTime t, [DateTime? now]) {
  final diff = (now ?? DateTime.now()).difference(t);
  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays == 1) return 'ayer';
  if (diff.inDays < 7) return 'hace ${diff.inDays} días';
  const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  final sameYear = t.year == (now ?? DateTime.now()).year;
  return '${t.day} ${months[t.month - 1]}${sameYear ? '' : ' ${t.year}'}';
}

class _ActivityCard extends StatelessWidget {
  final FriendActivity activity;
  final DocumentSnapshot? user;
  final bool cheered;
  final VoidCallback onCheer;
  final VoidCallback onOpenProfile;
  final VoidCallback? onOpenTrip;

  const _ActivityCard({
    required this.activity,
    required this.user,
    required this.cheered,
    required this.onCheer,
    required this.onOpenProfile,
    required this.onOpenTrip,
  });

  @override
  Widget build(BuildContext context) {
    final data = user?.data() as Map<String, dynamic>?;
    final name = (data?['displayName'] as String?) ?? 'Tu amigo';
    final trip = activity.trip;
    final firstName = name.split(' ').first;

    final ({IconData icon, Color color, String verb}) kind = switch (activity.type) {
      'finished' => (icon: Icons.flag_rounded, color: OhtliColors.xoconostle, verb: 'terminó un viaje'),
      'joined' => (icon: Icons.celebration_rounded, color: OhtliColors.cempasuchil, verb: 'se unió a Ohtli'),
      _ => (icon: Icons.auto_stories_rounded, color: OhtliColors.stormyTeal, verb: 'publicó un viaje'),
    };

    final header = Row(
      children: [
        GestureDetector(
          onTap: onOpenProfile,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                FeedAvatar(name: name, photoURL: data?['photoURL'] as String?, size: 46),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: kind.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: OhtliColors.cardBg, width: 2.5),
                    ),
                    child: Icon(kind.icon, size: 11, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: GoogleFonts.inter(fontSize: 14.5, color: OhtliColors.onyx.withValues(alpha: 0.8), height: 1.35),
                  children: [
                    TextSpan(
                      text: '$name ',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15.5, color: OhtliColors.onyx),
                    ),
                    TextSpan(text: kind.verb),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                feedRelativeTime(activity.date),
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
              ),
            ],
          ),
        ),
      ],
    );

    final cheerButton = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
      child: cheered
          ? Container(
              key: const ValueKey('done'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: OhtliColors.cempasuchil.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: OhtliColors.cempasuchil.withValues(alpha: 0.4)),
              ),
              child: Text(
                activity.type == 'joined' ? '👋  Saludaste' : '🎉  Felicitaste a $firstName',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
              ),
            )
          : OhtliPrimaryButton(
              key: const ValueKey('cheer'),
              compact: true,
              highlight: true,
              label: activity.type == 'joined' ? '👋  Saludar' : '🎉  Felicitar',
              onPressed: onCheer,
            ),
    );

    if (trip == null) {
      return OhtliSurface(
        padding: const EdgeInsets.all(16),
        accent: kind.color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: 14),
            Text('Dale la bienvenida a $firstName y armen su primera ruta juntos.', style: OhtliUi.body(size: 14)),
            const SizedBox(height: 12),
            cheerButton,
          ],
        ),
      );
    }

    final cover = trip.coverUrl.isNotEmpty ? trip.coverUrl : CdmxPhotos.cover(trip.id.hashCode);
    return OhtliSurface(
      padding: EdgeInsets.zero,
      onTap: onOpenTrip,
      accent: kind.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 14), child: header),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    OhtliPhoto(cover),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xB0000000)],
                          stops: [0.45, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trip.title.isEmpty ? 'Viaje sin título' : trip.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1),
                          ),
                          if (trip.coAuthorNames.isNotEmpty || trip.travelDate != null) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (trip.travelDate != null) OhtliMetaPill(icon: Icons.event_rounded, label: _date(trip.travelDate!), onDark: true),
                                if (trip.coAuthorNames.isNotEmpty)
                                  OhtliMetaPill(icon: Icons.group_rounded, label: 'con ${trip.coAuthorNames.take(2).join(' y ')}', onDark: true),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (trip.description.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(trip.description.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: OhtliUi.body(size: 14)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                cheerButton,
                OhtliSecondaryButton(compact: true, label: 'Ver viaje', icon: Icons.arrow_forward_rounded, onPressed: onOpenTrip),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) {
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
