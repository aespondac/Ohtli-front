import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/colors.dart';
import 'construction_page.dart'; // To reuse RouteBackgroundPainter
import 'trips/trip_viewer_page.dart';

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
      print("Error handling friend request: $e");
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
                          'No tienes notificaciones todavía.',
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white54 : OhtliColors.onyx.withOpacity(0.5),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    
                    final String type = data['type'] ?? 'friend_request';
                    final String senderName = data['senderName'] ?? 'Viajero Ohtli';
                    final String senderId = data['senderId'] ?? '';
                    final String status = data['status'] ?? 'pending';
                    final String? senderPhoto = data['senderPhoto'];

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
                      messageText = 'te hizo un plan sorpresa: "$tripTitle"!';
                    } else if (type == 'co_author_added') {
                      final isPlan = data['isPlan'] ?? false;
                      final tripTitle = data['tripTitle'] ?? 'su itinerario';
                      messageText = 'te agregó como coautor en su ${isPlan ? "plan" : "viaje"}: "$tripTitle". ✍️';
                    }

                    final initials = senderName
                        .split(' ')
                        .where((w) => w.isNotEmpty)
                        .take(2)
                        .map((w) => w[0].toUpperCase())
                        .join();

                    final bool isClickable = (type == 'new_publication' || type == 'surprise_plan' || type == 'co_author_added') && data['tripId'] != null;

                    final bool isDesktop = width > 600;

                    final Widget actionButtons = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _handleFriendRequest(doc.id, senderId, false),
                          icon: const Icon(Icons.close_rounded, size: 14),
                          label: Text(
                            'Rechazar',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: OhtliColors.xoconostle,
                            side: const BorderSide(color: OhtliColors.xoconostle, width: 1.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            minimumSize: Size.zero,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: () => _handleFriendRequest(doc.id, senderId, true),
                          icon: const Icon(Icons.check_rounded, size: 14),
                          label: Text(
                            'Aceptar',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: OhtliColors.stormyTeal,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            minimumSize: Size.zero,
                          ),
                        ),
                      ],
                    );

                    final Widget cardContent = Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: isDesktop
                          ? Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: OhtliColors.stormyTeal,
                                  ),
                                  child: ClipOval(
                                    child: senderPhoto != null && senderPhoto.isNotEmpty
                                        ? Image.network(
                                            senderPhoto,
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, e, s) => Center(
                                              child: Text(
                                                initials,
                                                style: GoogleFonts.inter(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          )
                                        : Center(
                                            child: Text(
                                              initials,
                                              style: GoogleFonts.inter(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: GoogleFonts.inter(color: textColor, fontSize: 13.5),
                                      children: [
                                        TextSpan(
                                          text: '$senderName ',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        TextSpan(
                                          text: messageText,
                                          style: TextStyle(
                                            color: isDark ? Colors.white70 : OhtliColors.onyx.withOpacity(0.85),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (type == 'friend_request' && status == 'pending') ...[
                                  const SizedBox(width: 16),
                                  actionButtons,
                                ],
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: OhtliColors.stormyTeal,
                                      ),
                                      child: ClipOval(
                                        child: senderPhoto != null && senderPhoto.isNotEmpty
                                            ? Image.network(
                                                senderPhoto,
                                                fit: BoxFit.cover,
                                                errorBuilder: (c, e, s) => Center(
                                                  child: Text(
                                                    initials,
                                                    style: GoogleFonts.inter(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : Center(
                                                child: Text(
                                                  initials,
                                                  style: GoogleFonts.inter(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: GoogleFonts.inter(color: textColor, fontSize: 13.5),
                                          children: [
                                            TextSpan(
                                              text: '$senderName ',
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                            TextSpan(
                                              text: messageText,
                                              style: TextStyle(
                                                color: isDark ? Colors.white70 : OhtliColors.onyx.withOpacity(0.85),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (type == 'friend_request' && status == 'pending') ...[
                                  const SizedBox(height: 14),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      actionButtons,
                                    ],
                                  ),
                                ],
                              ],
                            ),
                    );

                    if (isClickable) {
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            // For co_author_added, use tripOwnerId since senderId is the person who added them
                            final String navAuthorId = (type == 'co_author_added' && data['tripOwnerId'] != null)
                                ? data['tripOwnerId']
                                : senderId;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TripViewerPage(
                                  tripId: data['tripId'],
                                  authorId: navAuthorId,
                                ),
                              ),
                            );
                          },
                          child: cardContent,
                        ),
                      );
                    } else {
                      return cardContent;
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
