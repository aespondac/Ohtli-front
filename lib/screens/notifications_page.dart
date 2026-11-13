import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/colors.dart';
import 'construction_page.dart'; // To reuse RouteBackgroundPainter
import 'trips/trip_viewer_page.dart';
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
      print("Error marking notifications as read: $e");
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

        // 3. Add Bob to Alice's friends list
        await firestore.collection('users').doc(senderId).update({
          'friends': FieldValue.arrayUnion([_currentUser.uid]),
        });

        // 4. Add Alice to Bob's friends list
        await firestore.collection('users').doc(_currentUser.uid).update({
          'friends': FieldValue.arrayUnion([senderId]),
        });

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

  @override
  Widget build(BuildContext context) {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    final Color bgColor = isDark ? const Color(0xFF121214) : OhtliColors.cloudDancer;
    final Color cardColor = isDark ? const Color(0xFF1E1E22) : Colors.white;
    final Color textColor = isDark ? Colors.white : OhtliColors.onyx;

    if (_currentUser == null) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Text(
            'Inicia sesión para ver tus notificaciones.',
            style: GoogleFonts.inter(color: textColor),
          ),
        ),
      );
    }

    final double width = MediaQuery.of(context).size.width;
    final double padding = width > 800 ? 32.0 : 16.0;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 0,
        toolbarHeight: 80,
        title: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notificaciones',
                style: GoogleFonts.inter(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Mantente al día con tu actividad',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: textColor.withOpacity(0.5),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: RouteBackgroundPainter(OhtliColors.cantera.withOpacity(0.3)),
            ),
          ),
          Positioned.fill(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(_currentUser.uid)
                  .collection('notifications')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: OhtliColors.stormyTeal),
                  );
                }

                final allDocs = snapshot.data?.docs ?? [];
                final now = DateTime.now();
                final docs = allDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final String? type = data['type'] as String?;
                  final Timestamp? ts = data['timestamp'] as Timestamp?;
                  if (ts == null) return true;
                  if (type == 'surprise_plan') {
                    return !now.isBefore(ts.toDate());
                  }
                  return true;
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 64,
                          color: isDark ? Colors.white24 : OhtliColors.cantera,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Todo al día',
                          style: GoogleFonts.outfit(
                            color: textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Text(
                            'Aquí verás solicitudes de amistad, viajes nuevos de tus amigos y planes sorpresa.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: isDark ? Colors.white54 : OhtliColors.onyx.withOpacity(0.55),
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Encabezados por día (Hoy / Ayer / Esta semana / Antes)
                final entries = <Object>[];
                String? lastGroup;
                for (final doc in docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final ts = (data['timestamp'] as Timestamp?)?.toDate();
                  final group = _groupFor(ts);
                  if (group != lastGroup) {
                    entries.add(group);
                    lastGroup = group;
                  }
                  entries.add(doc);
                }

                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView.builder(
                      padding: EdgeInsets.fromLTRB(padding, 4, padding, 32),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        if (entry is String) {
                          return Padding(
                            padding: EdgeInsets.only(top: index == 0 ? 4 : 18, bottom: 10, left: 4),
                            child: Text(
                              entry.toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: isDark ? Colors.white54 : OhtliColors.onyx.withOpacity(0.5),
                              ),
                            ),
                          );
                        }
                        final doc = entry as QueryDocumentSnapshot;
                        final data = doc.data() as Map<String, dynamic>;

                        final String type = data['type'] ?? 'friend_request';
                        final String senderName = data['senderName'] ?? 'Viajero Ohtli';
                        final String senderId = data['senderId'] ?? '';
                        final String status = data['status'] ?? 'pending';
                        final String? senderPhoto = data['senderPhoto'];
                        final DateTime? ts = (data['timestamp'] as Timestamp?)?.toDate();

                        String messageText = '';
                        if (type == 'friend_request') {
                          if (status == 'pending') {
                            messageText = 'te envió una solicitud de amistad.';
                          } else if (status == 'accepted') {
                            messageText = 'y tú ahora son amigos.';
                          } else {
                            messageText = 'te envió una solicitud (rechazada).';
                          }
                        } else if (type == 'new_publication') {
                          final isPlan = data['isPlan'] ?? false;
                          final tripTitle = data['tripTitle'] ?? 'su itinerario';
                          messageText = 'publicó un nuevo ${isPlan ? "plan" : "viaje"}: "$tripTitle".';
                        } else if (type == 'surprise_plan') {
                          final tripTitle = data['tripTitle'] ?? 'su itinerario';
                          messageText = 'te preparó un plan sorpresa: "$tripTitle".';
                        } else if (type == 'co_author_added') {
                          final isPlan = data['isPlan'] ?? false;
                          final tripTitle = data['tripTitle'] ?? 'su itinerario';
                          messageText = 'te agregó como coautor en su ${isPlan ? "plan" : "viaje"}: "$tripTitle".';
                        }

                        final initials = senderName
                            .split(' ')
                            .where((w) => w.isNotEmpty)
                            .take(2)
                            .map((w) => w[0].toUpperCase())
                            .join();

                        final bool isClickable = (type == 'new_publication' || type == 'surprise_plan' || type == 'co_author_added') && data['tripId'] != null;
                        final bool isPendingRequest = type == 'friend_request' && status == 'pending';
                        final badge = _typeBadge(type);
                        final bool isDesktop = width > 600;

                        void openTrip() {
                          // En co_author_added el dueño del viaje es tripOwnerId (senderId es quien te agregó)
                          final String navAuthorId = (type == 'co_author_added' && data['tripOwnerId'] != null) ? data['tripOwnerId'] : senderId;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TripViewerPage(tripId: data['tripId'], authorId: navAuthorId),
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

                        final avatar = GestureDetector(
                          onTap: openProfile,
                          child: MouseRegion(
                            cursor: senderId.isEmpty ? MouseCursor.defer : SystemMouseCursors.click,
                            child: SizedBox(
                              width: 46,
                              height: 46,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: const BoxDecoration(shape: BoxShape.circle, color: OhtliColors.stormyTeal),
                                    child: ClipOval(
                                      child: senderPhoto != null && senderPhoto.isNotEmpty
                                          ? Image.network(
                                              senderPhoto,
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, st) => Center(
                                                child: Text(initials, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                              ),
                                            )
                                          : Center(
                                              child: Text(initials, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: badge.color,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: cardColor, width: 2),
                                      ),
                                      child: Icon(badge.icon, size: 11, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        final text = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.inter(color: textColor, fontSize: 14, height: 1.4),
                                children: [
                                  TextSpan(text: '$senderName ', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  TextSpan(
                                    text: messageText,
                                    style: TextStyle(color: isDark ? Colors.white70 : OhtliColors.onyx.withOpacity(0.85)),
                                  ),
                                ],
                              ),
                            ),
                            if (ts != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                _relativeTime(ts),
                                style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white38 : OhtliColors.onyx.withOpacity(0.45)),
                              ),
                            ],
                          ],
                        );

                        final actionButtons = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => _handleFriendRequest(doc.id, senderId, false),
                              style: TextButton.styleFrom(
                                foregroundColor: isDark ? Colors.white70 : OhtliColors.onyx.withOpacity(0.7),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                              child: Text('Rechazar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton(
                              onPressed: () => _handleFriendRequest(doc.id, senderId, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: OhtliColors.stormyTeal,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                              child: Text('Aceptar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        );

                        final card = Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isPendingRequest
                                  ? OhtliColors.stormyTeal.withOpacity(0.35)
                                  : (isDark ? Colors.white.withOpacity(0.06) : OhtliColors.cardBorder.withOpacity(0.6)),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  avatar,
                                  const SizedBox(width: 12),
                                  Expanded(child: text),
                                  if (isPendingRequest && isDesktop) ...[const SizedBox(width: 12), actionButtons],
                                  if (isClickable)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8, top: 10),
                                      child: Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white38 : OhtliColors.onyx.withOpacity(0.35)),
                                    ),
                                ],
                              ),
                              if (isPendingRequest && !isDesktop) ...[
                                const SizedBox(height: 10),
                                Align(alignment: Alignment.centerRight, child: actionButtons),
                              ],
                            ],
                          ),
                        );

                        if (!isClickable) return card;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: openTrip,
                            borderRadius: BorderRadius.circular(18),
                            child: card,
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
