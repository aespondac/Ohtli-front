import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/colors.dart';
import 'home_page.dart'; // For OhtliSettings

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;

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
            .doc(_currentUser!.uid)
            .collection('notifications')
            .doc(notificationId)
            .update({
          'status': 'accepted',
        });

        // 3. Add Bob to Alice's friends list
        await firestore.collection('users').doc(senderId).update({
          'friends': FieldValue.arrayUnion([_currentUser!.uid]),
        });

        // 4. Add Alice to Bob's friends list
        await firestore.collection('users').doc(_currentUser!.uid).update({
          'friends': FieldValue.arrayUnion([senderId]),
        });

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
            .doc(_currentUser!.uid)
            .collection('notifications')
            .doc(notificationId)
            .update({
          'status': 'declined',
        });

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

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Notificaciones',
          style: GoogleFonts.outfit(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('notifications')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: OhtliColors.stormyTeal),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 64,
                    color: isDark ? Colors.white24 : OhtliColors.cantera,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No tienes notificaciones todavía.',
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white54 : OhtliColors.onyx.withValues(alpha: 0.5),
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

              String messageText = '';
              if (type == 'friend_request') {
                if (status == 'pending') {
                  messageText = 'te envió una solicitud de amistad.';
                } else if (status == 'accepted') {
                  messageText = 'y tú ahora son amigos.';
                } else {
                  messageText = 'te envió una solicitud (rechazada).';
                }
              }

              final initials = senderName
                  .split(' ')
                  .where((w) => w.isNotEmpty)
                  .take(2)
                  .map((w) => w[0].toUpperCase())
                  .join();

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
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
                          child: Center(
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
                                    color: isDark ? Colors.white70 : OhtliColors.onyx.withValues(alpha: 0.85),
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
                          OutlinedButton(
                            onPressed: () => _handleFriendRequest(doc.id, senderId, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: OhtliColors.xoconostle,
                              side: const BorderSide(color: OhtliColors.xoconostle, width: 1.2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              minimumSize: Size.zero,
                            ),
                            child: Text(
                              'Rechazar',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () => _handleFriendRequest(doc.id, senderId, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: OhtliColors.stormyTeal,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              minimumSize: Size.zero,
                            ),
                            child: Text(
                              'Aceptar',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
