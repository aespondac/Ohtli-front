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
import 'account/public_profile_page.dart';

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
    if (_currentIndex == 3 || _currentIndex == 4) {
      return ConstructionPage(onLoginClick: () {});
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
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: colorSidebar,
          selectedItemColor: OhtliColors.stormyTeal,
          unselectedItemColor: isDark ? Colors.white38 : OhtliColors.onyx.withValues(alpha: 0.4),
          selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11),
          unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 11),
          items: [
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                'assets/icon_isologo.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(
                  isDark ? Colors.white38 : OhtliColors.onyx.withValues(alpha: 0.4),
                  BlendMode.srcIn,
                ),
              ),
              activeIcon: SvgPicture.asset(
                'assets/icon_isologo.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(
                  OhtliColors.stormyTeal,
                  BlendMode.srcIn,
                ),
              ),
              label: 'Explorar',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map_rounded),
              label: 'Mis Viajes',
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

  Widget _buildMainContent(
    bool isMobile,
  ) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: RouteBackgroundPainter(OhtliColors.cantera.withValues(alpha: 0.95)),
          ),
        ),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 280, maxHeight: 90),
                child: SvgPicture.asset(
                  'assets/logo.svg',
                  width: 200,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Text(
                    'Ohtli',
                    style: GoogleFonts.inter(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: OhtliColors.stormyTeal,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'el viaje empieza aquí',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 20 : 26,
                  fontWeight: FontWeight.w300,
                  color: OhtliColors.onyx,
                  letterSpacing: 2.0,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'próximamente',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w300,
                  color: OhtliColors.onyx.withValues(alpha: 0.4),
                  letterSpacing: 3.0,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              'ohtli  •  cdmx',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w300,
                letterSpacing: 4.0,
                color: OhtliColors.onyx.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
