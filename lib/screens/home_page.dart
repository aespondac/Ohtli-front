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
import 'construction_page.dart';
import 'trips/trips_dashboard_page.dart';
import 'explore/explore_page.dart';
import 'account/public_profile_page.dart';
import 'friends_page.dart';
import 'notifications_page.dart';
import 'places/places_page.dart';
import '../widgets/trip_planner_dialog.dart';

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
    Icon(Icons.explore_outlined),
    Icon(Icons.explore),
  ];

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _localPhotoURL;
  int _currentIndex = 0;

  // Barra inferior (móvil): Explorar, Mis Viajes, Lugares, Amigos, Perfil → índices de página
  static const List<int> _bottomNavPages = [0, 1, 5, 3, 2];
  int _lastBottomNavIndex = 0;

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
      widget.onLogout();
      await FirebaseAuth.instance.signOut();
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
    if (_currentIndex == 4) {
      return const ConstructionPage();
    }
    if (_currentIndex == 5) {
      return const PlacesPage();
    }
    if (_currentIndex == 6) {
      return const NotificationsPage();
    }
    return ExplorePage(
      onOpenTab: (index) => setState(() => _currentIndex = index),
      onPlanTrip: _openTripPlanner,
    );
  }

  void _openTripPlanner() {
    TripPlannerDialog.show(
      context,
      onManualPlanSelected: () => setState(() => _currentIndex = 1),
    );
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
            if (user != null)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .collection('notifications')
                    .where('read', isEqualTo: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  int unreadCount = 0;
                  if (snapshot.hasData) {
                    final now = DateTime.now();
                    unreadCount = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final String? type = data['type'] as String?;
                      final Timestamp? ts = data['timestamp'] as Timestamp?;
                      if (ts == null) return true;
                      if (type == 'surprise_plan') {
                        return !now.isBefore(ts.toDate());
                      }
                      return true;
                    }).length;
                  }

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_none, color: OhtliColors.stormyTeal, size: 20),
                        onPressed: () {
                          setState(() {
                            _currentIndex = 6;
                          });
                        },
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: OhtliColors.xoconostle,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 14,
                              minHeight: 14,
                            ),
                            child: Center(
                              child: Text(
                                '$unreadCount',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              )
            else
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
        floatingActionButton: FloatingActionButton(
          heroTag: 'fab_plan_trip_mobile',
          onPressed: () {
            TripPlannerDialog.show(
              context,
              onManualPlanSelected: () => setState(() => _currentIndex = 1),
            );
          },
          backgroundColor: OhtliColors.stormyTeal,
          elevation: 6,
          child: SvgPicture.asset(
            'assets/icon_isologo.svg',
            width: 22,
            height: 22,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          // En pantallas fuera de la barra (p. ej. Notificaciones) se mantiene la última pestaña
          currentIndex: _bottomNavPages.contains(_currentIndex)
              ? (_lastBottomNavIndex = _bottomNavPages.indexOf(_currentIndex))
              : _lastBottomNavIndex,
          onTap: (index) {
            setState(() {
              _lastBottomNavIndex = index;
              _currentIndex = _bottomNavPages[index];
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
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore),
              label: 'Explorar',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Mis Viajes',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.place_outlined),
              activeIcon: Icon(Icons.place),
              label: 'Lugares',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              activeIcon: Icon(Icons.people_rounded),
              label: 'Amigos',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Perfil',
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: OhtliColors.cloudDancer,
      // Sin botón flotante en escritorio: el menú lateral ya tiene "Planea un viaje" siempre visible
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

}
