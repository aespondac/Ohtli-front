import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/colors.dart';
import 'construction_page.dart'; // Reuse RouteBackgroundPainter
import 'trips/trips_dashboard_page.dart';

class HomePage extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onNavigateToAccount;

  const HomePage({
    super.key,
    required this.onLogout,
    required this.onNavigateToAccount,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _sidebarCollapsed = false;
  bool _isHoveringLogout = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _localPhotoURL;
  int _currentIndex = 0;
  bool _isHoveringInicio = false;
  bool _isHoveringMisViajes = false;

  @override
  void initState() {
    super.initState();
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

  Widget _buildSidebarItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    required bool isHovered,
    required ValueChanged<bool> onHover,
  }) {
    final bool isActive = _currentIndex == index;
    final bool isCollapsed = _sidebarCollapsed;

    Color itemColor = isActive
        ? OhtliColors.stormyTeal
        : (isHovered ? OhtliColors.xoconostle : OhtliColors.onyx.withOpacity(0.7));

    Widget content = Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: EdgeInsets.symmetric(
        horizontal: isCollapsed ? 0 : 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: isActive
            ? OhtliColors.cloudDancer.withOpacity(0.8)
            : (isHovered ? Colors.white.withOpacity(0.3) : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(
            isActive ? activeIcon : icon,
            color: itemColor,
            size: 20,
          ),
          if (!isCollapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: itemColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (isCollapsed) {
      content = Tooltip(
        message: label,
        decoration: BoxDecoration(
          color: OhtliColors.onyx.withOpacity(0.8),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: GoogleFonts.inter(color: Colors.white, fontSize: 11),
        child: content,
      );
    }

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        child: content,
      ),
    );
  }

  Widget _buildBody(bool isMobile) {
    if (_currentIndex == 1) {
      return const TripsDashboardPage();
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

    const colorSidebar = Color(0xFFE4E1DA);

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
          unselectedItemColor: OhtliColors.onyx.withOpacity(0.4),
          selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11),
          unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore_rounded),
              label: 'Inicio',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map_rounded),
              label: 'Mis Viajes',
            ),
          ],
        ),
      );
    }

    final sidebarWidth = _sidebarCollapsed ? 64.0 : 200.0;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: OhtliColors.cloudDancer,
      body: Row(
        children: [
          // ========= SIDEBAR =========
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: sidebarWidth,
            decoration: const BoxDecoration(
              color: colorSidebar,
              border: Border(
                right: BorderSide(color: Color(0xFFD1CDC4), width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top: Isologo (collapsed) or Logo + collapse button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(
                    children: [
                      if (_sidebarCollapsed) ...
                        [
                          Expanded(
                            child: Center(
                              child: SvgPicture.asset(
                                'assets/icon_isologo.svg',
                                height: 26,
                                fit: BoxFit.contain,
                                colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                              ),
                            ),
                          ),
                        ]
                      else ...
                        [
                          Expanded(
                            child: SvgPicture.asset(
                              'assets/logo.svg',
                              height: 22,
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.keyboard_arrow_left_rounded,
                                size: 18,
                                color: OhtliColors.stormyTeal,
                              ),
                            ),
                          ),
                        ],
                    ],
                  ),
                ),

                // Expand button when collapsed (centered below isologo)
                if (_sidebarCollapsed)
                  Center(
                    child: InkWell(
                      onTap: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: const Icon(
                          Icons.keyboard_arrow_right_rounded,
                          size: 18,
                          color: OhtliColors.stormyTeal,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),
                _buildSidebarItem(
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore_rounded,
                  label: 'Inicio',
                  index: 0,
                  isHovered: _isHoveringInicio,
                  onHover: (hovered) => setState(() => _isHoveringInicio = hovered),
                ),
                _buildSidebarItem(
                  icon: Icons.map_outlined,
                  activeIcon: Icons.map_rounded,
                  label: 'Mis Viajes',
                  index: 1,
                  isHovered: _isHoveringMisViajes,
                  onHover: (hovered) => setState(() => _isHoveringMisViajes = hovered),
                ),
                const Spacer(),

                // Bottom: Avatar + Name + Logout (clickable avatar opens panel)
                const Divider(height: 1, color: Color(0xFFD1CDC4)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      _buildAvatarWidget(
                        radius: 16,
                        initials: initials,
                        photoURL: _localPhotoURL,
                        onTap: widget.onNavigateToAccount,
                      ),
                      if (!_sidebarCollapsed) ...
                        [
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: widget.onNavigateToAccount,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Text(
                                  displayName.split(' ').first,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: OhtliColors.onyx.withOpacity(0.8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          MouseRegion(
                            onEnter: (_) => setState(() => _isHoveringLogout = true),
                            onExit: (_) => setState(() => _isHoveringLogout = false),
                            child: InkWell(
                              onTap: _handleLogout,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.logout_rounded,
                                  size: 17,
                                  color: _isHoveringLogout
                                      ? OhtliColors.xoconostle
                                      : OhtliColors.stormyTeal,
                                ),
                              ),
                            ),
                          ),
                        ]
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            ),
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
            painter: RouteBackgroundPainter(OhtliColors.cantera.withOpacity(0.95)),
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
                  color: OhtliColors.onyx.withOpacity(0.4),
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
                color: OhtliColors.onyx.withOpacity(0.4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
