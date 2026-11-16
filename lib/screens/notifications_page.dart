import '../services/social_graph.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/colors.dart';
import '../widgets/ohtli_ui.dart';
import 'friends_feed.dart' show sendCheer;
import 'friends_page.dart';
import '../services/notification_text.dart';
import '../widgets/ohtli_live_alerts.dart' show OhtliAlerts;
import 'package:flutter_svg/flutter_svg.dart';
import 'trips/trip_screens.dart' deferred as trips;
import '../widgets/deferred_view.dart';
import '../widgets/group_trip_sheet.dart' show openGroupTrip;
import '../widgets/push_toggle.dart' show PushInviteBanner;
import 'account/public_profile_page.dart';
import '../utils/friendly_errors.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  /// Se crea una sola vez: si se recreara en cada build (p. ej. al cambiar de filtro)
  /// la lista volvería a "cargando" y parpadearía.
  late final Stream<QuerySnapshot>? _stream = _currentUser == null
      ? null
      : FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser.uid)
          .collection('notifications')
          .orderBy('timestamp', descending: true)
          .snapshots();

  @override
  void initState() {
    super.initState();
    _markAllAsRead();
  }

  Future<void> _markAllAsRead() async {
    if (_currentUser == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser.uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in snapshot.docs) {
          batch.update(doc.reference, {'read': true});
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint("Error marking notifications as read: $e");
    }
  }

  Future<void> _handleFriendRequest(String notificationId, String senderId, bool accept) async {
    if (_currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;

      if (accept) {
        // 1. Update the top-level friend request
        await firestore.collection('friend_requests').doc(notificationId).update({'status': 'accepted'});

        // 2. Update Bob's private notification
        await firestore.collection('users').doc(_currentUser.uid).collection('notifications').doc(notificationId).update({'status': 'accepted'});

        // 3-4. Amistad en ambos sentidos (users/{uid}/social/graph)
        await SocialGraph.addFriendship(_currentUser.uid, senderId);

        // 5. Clean up any other duplicate pending notifications/requests between these two users
        final duplicateRequests = await firestore
            .collection('friend_requests')
            .where('senderId', isEqualTo: senderId)
            .where('receiverId', isEqualTo: _currentUser.uid)
            .where('status', isEqualTo: 'pending')
            .get();

        for (var requestDoc in duplicateRequests.docs) {
          if (requestDoc.id != notificationId) {
            await requestDoc.reference.update({'status': 'accepted'});
            await firestore.collection('users').doc(_currentUser.uid).collection('notifications').doc(requestDoc.id).update({'status': 'accepted'});
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('¡Solicitud aceptada! Ahora son amigos.', style: GoogleFonts.inter()),
              backgroundColor: OhtliColors.stormyTeal,
            ),
          );
        }
      } else {
        // Decline request
        // 1. Update the top-level request
        await firestore.collection('friend_requests').doc(notificationId).update({'status': 'declined'});

        // 2. Update Bob's private notification
        await firestore.collection('users').doc(_currentUser.uid).collection('notifications').doc(notificationId).update({'status': 'declined'});

        // 3. Clean up any other duplicate pending requests as declined
        final duplicateRequests = await firestore
            .collection('friend_requests')
            .where('senderId', isEqualTo: senderId)
            .where('receiverId', isEqualTo: _currentUser.uid)
            .where('status', isEqualTo: 'pending')
            .get();

        for (var requestDoc in duplicateRequests.docs) {
          if (requestDoc.id != notificationId) {
            await requestDoc.reference.update({'status': 'declined'});
            await firestore.collection('users').doc(_currentUser.uid).collection('notifications').doc(requestDoc.id).update({'status': 'declined'});
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Solicitud rechazada.', style: GoogleFonts.inter()),
              backgroundColor: OhtliColors.xoconostle,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, fallback: 'No pudimos responder la solicitud. Intenta de nuevo.'), style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    }
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'ayer';
    if (diff.inDays < 7) return 'hace ${diff.inDays} días';
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    final sameYear = t.year == DateTime.now().year;
    return '${t.day} ${months[t.month - 1]}${sameYear ? '' : ' ${t.year}'}';
  }

  String _groupFor(DateTime? t) {
    if (t == null) return 'Antes';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return 'Hoy';
    if (days == 1) return 'Ayer';
    if (days < 7) return 'Esta semana';
    return 'Antes';
  }

  /// Filtro activo: null = todas.
  String? _filter;

  /// Avisos a los que ya respondiste con «Felicitar» o «Saludar» en esta visita.
  final Set<String> _cheered = {};

  static const _filters = <({String? key, String label, IconData icon})>[
    (key: null, label: 'Todas', icon: Icons.inbox_rounded),
    (key: 'friends', label: 'Amistades', icon: Icons.people_alt_rounded),
    (key: 'trips', label: 'Viajes', icon: Icons.map_rounded),
    (key: 'surprises', label: 'Sorpresas', icon: Icons.card_giftcard_rounded),
    (key: 'ai', label: 'Rutas con IA', icon: Icons.auto_awesome_rounded),
  ];

  bool _matchesFilter(String type) {
    switch (_filter) {
      case 'friends':
        return type == 'friend_request' || type == 'cheer';
      case 'trips':
        return type == 'new_publication' ||
            type == 'co_author_added' ||
            type == 'trip_comment' ||
            type == 'trip_reaction' ||
            type.startsWith('group_trip_');
      case 'surprises':
        return type == 'surprise_plan';
      case 'ai':
        return type == 'itinerary_ready' || type == 'itinerary_failed';
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: const OhtliEmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'Inicia sesión',
                message: 'Inicia sesión para ver tus notificaciones.',
              ),
            ),
          ),
        ),
      );
    }

    final double width = MediaQuery.of(context).size.width;
    final double padding = OhtliUi.pagePadding(width);
    final bool isMobile = width < 700;
    // En el panel junto al menú hay botones arriba a la derecha (pantalla completa y cerrar).
    final double headerRight = width <= 460 ? 84 : 0;

    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream,
        builder: (context, snapshot) {
          final bool loading = snapshot.connectionState == ConnectionState.waiting;
          final allDocs = snapshot.data?.docs ?? [];
          final now = DateTime.now();
          final visible = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final String? type = data['type'] as String?;
            final Timestamp? ts = data['timestamp'] as Timestamp?;
            if (ts == null) return true;
            if (type == 'surprise_plan') return !now.isBefore(ts.toDate());
            return true;
          }).toList();
          final docs = visible.where((d) => _matchesFilter(((d.data() as Map<String, dynamic>)['type'] as String?) ?? 'friend_request')).toList();
          final int pending = visible.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return (data['type'] ?? 'friend_request') == 'friend_request' && (data['status'] ?? 'pending') == 'pending';
          }).length;

          final String summary = loading
              ? 'Cargando tu actividad…'
              : pending > 0
              ? (pending == 1 ? 'Tienes 1 solicitud de amistad por responder.' : 'Tienes $pending solicitudes de amistad por responder.')
              : visible.isEmpty
              ? 'Aquí aparece lo que pasa con tus amigos y tus viajes.'
              : 'Estás al día con tu actividad.';

          // Encabezados por día (Hoy / Ayer / Esta semana / Antes)
          // Avisos de rutas con IA iguales y seguidos (p. ej. tres búsquedas que terminaron a la
          // vez) se juntan en uno: el primero se queda y cuenta cuántos representa.
          final entries = <Object>[];
          final repeats = <String, int>{};
          String? lastGroup;
          QueryDocumentSnapshot? lastDoc;
          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final group = _groupFor((data['timestamp'] as Timestamp?)?.toDate());
            if (group != lastGroup) {
              entries.add(group);
              lastGroup = group;
              lastDoc = null;
            }
            final type = data['type'];
            if (lastDoc != null && (type == 'itinerary_ready' || type == 'itinerary_failed')) {
              final prev = lastDoc.data() as Map<String, dynamic>;
              if (prev['type'] == type && prev['message'] == data['message']) {
                repeats[lastDoc.id] = (repeats[lastDoc.id] ?? 1) + 1;
                continue;
              }
            }
            entries.add(doc);
            lastDoc = doc;
          }

          final header = Padding(
            padding: EdgeInsets.fromLTRB(padding, isMobile ? 24 : 40, padding + headerRight, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OhtliSectionHeader(
                  eyebrow: 'Tu actividad',
                  icon: Icons.notifications_rounded,
                  title: 'Notificaciones',
                  subtitle: summary,
                  large: true,
                ),
                const SizedBox(height: 20),
                const PushInviteBanner(),
              ],
            ),
          );

          final chips = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(padding, 0, padding, 8),
            child: Row(
              children: [
                for (final f in _filters) ...[
                  OhtliChoiceChip(label: f.label, icon: f.icon, selected: _filter == f.key, onTap: () => setState(() => _filter = f.key)),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          );

          Widget body;
          if (loading) {
            body = SliverList.builder(
              itemCount: 4,
              itemBuilder: (_, i) => Container(
                height: 78,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: OhtliColors.cardBg,
                  borderRadius: BorderRadius.circular(OhtliUi.radiusCard),
                  border: Border.all(color: OhtliColors.cardBorder),
                ),
              ),
            );
          } else if (docs.isEmpty) {
            body = SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: visible.isEmpty
                    ? OhtliEmptyState(
                        icon: Icons.notifications_none_rounded,
                        title: 'Todo al día',
                        message: 'Aquí verás solicitudes de amistad, viajes nuevos de tus amigos, invitaciones como coautor y planes sorpresa.',
                        action: OhtliPrimaryButton(
                          compact: true,
                          label: 'Buscar amigos',
                          icon: Icons.person_add_alt_1_rounded,
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsPage(showBackButton: true))),
                        ),
                      )
                    : OhtliEmptyState(
                        icon: _filters.firstWhere((f) => f.key == _filter).icon,
                        title: 'Nada por aquí',
                        message: 'No tienes notificaciones de este tipo.',
                        action: OhtliSecondaryButton(label: 'Ver todas', onPressed: () => setState(() => _filter = null)),
                      ),
              ),
            );
          } else {
            body = SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                if (entry is String) {
                  return Padding(
                    padding: EdgeInsets.only(top: index == 0 ? 8 : 22, bottom: 12, left: 4),
                    child: Text(entry.toUpperCase(), style: OhtliUi.eyebrow(OhtliColors.subtleText)),
                  );
                }
                return Padding(padding: const EdgeInsets.only(bottom: 12), child: _buildNotification(entry as QueryDocumentSnapshot, width, repeats: repeats[entry.id] ?? 1));
              },
            );
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: header),
              SliverToBoxAdapter(child: chips),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padding, 8, padding, 48),
                sliver: SliverConstrainedCrossAxis(maxExtent: 820, sliver: body),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNotification(QueryDocumentSnapshot doc, double width, {int repeats = 1}) {
    final data = doc.data() as Map<String, dynamic>;
    final String type = data['type'] ?? 'friend_request';
    final look = describeNotification(data);
    final String senderName = look.sender;
    final String senderId = data['senderId'] ?? '';
    final String status = data['status'] ?? 'pending';
    final String? senderPhoto = data['senderPhoto'];
    final DateTime? ts = (data['timestamp'] as Timestamp?)?.toDate();
    final String tripTitle = data['tripTitle'] ?? 'su itinerario';
    final bool isPlan = data['isPlan'] ?? false;

    final String messageText = repeats > 1 ? itineraryGroupedMessage(type, repeats) : look.message;
    final initials = senderName.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final bool isClickable =
        (type == 'new_publication' ||
            type == 'surprise_plan' ||
            type == 'co_author_added' ||
            type == 'cheer' ||
            type == 'trip_comment' ||
            type == 'trip_reaction') &&
        data['tripId'] != null;
    final bool isPendingRequest = type == 'friend_request' && status == 'pending';
    final badge = (icon: look.icon, color: look.color);
    final bool isDesktop = width > 600;

    void openTrip() {
      // En co_author_added el dueño del viaje es tripOwnerId (senderId es quien te agregó)
      final String navAuthorId = (data['tripOwnerId'] != null && type != 'new_publication' && type != 'surprise_plan')
          ? data['tripOwnerId']
          : senderId;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DeferredView(
            load: trips.loadLibrary,
            builder: (_) => trips.TripViewerPage(tripId: data['tripId'], authorId: navAuthorId),
          ),
        ),
      );
    }

    void openProfile() {
      if (senderId.isEmpty) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => PublicProfilePage(userId: senderId, showBackButton: true, onBack: () => Navigator.pop(ctx)),
        ),
      );
    }

    Widget initialsText() => Center(
      child: Text(
        initials,
        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
      ),
    );

    final Widget systemAvatar = Container(
      width: 50,
      height: 50,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: look.color,
        shape: BoxShape.circle,
        boxShadow: OhtliUi.softShadow(color: look.color),
      ),
      child: SvgPicture.asset('assets/icon_isologo.svg', colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
    );

    final avatar = look.fromSystem
        ? systemAvatar
        : Semantics(
            button: senderId.isNotEmpty,
            label: 'Perfil de $senderName',
            child: GestureDetector(
              onTap: openProfile,
              child: MouseRegion(
                cursor: senderId.isEmpty ? MouseCursor.defer : SystemMouseCursors.click,
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: OhtliColors.stormyTeal,
                          boxShadow: OhtliUi.softShadow(),
                        ),
                        child: ClipOval(
                          child: senderPhoto != null && senderPhoto.isNotEmpty
                              ? Image.network(senderPhoto, fit: BoxFit.cover, errorBuilder: (c, e, st) => initialsText())
                              : initialsText(),
                        ),
                      ),
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: badge.color,
                            shape: BoxShape.circle,
                            border: Border.all(color: OhtliColors.cardBg, width: 2.5),
                          ),
                          child: Icon(badge.icon, size: 11, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: GoogleFonts.inter(color: OhtliColors.onyx, fontSize: 14.5, height: 1.45),
            children: [
              if (!look.fromSystem)
                TextSpan(
                  text: '$senderName ',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15.5),
                ),
              TextSpan(
                text: messageText,
                style: TextStyle(color: OhtliColors.onyx.withValues(alpha: 0.8)),
              ),
            ],
          ),
        ),
        if (ts != null) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_rounded, size: 13, color: OhtliColors.subtleText),
              const SizedBox(width: 4),
              Text(
                _relativeTime(ts),
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.subtleText),
              ),
            ],
          ),
        ],
      ],
    );

    // Acciones claras para cada tipo de aviso.
    final String cheerKey = '${data['tripId'] ?? doc.id}';
    final List<Widget> ctas = switch (type) {
      'friend_request' when isPendingRequest => [
        OhtliPrimaryButton(compact: true, label: 'Aceptar', icon: Icons.check_rounded, onPressed: () => _handleFriendRequest(doc.id, senderId, true)),
        OhtliSecondaryButton(compact: true, label: 'Rechazar', onPressed: () => _handleFriendRequest(doc.id, senderId, false)),
      ],
      'friend_request' when status == 'accepted' => [
        OhtliSecondaryButton(compact: true, label: 'Ver perfil', icon: Icons.person_rounded, onPressed: openProfile),
        _cheerButton(
          cheerKey,
          label: '👋  Saludar',
          onTap: () => sendCheer(toUserId: senderId),
        ),
      ],
      'new_publication' when isClickable => [
        _cheerButton(
          cheerKey,
          label: '🎉  Felicitar',
          onTap: () => sendCheer(toUserId: senderId, tripId: data['tripId'], tripTitle: tripTitle, tripOwnerId: senderId),
        ),
        OhtliSecondaryButton(compact: true, label: isPlan ? 'Ver plan' : 'Ver viaje', icon: Icons.arrow_forward_rounded, onPressed: openTrip),
      ],
      'surprise_plan' when isClickable => [OhtliPrimaryButton(compact: true, highlight: true, label: '🎁  Abrir sorpresa', onPressed: openTrip)],
      'co_author_added' when isClickable => [
        OhtliPrimaryButton(compact: true, label: isPlan ? 'Abrir plan' : 'Abrir viaje', icon: Icons.edit_note_rounded, onPressed: openTrip),
      ],
      'trip_comment' when isClickable => [OhtliPrimaryButton(compact: true, label: 'Responder', icon: Icons.reply_rounded, onPressed: openTrip)],
      'trip_reaction' when isClickable => [
        OhtliSecondaryButton(compact: true, label: 'Ver viaje', icon: Icons.arrow_forward_rounded, onPressed: openTrip),
      ],
      'group_trip_invite' when data['groupTripId'] != null => [
        if (status == 'pending')
          OhtliPrimaryButton(compact: true, label: 'Responder', icon: Icons.how_to_reg_rounded, onPressed: () => openGroupTrip(context, data['groupTripId']))
        else
          OhtliSecondaryButton(compact: true, label: 'Ver plan', icon: Icons.arrow_forward_rounded, onPressed: () => openGroupTrip(context, data['groupTripId'])),
      ],
      'group_trip_accepted' || 'group_trip_created' when data['groupTripId'] != null => [
        OhtliPrimaryButton(compact: true, label: 'Abrir plan', icon: Icons.edit_note_rounded, onPressed: () => openGroupTrip(context, data['groupTripId'])),
      ],
      'group_trip_ready' when data['groupTripId'] != null => [
        OhtliPrimaryButton(compact: true, highlight: true, label: 'Votar', icon: Icons.how_to_vote_rounded, onPressed: () => openGroupTrip(context, data['groupTripId'])),
      ],
      'itinerary_ready' => [
        OhtliPrimaryButton(
          compact: true,
          highlight: true,
          label: 'Ver propuestas',
          icon: Icons.auto_awesome_rounded,
          onPressed: () => OhtliAlerts.openTab(context, 1),
        ),
      ],
      'itinerary_failed' => [
        OhtliSecondaryButton(
          compact: true,
          label: 'Intentar de nuevo',
          icon: Icons.refresh_rounded,
          onPressed: () => OhtliAlerts.openTab(context, 1),
        ),
      ],
      'cheer' => [
        if (isClickable) OhtliSecondaryButton(compact: true, label: 'Ver tu viaje', icon: Icons.arrow_forward_rounded, onPressed: openTrip),
        OhtliSecondaryButton(compact: true, label: 'Ver perfil', icon: Icons.person_rounded, onPressed: openProfile),
      ],
      _ => const <Widget>[],
    };

    return OhtliSurface(
      padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
      onTap: isClickable ? openTrip : null,
      accent: badge.color,
      selected: isPendingRequest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              avatar,
              const SizedBox(width: 14),
              Expanded(child: text),
            ],
          ),
          if (ctas.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.only(left: isDesktop ? 66 : 0),
              child: Wrap(spacing: 8, runSpacing: 8, children: ctas),
            ),
          ],
        ],
      ),
    );
  }

  /// «Felicitar» / «Saludar»: al tocarlo queda marcado como hecho.
  Widget _cheerButton(String key, {required String label, required Future<void> Function() onTap}) {
    final done = _cheered.contains(key);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
      child: done
          ? Container(
              key: const ValueKey('done'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: OhtliColors.cempasuchil.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: OhtliColors.cempasuchil.withValues(alpha: 0.4)),
              ),
              child: Text(
                '¡Listo!',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: OhtliColors.onyx),
              ),
            )
          : OhtliPrimaryButton(
              key: const ValueKey('cheer'),
              compact: true,
              highlight: true,
              label: label,
              onPressed: () {
                setState(() => _cheered.add(key));
                onTap();
              },
            ),
    );
  }
}
