import '../services/social_graph.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/colors.dart';
import '../widgets/ohtli_ui.dart';
import 'trips/trip_screens.dart' deferred as trips;
import '../widgets/deferred_view.dart';
import 'account/public_profile_page.dart';
import '../utils/friendly_errors.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;

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
        await firestore.collection('friend_requests').doc(notificationId).update({
          'status': 'accepted',
        });

        // 2. Update Bob's private notification
        await firestore
            .collection('users')
            .doc(_currentUser.uid)
            .collection('notifications')
            .doc(notificationId)
            .update({
          'status': 'accepted',
        });

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
            await firestore
                .collection('users')
                .doc(_currentUser.uid)
                .collection('notifications')
                .doc(requestDoc.id)
                .update({
              'status': 'accepted',
            });
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
        await firestore.collection('friend_requests').doc(notificationId).update({
          'status': 'declined',
        });

        // 2. Update Bob's private notification
        await firestore
            .collection('users')
            .doc(_currentUser.uid)
            .collection('notifications')
            .doc(notificationId)
            .update({
          'status': 'declined',
        });

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
            await firestore
                .collection('users')
                .doc(_currentUser.uid)
                .collection('notifications')
                .doc(requestDoc.id)
                .update({
              'status': 'declined',
            });
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

  ({IconData icon, Color color}) _typeBadge(String type) {
    switch (type) {
      case 'friend_request':
        return (icon: Icons.person_add_alt_1_rounded, color: OhtliColors.stormyTeal);
      case 'surprise_plan':
        return (icon: Icons.card_giftcard_rounded, color: OhtliColors.xoconostle);
      case 'co_author_added':
        return (icon: Icons.group_add_rounded, color: OhtliColors.cempasuchil);
      default:
        return (icon: Icons.auto_stories_rounded, color: OhtliColors.stormyTeal);
    }
  }

  /// Filtro activo: null = todas.
  String? _filter;

  static const _filters = <({String? key, String label, IconData icon})>[
    (key: null, label: 'Todas', icon: Icons.inbox_rounded),
    (key: 'friends', label: 'Amistades', icon: Icons.people_alt_rounded),
    (key: 'trips', label: 'Viajes', icon: Icons.map_rounded),
    (key: 'surprises', label: 'Sorpresas', icon: Icons.card_giftcard_rounded),
  ];

  bool _matchesFilter(String type) {
    switch (_filter) {
      case 'friends':
        return type == 'friend_request';
      case 'trips':
        return type == 'new_publication' || type == 'co_author_added';
      case 'surprises':
        return type == 'surprise_plan';
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
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser.uid)
            .collection('notifications')
            .orderBy('timestamp', descending: true)
            .snapshots(),
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
          final entries = <Object>[];
          String? lastGroup;
          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final group = _groupFor((data['timestamp'] as Timestamp?)?.toDate());
            if (group != lastGroup) {
              entries.add(group);
              lastGroup = group;
            }
            entries.add(doc);
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
              ],
            ),
          );

          final chips = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(padding, 0, padding, 8),
            child: Row(
              children: [
                for (final f in _filters) ...[
                  OhtliChoiceChip(
                    label: f.label,
                    icon: f.icon,
                    selected: _filter == f.key,
                    onTap: () => setState(() => _filter = f.key),
                  ),
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
                    ? const OhtliEmptyState(
                        icon: Icons.notifications_none_rounded,
                        title: 'Todo al día',
                        message: 'Aquí verás solicitudes de amistad, viajes nuevos de tus amigos, invitaciones como coautor y planes sorpresa.',
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
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildNotification(entry as QueryDocumentSnapshot, width),
                );
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

  Widget _buildNotification(QueryDocumentSnapshot doc, double width) {
    final data = doc.data() as Map<String, dynamic>;
    final String type = data['type'] ?? 'friend_request';
    final String senderName = data['senderName'] ?? 'Viajero Ohtli';
    final String senderId = data['senderId'] ?? '';
    final String status = data['status'] ?? 'pending';
    final String? senderPhoto = data['senderPhoto'];
    final DateTime? ts = (data['timestamp'] as Timestamp?)?.toDate();
    final String tripTitle = data['tripTitle'] ?? 'su itinerario';
    final bool isPlan = data['isPlan'] ?? false;

    String messageText = '';
    if (type == 'friend_request') {
      messageText = status == 'pending'
          ? 'te envió una solicitud de amistad.'
          : status == 'accepted'
              ? 'y tú ahora son amigos.'
              : 'te envió una solicitud (rechazada).';
    } else if (type == 'new_publication') {
      messageText = 'publicó un nuevo ${isPlan ? "plan" : "viaje"}: "$tripTitle".';
    } else if (type == 'surprise_plan') {
      messageText = 'te preparó un plan sorpresa: "$tripTitle".';
    } else if (type == 'co_author_added') {
      messageText = 'te agregó como coautor en su ${isPlan ? "plan" : "viaje"}: "$tripTitle".';
    }

    final initials = senderName.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final bool isClickable = (type == 'new_publication' || type == 'surprise_plan' || type == 'co_author_added') && data['tripId'] != null;
    final bool isPendingRequest = type == 'friend_request' && status == 'pending';
    final badge = _typeBadge(type);
    final bool isDesktop = width > 600;

    void openTrip() {
      // En co_author_added el dueño del viaje es tripOwnerId (senderId es quien te agregó)
      final String navAuthorId = (type == 'co_author_added' && data['tripOwnerId'] != null) ? data['tripOwnerId'] : senderId;
      Navigator.push(context, MaterialPageRoute(builder: (context) => DeferredView(load: trips.loadLibrary, builder: (_) => trips.TripViewerPage(tripId: data['tripId'], authorId: navAuthorId))));
    }

    void openProfile() {
      if (senderId.isEmpty) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (ctx) => PublicProfilePage(userId: senderId, showBackButton: true, onBack: () => Navigator.pop(ctx))),
      );
    }

    Widget initialsText() => Center(
          child: Text(initials, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        );

    final avatar = Semantics(
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
                    border: Border.all(color: OhtliColors.cardBg, width: 2),
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
              TextSpan(text: '$senderName ', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15.5)),
              TextSpan(text: messageText, style: TextStyle(color: OhtliColors.onyx.withValues(alpha: 0.8))),
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
              Text(_relativeTime(ts), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
            ],
          ),
        ],
      ],
    );

    final actionButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OhtliSecondaryButton(compact: true, label: 'Rechazar', onPressed: () => _handleFriendRequest(doc.id, senderId, false)),
        const SizedBox(width: 8),
        OhtliPrimaryButton(compact: true, label: 'Aceptar', icon: Icons.check_rounded, onPressed: () => _handleFriendRequest(doc.id, senderId, true)),
      ],
    );

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
              if (isPendingRequest && isDesktop) ...[const SizedBox(width: 12), actionButtons],
              if (isClickable)
                Container(
                  margin: const EdgeInsets.only(left: 10),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: OhtliColors.innerCardBg, shape: BoxShape.circle),
                  child: Icon(Icons.arrow_forward_rounded, size: 17, color: OhtliColors.accentText),
                ),
            ],
          ),
          if (isPendingRequest && !isDesktop) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: actionButtons),
          ],
        ],
      ),
    );
  }
}
