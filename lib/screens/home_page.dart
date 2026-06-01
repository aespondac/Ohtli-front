// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/colors.dart';
import '../widgets/ohtli_sidebar.dart';
import 'construction_page.dart'; // Reuse RouteBackgroundPainter
import 'trips/trips_dashboard_page.dart';
import 'trips/trip_viewer_page.dart';
import 'account/public_profile_page.dart';
import 'friends_page.dart';
import 'notifications_page.dart';

// Pinned Stories Model & Constant
class PinnedStory {
  final String tripId;
  final String authorId;

  const PinnedStory({required this.tripId, required this.authorId});
}

const List<PinnedStory> kPinnedStories = [
  PinnedStory(
    tripId: '8c945367-4543-403d-8f56-51798d7f4e7d',
    authorId: '4cavo5EKn6Vvuoo2s46VokEj7lE3',
  ),
];

class HomePage extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onNavigateToAccount;
  final int initialIndex;

  const HomePage({
    super.key,
    required this.onLogout,
    required this.onNavigateToAccount,
    this.initialIndex = 0,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Preservar iconos contra tree-shaking en la web
  // ignore: unused_field
  static const List<Icon> _preservedIcons = [
    Icon(Icons.notifications_none),
    Icon(Icons.map_outlined),
    Icon(Icons.map),
    Icon(Icons.person_outline),
    Icon(Icons.person),
    Icon(Icons.emoji_events_outlined),
    Icon(Icons.emoji_events),
    Icon(Icons.place_outlined),
    Icon(Icons.place),
  ];

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _localPhotoURL;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _syncProfilePic();
  }

  void _syncProfilePic() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // 1. Load from localStorage for instant render
      final localPic = html.window.localStorage['ohtli_profile_pic_${user.uid}'];
      if (localPic != null && localPic.isNotEmpty) {
        _localPhotoURL = localPic;
      } else {
        _localPhotoURL = user.photoURL;
      }

      // 2. Fetch from Cloud Firestore to sync and show latest data
      FirebaseFirestore.instance.collection('users').doc(user.uid).get().then((doc) {
        if (doc.exists) {
          final data = doc.data();
          if (data != null && data.containsKey('photoURL')) {
            final String? remotePhoto = data['photoURL'] as String?;
            if (remotePhoto != null && remotePhoto.isNotEmpty) {
              if (mounted) {
                setState(() {
                  _localPhotoURL = remotePhoto;
                });
                // Keep LocalStorage in sync
                html.window.localStorage['ohtli_profile_pic_${user.uid}'] = remotePhoto;
              }
            }
          }
        }
      }).catchError((e) {
        print("Error syncing profile pic from Firestore: $e");
      });
    } else {
      _localPhotoURL = null;
    }
  }

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      widget.onLogout();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cerrar sesión: ${e.toString()}'),
            backgroundColor: OhtliColors.xoconostle,
          ),
        );
      }
    }
  }

  Widget _buildAvatarWidget({
    required double radius,
    required String initials,
    required String? photoURL,
    VoidCallback? onTap,
  }) {
    Widget avatarContent;
    if (photoURL != null && photoURL.isNotEmpty) {
      if (photoURL.startsWith('data:image') || photoURL.startsWith('data:')) {
        try {
          final String base64Data = photoURL.split(',').last;
          final Uint8List decodedBytes = base64.decode(base64Data);
          avatarContent = ClipOval(
            child: Image.memory(
              decodedBytes,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
            ),
          );
        } catch (e) {
          avatarContent = Center(
            child: Text(
              initials,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: radius * 0.7,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
      } else {
        avatarContent = ClipOval(
          child: Image.network(
            photoURL,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Text(
                  initials,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: radius * 0.7,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        );
      }
    } else {
      avatarContent = Center(
        child: Text(
          initials,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: radius * 0.7,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    Widget mainAvatar = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: OhtliColors.stormyTeal,
      ),
      child: avatarContent,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: mainAvatar,
        ),
      );
    }

    return mainAvatar;
  }

  Widget _buildBody(bool isMobile) {
    if (_currentIndex == 1) {
      return const TripsDashboardPage();
    }
    if (_currentIndex == 2) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        return PublicProfilePage(userId: user.uid);
      }
    }
    if (_currentIndex == 3) {
      return const FriendsPage();
    }
    if (_currentIndex == 4 || _currentIndex == 5) {
      return ConstructionPage(onLoginClick: () {});
    }
    if (_currentIndex == 6) {
      return const NotificationsPage();
    }
    return _buildMainContent(isMobile);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final localPic = html.window.localStorage['ohtli_profile_pic_${user.uid}'];
      if (localPic != null && localPic.isNotEmpty) {
        _localPhotoURL = localPic;
      }
    }

    final displayName = user?.displayName ?? user?.email ?? 'Viajero';
    final initials = displayName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 800;

    final bool isDark = OhtliSettings.instance.isDarkMode;
    final colorSidebar = isDark ? const Color(0xFF1E1E22) : const Color(0xFFE4E1DA);

    if (isMobile) {
      return Scaffold(
        key: _scaffoldKey,
        backgroundColor: OhtliColors.cloudDancer,
        appBar: AppBar(
          backgroundColor: colorSidebar,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: Padding(
            padding: const EdgeInsets.all(10),
            child: SvgPicture.asset(
              'assets/icon_isologo.svg',
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_none, color: OhtliColors.stormyTeal, size: 20),
              onPressed: () {
                setState(() {
                  _currentIndex = 6;
                });
              },
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
              child: _buildAvatarWidget(
                radius: 18,
                initials: initials,
                photoURL: _localPhotoURL,
                onTap: widget.onNavigateToAccount,
              ),
            ),
          ],
        ),
        body: _buildBody(isMobile),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex == 1
              ? 0
              : (_currentIndex == 2
                  ? 1
                  : (_currentIndex == 0
                      ? 2
                      : (_currentIndex == 4
                          ? 3
                          : (_currentIndex == 5 ? 4 : 2)))),
          onTap: (index) {
            setState(() {
              if (index == 0) _currentIndex = 1; // Mis Viajes
              if (index == 1) _currentIndex = 2; // Perfil
              if (index == 2) _currentIndex = 0; // Explorar
              if (index == 3) _currentIndex = 4; // Logros
              if (index == 4) _currentIndex = 5; // Lugares
            });
          },
          backgroundColor: colorSidebar,
          selectedItemColor: OhtliColors.stormyTeal,
          unselectedItemColor: isDark ? Colors.white38 : OhtliColors.onyx.withOpacity(0.4),
          selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11),
          unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 11),
          type: BottomNavigationBarType.fixed, // Use fixed when >= 4 items
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Mis Viajes',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Perfil',
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                'assets/icon_isologo.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(
                  isDark ? Colors.white38 : OhtliColors.onyx.withOpacity(0.4),
                  BlendMode.srcIn,
                ),
              ),
              activeIcon: SvgPicture.asset(
                'assets/icon_isologo.svg',
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  OhtliColors.stormyTeal,
                  BlendMode.srcIn,
                ),
              ),
              label: 'Explorar',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.emoji_events_outlined),
              activeIcon: Icon(Icons.emoji_events),
              label: 'Logros',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.place_outlined),
              activeIcon: Icon(Icons.place),
              label: 'Lugares',
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: OhtliColors.cloudDancer,
      body: Row(
        children: [
          // ========= SIDEBAR =========
          OhtliSidebar(
            currentIndex: _currentIndex,
            onTabSelected: (index) => setState(() => _currentIndex = index),
            onNavigateToAccount: widget.onNavigateToAccount,
            onLogout: _handleLogout,
          ),

          // ========= MAIN CONTENT =========
          Expanded(
            child: _buildBody(isMobile),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(bool isMobile) {
    final bool isDark = OhtliSettings.instance.isDarkMode;
    
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: RouteBackgroundPainter(OhtliColors.cantera.withOpacity(0.95)),
          ),
        ),
        Positioned.fill(
          child: SafeArea(
            child: SingleChildScrollView(
              // No horizontal padding on ScrollView to allow edge-to-edge hero carousel
              padding: const EdgeInsets.only(bottom: 40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Pinned Stories Carousel (Full Width, edge-to-edge)
                  _buildPinnedStoriesCarousel(isMobile, isDark),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPinnedStoriesCarousel(bool isMobile, bool isDark) {
    // PageController for sliding carousel - full width viewport fraction 1.0!
    final PageController controller = PageController(viewportFraction: 1.0);
    final double height = isMobile ? 260.0 : 380.0;
    
    return SizedBox(
      height: height,
      width: double.infinity,
      child: PageView.builder(
        controller: controller,
        itemCount: kPinnedStories.length,
        itemBuilder: (context, index) {
          final pinned = kPinnedStories[index];
          return _buildPinnedStoryCard(pinned, isMobile, isDark);
        },
      ),
    );
  }

  Widget _buildPinnedStoryCard(PinnedStory pinned, bool isMobile, bool isDark) {
    return FutureBuilder<List<DocumentSnapshot>>(
      future: Future.wait([
        FirebaseFirestore.instance
            .collection('users')
            .doc(pinned.authorId)
            .collection('trips')
            .doc(pinned.tripId)
            .get(),
        FirebaseFirestore.instance
            .collection('users')
            .doc(pinned.authorId)
            .get(),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: EdgeInsets.symmetric(
              horizontal: isMobile ? 16.0 : 24.0,
              vertical: isMobile ? 12.0 : 16.0,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E22) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: OhtliColors.stormyTeal),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data![0].exists == false) {
          return const SizedBox();
        }

        final tripDoc = snapshot.data![0];
        final authorDoc = snapshot.data![1];

        final tripData = tripDoc.data() as Map<String, dynamic>?;
        final authorData = authorDoc.exists ? (authorDoc.data() as Map<String, dynamic>?) : null;

        final String title = tripData?['title'] ?? 'Sin Título';
        final String cover = tripData?['coverUrl'] ?? '';
        final String desc = tripData?['description'] ?? 'Sin descripción.';
        
        final String authorName = authorData?['displayName'] ?? 'Viajero Ohtli';
        final String? authorPhoto = authorData?['photoURL'];
        final String activeTitleId = authorData?['activeTitleId'] ?? 'viajero';

        bool isHovered = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return MouseRegion(
              onEnter: (_) => setState(() => isHovered = true),
              onExit: (_) => setState(() => isHovered = false),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TripViewerPage(
                        tripId: pinned.tripId,
                        authorId: pinned.authorId,
                      ),
                    ),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  margin: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16.0 : 24.0,
                    vertical: isMobile ? 12.0 : 16.0,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: isHovered 
                            ? OhtliColors.stormyTeal.withOpacity(0.15)
                            : Colors.black.withOpacity(0.08),
                        blurRadius: isHovered ? 16 : 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        // Cover Image Background with Zoom Effect on Hover
                        Positioned.fill(
                          child: AnimatedScale(
                            scale: isHovered ? 1.05 : 1.0,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                            child: cover.isNotEmpty
                                ? Image(
                                    image: _getImageProvider(cover),
                                    fit: BoxFit.cover,
                                  )
                                : Container(color: OhtliColors.cantera),
                          ),
                        ),
                        // Premium Dark Gradient Overlay
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withOpacity(0.8),
                                  Colors.black.withOpacity(0.1),
                                  Colors.black.withOpacity(0.85),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.45, 1.0],
                              ),
                            ),
                          ),
                        ),
                        // Badge: "CRÓNICA DESTACADA"
                        Positioned(
                          top: isMobile ? 16 : 24,
                          left: isMobile ? 16 : 24,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: OhtliColors.xoconostle,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.stars_rounded, color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  'CRÓNICA DESTACADA',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        // Content overlay
                        Positioned(
                          bottom: isMobile ? 16 : 32,
                          left: isMobile ? 16 : 32,
                          right: isMobile ? 16 : 32,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: isMobile ? 18 : 22,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                desc,
                                style: GoogleFonts.inter(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 14),
                              // Author Profile Row
                              Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: OhtliColors.stormyTeal,
                                    ),
                                    child: ClipOval(
                                      child: authorPhoto != null && authorPhoto.isNotEmpty
                                          ? Image(
                                              image: _getImageProvider(authorPhoto),
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) => Center(
                                                child: Text(
                                                  authorName.substring(0, 1).toUpperCase(),
                                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            )
                                          : Center(
                                              child: Text(
                                                authorName.substring(0, 1).toUpperCase(),
                                                style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          authorName,
                                          style: GoogleFonts.outfit(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        StreamBuilder<DocumentSnapshot>(
                                          stream: FirebaseFirestore.instance
                                              .collection('titles')
                                              .doc(activeTitleId)
                                              .snapshots(),
                                          builder: (context, titleSnapshot) {
                                            String titleName = 'Viajero';
                                            if (titleSnapshot.hasData && titleSnapshot.data!.exists) {
                                              final titleData = titleSnapshot.data!.data() as Map<String, dynamic>?;
                                              titleName = titleData?['name'] ?? 'Viajero';
                                            }
                                            return Text(
                                              titleName,
                                              style: GoogleFonts.inter(
                                                color: Colors.white.withOpacity(0.6),
                                                fontSize: 10,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Read Action Indicator
                                  Row(
                                    children: [
                                      Text(
                                        'Leer historia',
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 12),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  ImageProvider _getImageProvider(String url) {
    if (url.startsWith('data:')) {
      final String base64Data = url.split(',').last;
      return MemoryImage(base64Decode(base64Data));
    }
    return NetworkImage(url);
  }
}
