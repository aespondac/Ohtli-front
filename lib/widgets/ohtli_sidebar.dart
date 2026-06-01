// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print

import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/colors.dart';

class OhtliSidebar extends StatefulWidget {
  final int currentIndex; // 0: Inicio, 1: Mis Viajes, 2: Account/Mi Cuenta (non-tab)
  final Function(int) onTabSelected;
  final VoidCallback onNavigateToAccount;
  final VoidCallback onLogout;

  const OhtliSidebar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onNavigateToAccount,
    required this.onLogout,
  });

  @override
  State<OhtliSidebar> createState() => _OhtliSidebarState();
}

class _OhtliSidebarState extends State<OhtliSidebar> {
  // Preservar iconos contra tree-shaking
  // ignore: unused_field
  static const List<Icon> _preservedIcons = [
    Icon(Icons.map_outlined),
    Icon(Icons.map_rounded),
    Icon(Icons.person_outline),
    Icon(Icons.person),
    Icon(Icons.people_outline),
    Icon(Icons.people),
    Icon(Icons.emoji_events_outlined),
    Icon(Icons.emoji_events),
    Icon(Icons.place_outlined),
    Icon(Icons.place),
    Icon(Icons.notifications_none),
    Icon(Icons.notifications),
    Icon(Icons.keyboard_arrow_left_rounded),
    Icon(Icons.keyboard_arrow_right_rounded),
    Icon(Icons.logout_rounded),
  ];

  static bool _isCollapsed = false;
  static bool _hasLoadedState = false;

  bool _isHoveringInicio = false;
  bool _isHoveringMisViajes = false;
  bool _isHoveringPerfil = false;
  bool _isHoveringAmigos = false;
  bool _isHoveringLogros = false;
  bool _isHoveringLugares = false;
  bool _isHoveringNotificaciones = false;
  bool _isHoveringLogout = false;
  String? _localPhotoURL;

  @override
  void initState() {
    super.initState();
    _syncProfilePic();
    if (!_hasLoadedState && kIsWeb) {
      try {
        final saved = html.window.localStorage['ohtli_sidebar_collapsed'];
        if (saved != null) {
          _isCollapsed = saved == 'true';
        }
      } catch (e) {
        print("Error reading sidebar collapsed state: $e");
      }
      _hasLoadedState = true;
    }
  }

  void _syncProfilePic() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && kIsWeb) {
      try {
        final localPic = html.window.localStorage['ohtli_profile_pic_${user.uid}'];
        if (localPic != null && localPic.isNotEmpty) {
          setState(() {
            _localPhotoURL = localPic;
          });
        }
      } catch (e) {
        print("Error syncing profile pic in sidebar: $e");
      }
    }
  }

  void _toggleCollapsed() {
    setState(() {
      _isCollapsed = !_isCollapsed;
      if (kIsWeb) {
        try {
          html.window.localStorage['ohtli_sidebar_collapsed'] = _isCollapsed.toString();
        } catch (e) {
          print("Error saving sidebar collapsed state: $e");
        }
      }
    });
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

  Widget _buildItemIcon(dynamic iconData, Color color) {
    if (iconData is IconData) {
      return Icon(iconData, color: color, size: 20);
    } else if (iconData is String) {
      return SvgPicture.asset(
        iconData,
        width: 20,
        height: 20,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSidebarItem({
    required dynamic icon,
    required dynamic activeIcon,
    required String label,
    required int index,
    required bool isHovered,
    required ValueChanged<bool> onHover,
  }) {
    final bool isActive = widget.currentIndex == index;
    final bool isCollapsed = _isCollapsed;

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
          _buildItemIcon(isActive ? activeIcon : icon, itemColor),
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
        onTap: () {
          widget.onTabSelected(index);
        },
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncProfilePic();
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? user?.email ?? 'Viajero';
    final initials = displayName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    final bool isDark = OhtliSettings.instance.isDarkMode;
    final colorSidebar = isDark ? const Color(0xFF1E1E22) : const Color(0xFFE4E1DA);
    final colorBorder = isDark ? const Color(0xFF2C2C32) : const Color(0xFFD1CDC4);
    final sidebarWidth = _isCollapsed ? 64.0 : 200.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: colorSidebar,
        border: Border(
          right: BorderSide(color: colorBorder, width: 1),
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
                if (_isCollapsed) ...[
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: widget.onNavigateToAccount,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: SvgPicture.asset(
                            'assets/icon_isologo.svg',
                            height: 26,
                            fit: BoxFit.contain,
                            colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onNavigateToAccount,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: SvgPicture.asset(
                          'assets/logo.svg',
                          height: 22,
                          fit: BoxFit.contain,
                          alignment: Alignment.centerLeft,
                          colorFilter: const ColorFilter.mode(OhtliColors.stormyTeal, BlendMode.srcIn),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: _toggleCollapsed,
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
          if (_isCollapsed)
            Center(
              child: InkWell(
                onTap: _toggleCollapsed,
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
            icon: 'assets/icon_isologo.svg',
            activeIcon: 'assets/icon_isologo.svg',
            label: 'Explorar',
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
          _buildSidebarItem(
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            label: 'Perfil',
            index: 2,
            isHovered: _isHoveringPerfil,
            onHover: (hovered) => setState(() => _isHoveringPerfil = hovered),
          ),
          _buildSidebarItem(
            icon: Icons.people_outline,
            activeIcon: Icons.people,
            label: 'Amigos',
            index: 3,
            isHovered: _isHoveringAmigos,
            onHover: (hovered) => setState(() => _isHoveringAmigos = hovered),
          ),
          _buildSidebarItem(
            icon: Icons.emoji_events_outlined,
            activeIcon: Icons.emoji_events,
            label: 'Logros',
            index: 4,
            isHovered: _isHoveringLogros,
            onHover: (hovered) => setState(() => _isHoveringLogros = hovered),
          ),
          _buildSidebarItem(
            icon: Icons.place_outlined,
            activeIcon: Icons.place,
            label: 'Lugares',
            index: 5,
            isHovered: _isHoveringLugares,
            onHover: (hovered) => setState(() => _isHoveringLugares = hovered),
          ),
          _buildSidebarItem(
            icon: Icons.notifications_none,
            activeIcon: Icons.notifications,
            label: 'Notificaciones',
            index: 6,
            isHovered: _isHoveringNotificaciones,
            onHover: (hovered) => setState(() => _isHoveringNotificaciones = hovered),
          ),
          const Spacer(),

          // Bottom: Avatar + Name + Logout (clickable avatar/name navigates to Account)
          Divider(height: 1, color: colorBorder),
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
                if (!_isCollapsed) ...[
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
                      onTap: widget.onLogout,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.logout_rounded,
                          size: 17,
                          color: _isHoveringLogout
                              ? OhtliColors.xoconostle
                              : OhtliColors.onyx.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
