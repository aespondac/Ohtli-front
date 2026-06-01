import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/colors.dart';
import 'account/public_profile_page.dart'; // To visit their profile!
import 'construction_page.dart'; // To reuse RouteBackgroundPainter

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleFriendStatus(String targetUserId, String action) async {
    if (_currentUser == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(_currentUser.uid);

    try {
      if (action == 'none') {
        // Remove friendship mutually
        await docRef.update({
          'friends': FieldValue.arrayRemove([targetUserId]),
          'closeFriends': FieldValue.arrayRemove([targetUserId]),
        });
        await FirebaseFirestore.instance.collection('users').doc(targetUserId).update({
          'friends': FieldValue.arrayRemove([_currentUser.uid]),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Amistad removida.', style: GoogleFonts.inter()),
              backgroundColor: OhtliColors.stormyTeal,
            ),
          );
        }
      } else if (action == 'friend') {
        // Keep as friend, remove from close friends
        await docRef.update({
          'closeFriends': FieldValue.arrayRemove([targetUserId]),
        });
      } else if (action == 'closeFriend') {
        // Add to close friends (user is the ONLY ONE choosing their close friends)
        await docRef.update({
          'closeFriends': FieldValue.arrayUnion([targetUserId]),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('¡Añadido a tus Mejores Amigos!', style: GoogleFonts.inter()),
              backgroundColor: OhtliColors.stormyTeal,
            ),
          );
        }
      }
    } catch (e) {
      print("Error changing friend status: $e");
    }
  }

  Future<void> _sendFriendRequest(String targetUserId, String targetName, String? targetPhoto) async {
    if (_currentUser == null) return;

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Create a top-level friend request
      final docRef = await firestore.collection('friend_requests').add({
        'senderId': _currentUser.uid,
        'senderName': _currentUser.displayName ?? 'Un viajero',
        'senderPhoto': _currentUser.photoURL,
        'receiverId': targetUserId,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. Add notification inside target user's private subcollection
      await firestore
          .collection('users')
          .doc(targetUserId)
          .collection('notifications')
          .doc(docRef.id)
          .set({
        'type': 'friend_request',
        'senderId': _currentUser.uid,
        'senderName': _currentUser.displayName ?? 'Un viajero',
        'senderPhoto': _currentUser.photoURL,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Solicitud de amistad enviada a $targetName!', style: GoogleFonts.inter()),
            backgroundColor: OhtliColors.stormyTeal,
          ),
        );
      }
    } catch (e) {
      print("Error sending friend request: $e");
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
            'Inicia sesión para ver tu lista de amigos.',
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
        toolbarHeight: 80,
        title: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding - 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Amigos',
                style: GoogleFonts.inter(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Conéctate y comparte con otros viajeros',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: textColor.withOpacity(0.5),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: OhtliColors.stormyTeal,
              indicatorWeight: 3,
              labelColor: OhtliColors.stormyTeal,
              unselectedLabelColor: textColor.withOpacity(0.5),
              labelStyle: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              unselectedLabelStyle: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              tabs: const [
                Tab(text: 'Tus Amigos'),
                Tab(text: 'Mejores Amigos'),
                Tab(text: 'Sugeridos'),
              ],
            ),
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
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(_currentUser.uid).snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
                }

                final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                final List<dynamic> friends = userData?['friends'] ?? [];
                final List<dynamic> closeFriends = userData?['closeFriends'] ?? [];

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').snapshots(),
                  builder: (context, usersSnapshot) {
                    if (usersSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal));
                    }

                    final allUsers = usersSnapshot.data?.docs ?? [];
                    
                    // 1. Filter friends
                    var friendUsers = allUsers.where((doc) => friends.contains(doc.id)).toList();
                    
                    // 2. Filter suggested (everyone except ourselves and our friends)
                    var suggestedUsers = allUsers.where((doc) => doc.id != _currentUser.uid && !friends.contains(doc.id)).toList();

                    // Apply search query filter if search is active
                    if (_searchQuery.isNotEmpty) {
                      friendUsers = friendUsers.where((doc) {
                        final name = (doc.data() as Map<String, dynamic>)['displayName'] ?? '';
                        return name.toLowerCase().contains(_searchQuery.toLowerCase());
                      }).toList();

                      suggestedUsers = suggestedUsers.where((doc) {
                        final name = (doc.data() as Map<String, dynamic>)['displayName'] ?? '';
                        return name.toLowerCase().contains(_searchQuery.toLowerCase());
                      }).toList();
                    }

                    return Column(
                      children: [
                        // Search Bar
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (val) {
                              setState(() {
                                _searchQuery = val;
                              });
                            },
                            decoration: InputDecoration(
                              hintText: 'Buscar aventureros...',
                              hintStyle: GoogleFonts.inter(
                                color: isDark ? Colors.white38 : OhtliColors.onyx.withOpacity(0.4),
                                fontSize: 13,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: isDark ? Colors.white38 : OhtliColors.onyx.withOpacity(0.5),
                                size: 20,
                              ),
                              filled: true,
                              fillColor: cardColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                            ),
                            style: GoogleFonts.inter(color: textColor, fontSize: 13),
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildFriendsList(friendUsers, closeFriends, cardColor, textColor, isDark, isSuggested: false, onlyCloseFriends: false),
                              _buildFriendsList(friendUsers, closeFriends, cardColor, textColor, isDark, isSuggested: false, onlyCloseFriends: true),
                              _buildFriendsList(suggestedUsers, closeFriends, cardColor, textColor, isDark, isSuggested: true, onlyCloseFriends: false),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsList(
    List<DocumentSnapshot> list,
    List<dynamic> closeFriends,
    Color cardColor,
    Color textColor,
    bool isDark, {
    required bool isSuggested,
    bool onlyCloseFriends = false,
  }) {
    final displayedList = onlyCloseFriends
        ? list.where((doc) => closeFriends.contains(doc.id)).toList()
        : list;

    if (displayedList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40.0),
          child: Text(
            isSuggested
                ? 'No hay sugerencias disponibles.'
                : (onlyCloseFriends
                    ? 'No tienes mejores amigos asignados aún.'
                    : 'Aún no tienes amigos en tu lista.'),
            style: GoogleFonts.inter(
              color: isDark ? Colors.white38 : OhtliColors.onyx.withOpacity(0.5),
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: displayedList.length,
      itemBuilder: (context, index) {
        final doc = displayedList[index];
        final friendId = doc.id;
        final data = doc.data() as Map<String, dynamic>;
        
        final String name = data['displayName'] ?? 'Viajero Ohtli';
        final String? photoURL = data['photoURL'];
        final String activeTitleId = data['activeTitleId'] ?? 'viajero';
        final bool isCloseFriend = closeFriends.contains(friendId);

        final initials = name
            .split(' ')
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          child: Row(
            children: [
              // Avatar
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PublicProfilePage(userId: friendId, showBackButton: true, onBack: () => Navigator.pop(context)),
                    ),
                  );
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: OhtliColors.stormyTeal,
                    ),
                    child: ClipOval(
                      child: photoURL != null && photoURL.isNotEmpty
                          ? Image.network(photoURL, fit: BoxFit.cover, errorBuilder: (c, e, s) => Center(
                              child: Text(
                                initials,
                                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ))
                          : Center(
                              child: Text(
                                initials,
                                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Name and title
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PublicProfilePage(userId: friendId, showBackButton: true, onBack: () => Navigator.pop(context)),
                      ),
                    );
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.outfit(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (isCloseFriend) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.star_rounded, color: OhtliColors.stormyTeal, size: 14),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('titles').doc(activeTitleId).snapshots(),
                          builder: (context, titleSnapshot) {
                            String titleName = 'Viajero';
                            if (titleSnapshot.hasData && titleSnapshot.data!.exists) {
                              final titleData = titleSnapshot.data!.data() as Map<String, dynamic>?;
                              titleName = titleData?['name'] ?? 'Viajero';
                            }
                            return Text(
                              titleName,
                              style: GoogleFonts.inter(
                                color: isDark ? Colors.white38 : OhtliColors.onyx.withOpacity(0.5),
                                fontSize: 11,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Action Buttons
              if (isSuggested)
                ElevatedButton(
                  onPressed: () => _sendFriendRequest(friendId, name, photoURL),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OhtliColors.stormyTeal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  child: Text(
                    'Añadir amigo',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                PopupMenuButton<String>(
                  onSelected: (action) => _toggleFriendStatus(friendId, action),
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: 'none',
                      child: Text('Eliminar Amigo'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'friend',
                      child: Text('Amigo Normal'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'closeFriend',
                      child: Text('Mejor Amigo'),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCloseFriend ? OhtliColors.stormyTeal : OhtliColors.cantera.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isCloseFriend ? 'Mejor Amigo' : 'Amigo',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isCloseFriend ? Colors.white : OhtliColors.onyx,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
