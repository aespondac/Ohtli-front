// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui' show lerpDouble;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/colors.dart';
import 'trip_planner_dialog.dart';

/// Verde de marca para texto e iconos: en modo oscuro se aclara para mantener
/// buen contraste sobre el fondo del menú (el stormyTeal original casi no se lee).
Color get _accent => OhtliSettings.instance.isDarkMode ? const Color(0xFF7FC4CC) : OhtliColors.stormyTeal;

/// Menú lateral de escritorio.
///
/// Dinámica:
/// - Por defecto está contraído (solo iconos) y no estorba al contenido.
/// - Si dejas el puntero encima ~2 s se despliega *sobre* el contenido (sin
///   empujarlo) y se vuelve a contraer en cuanto el puntero sale o eliges una opción.
/// - Se puede fijar abierto con el botón de la cabecera o con ⌘B / Ctrl+B.
/// - Atajos: ⌥1…⌥6 / Alt+1…Alt+6 para cada sección, ⌥N / Alt+N para planear un
///   viaje, Esc para cerrar el menú desplegado y ? para ver todos los atajos.
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

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final PhysicalKeyboardKey key;
  final String keyLabel;
  const _NavItem(this.icon, this.activeIcon, this.label, this.index, this.key, this.keyLabel);
}

class _OhtliSidebarState extends State<OhtliSidebar> with TickerProviderStateMixin {
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
    Icon(Icons.keyboard_double_arrow_left_rounded),
    Icon(Icons.keyboard_double_arrow_right_rounded),
    Icon(Icons.push_pin_outlined),
    Icon(Icons.keyboard_outlined),
    Icon(Icons.logout_rounded),
    Icon(Icons.explore_outlined),
    Icon(Icons.explore),
    Icon(Icons.add_rounded),
    Icon(Icons.accessibility_new_rounded),
    Icon(Icons.accessibility_new_outlined),
    Icon(Icons.brightness_auto_rounded),
    Icon(Icons.light_mode_rounded),
    Icon(Icons.dark_mode_rounded),
  ];

  static const double _railWidth = 64;
  static const double _panelWidth = 212;
  // Por debajo de este ancho de ventana el menú nunca se queda fijo abierto.
  static const double _narrowBreakpoint = 1100;
  static const Duration _dwell = Duration(seconds: 2);
  static const Duration _leaveGrace = Duration(milliseconds: 280);
  static const String _pinnedKey = 'ohtli_sidebar_pinned';

  static const List<_NavItem> _items = [
    _NavItem(Icons.explore_outlined, Icons.explore, 'Explorar', 0, PhysicalKeyboardKey.digit1, '1'),
    _NavItem(Icons.map_outlined, Icons.map_rounded, 'Mis Viajes', 1, PhysicalKeyboardKey.digit2, '2'),
    _NavItem(Icons.person_outline, Icons.person, 'Perfil', 2, PhysicalKeyboardKey.digit3, '3'),
    _NavItem(Icons.people_outline, Icons.people, 'Amigos', 3, PhysicalKeyboardKey.digit4, '4'),
    _NavItem(Icons.place_outlined, Icons.place, 'Lugares', 5, PhysicalKeyboardKey.digit5, '5'),
    _NavItem(Icons.notifications_none, Icons.notifications, 'Notificaciones', 6, PhysicalKeyboardKey.digit6, '6'),
  ];

  static const _NavItem _accessibilityItem = _NavItem(
    Icons.accessibility_new_outlined,
    Icons.accessibility_new_rounded,
    'Accesibilidad',
    -1,
    PhysicalKeyboardKey.keyA,
    'A',
  );

  // Estado compartido entre las pantallas que muestran el menú.
  static bool _isPinned = false;
  static bool _hasLoadedState = false;

  final OverlayPortalController _peekPortal = OverlayPortalController();
  late final AnimationController _peekCtrl;
  late final AnimationController _dwellCtrl;
  Timer? _collapseTimer;
  Timer? _dwellTimer;
  bool _peekOpen = false;
  bool _accessibilityOpen = false;
  // Tras elegir una opción el puntero sigue encima: no volver a desplegar hasta que salga.
  bool _suppressDwellUntilExit = false;
  bool _isNarrow = false;

  String? _hoveredKey;
  String? _localPhotoURL;

  bool get _isApple => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
  String get _modKey => _isApple ? '⌘' : 'Ctrl+';
  String get _altKey => _isApple ? '⌥' : 'Alt+';
  bool get _effectivePinned => _isPinned && !_isNarrow;

  @override
  void initState() {
    super.initState();
    _peekCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    // Solo visual (la barrita de progreso); el disparo real lo hace _dwellTimer.
    _dwellCtrl = AnimationController(vsync: this, duration: _dwell);
    HardwareKeyboard.instance.addHandler(_handleKey);
    _syncProfilePic();
    if (!_hasLoadedState && kIsWeb) {
      try {
        _isPinned = html.window.localStorage[_pinnedKey] == 'true';
      } catch (e) {
        print("Error reading sidebar pinned state: $e");
      }
      _hasLoadedState = true;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _collapseTimer?.cancel();
    _dwellTimer?.cancel();
    _peekCtrl.dispose();
    _dwellCtrl.dispose();
    super.dispose();
  }

  void _syncProfilePic() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && kIsWeb) {
      try {
        final localPic = html.window.localStorage['ohtli_profile_pic_${user.uid}'];
        if (localPic != null && localPic.isNotEmpty) {
          _localPhotoURL = localPic;
        }
      } catch (e) {
        print("Error syncing profile pic in sidebar: $e");
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Fijar / desplegar
  // ---------------------------------------------------------------------------

  void _togglePin() {
    if (_isNarrow) {
      // En ventanas estrechas no se fija: se despliega temporalmente.
      _peekOpen ? _closePeek() : _openPeek();
      return;
    }
    _cancelDwell();
    _closePeek(immediate: true);
    setState(() => _isPinned = !_isPinned);
    if (kIsWeb) {
      try {
        html.window.localStorage[_pinnedKey] = _isPinned.toString();
      } catch (e) {
        print("Error saving sidebar pinned state: $e");
      }
    }
  }

  void _onRailEnter(PointerEnterEvent _) {
    _collapseTimer?.cancel();
    if (_effectivePinned || _peekOpen || _suppressDwellUntilExit) return;
    _dwellCtrl.forward(from: 0);
    _dwellTimer?.cancel();
    _dwellTimer = Timer(_dwell, _openPeek);
  }

  void _onRailExit(PointerExitEvent _) {
    _cancelDwell();
    _suppressDwellUntilExit = false;
    if (_peekOpen) _scheduleCollapse();
  }

  void _cancelDwell() {
    _dwellTimer?.cancel();
    _dwellCtrl.reset();
  }

  void _scheduleCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(_leaveGrace, () {
      if (mounted) _closePeek();
    });
  }

  void _openPeek() {
    if (!mounted || _effectivePinned) return;
    _collapseTimer?.cancel();
    _cancelDwell();
    if (!_peekOpen) {
      setState(() => _peekOpen = true);
      _peekPortal.show();
    }
    _peekCtrl.forward();
  }

  void _closePeek({bool immediate = false}) {
    _collapseTimer?.cancel();
    if (!_peekOpen) return;
    _peekOpen = false;
    if (immediate || MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _peekCtrl.value = 0;
      _peekPortal.hide();
      if (mounted) setState(() {});
      return;
    }
    _peekCtrl.reverse().whenComplete(() {
      if (!mounted) return;
      if (!_peekOpen && _peekPortal.isShowing) _peekPortal.hide();
      setState(() {});
    });
  }

  // ---------------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------------

  void _select(int index) {
    _suppressDwellUntilExit = true;
    _cancelDwell();
    _closePeek(immediate: true);
    widget.onTabSelected(index);
  }

  void _goToAccount() {
    _suppressDwellUntilExit = true;
    _cancelDwell();
    _closePeek(immediate: true);
    widget.onNavigateToAccount();
  }

  void _openPlanner() {
    _suppressDwellUntilExit = true;
    _cancelDwell();
    _closePeek(immediate: true);
    TripPlannerDialog.show(context, onManualPlanSelected: () => widget.onTabSelected(1));
  }

  // ---------------------------------------------------------------------------
  // Atajos de teclado
  // ---------------------------------------------------------------------------

  bool _isTyping() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    // Solo la pantalla visible responde (puede haber otra con menú debajo en la pila).
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (_isTyping()) return false;

    final hk = HardwareKeyboard.instance;
    final mod = _isApple ? hk.isMetaPressed : hk.isControlPressed;
    final key = event.physicalKey;

    if (mod && !hk.isAltPressed && !hk.isShiftPressed && key == PhysicalKeyboardKey.keyB) {
      _togglePin();
      return true;
    }
    if (hk.isAltPressed && !hk.isMetaPressed && !hk.isControlPressed && !hk.isShiftPressed) {
      for (final item in _items) {
        if (item.key == key) {
          _select(item.index);
          return true;
        }
      }
      if (key == PhysicalKeyboardKey.keyN) {
        _openPlanner();
        return true;
      }
      if (key == _accessibilityItem.key) {
        _openAccessibility();
        return true;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _peekOpen) {
      _suppressDwellUntilExit = true;
      _closePeek();
      return true;
    }
    if (event.character == '?' && !mod && !hk.isAltPressed) {
      _showShortcuts();
      return true;
    }
    return false;
  }

  /// Panel rápido de accesibilidad: tema y tamaño de letra, junto al menú.
  Future<void> _openAccessibility() async {
    if (_accessibilityOpen) return;
    _suppressDwellUntilExit = true;
    _cancelDwell();
    _closePeek(immediate: true);
    final box = context.findRenderObject() as RenderBox?;
    final double left =
        (box != null && box.hasSize ? box.localToGlobal(Offset.zero).dx + box.size.width : _railWidth) + 10;
    setState(() => _accessibilityOpen = true);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar accesibilidad',
      barrierColor: Colors.black.withOpacity(0.08),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, _, _) => Stack(
        children: [
          Positioned(
            left: left,
            bottom: 16,
            child: _AccessibilityPanel(
              onMoreOptions: () {
                Navigator.of(ctx).pop();
                _goToAccount();
              },
            ),
          ),
        ],
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(-0.03, 0.02), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (mounted) setState(() => _accessibilityOpen = false);
  }

  void _showShortcuts() {
    _closePeek(immediate: true);
    final rows = <(String, String)>[
      ('Fijar / contraer el menú', '${_modKey}B'),
      ('Planea un viaje', '${_altKey}N'),
      for (final item in _items) (item.label, '$_altKey${item.keyLabel}'),
      ('Accesibilidad: tema y tamaño de letra', '$_altKey${_accessibilityItem.keyLabel}'),
      ('Cerrar el menú desplegado', 'Esc'),
      ('Ver esta ayuda', '?'),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OhtliColors.cloudDancer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.keyboard_outlined, color: _accent),
            const SizedBox(width: 10),
            Text(
              'Atajos de teclado',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: OhtliColors.onyx),
            ),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.$1,
                          style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx.withOpacity(0.85)),
                        ),
                      ),
                      _KeyCap(r.$2),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'Deja el puntero sobre el menú contraído 2 segundos para desplegarlo.',
                style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx.withOpacity(0.55)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Entendido', style: GoogleFonts.inter(color: _accent)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Construcción
  // ---------------------------------------------------------------------------

  Widget _tooltip({required String message, required Widget child, bool show = true}) {
    if (!show) return child;
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 250),
      preferBelow: true,
      decoration: BoxDecoration(color: OhtliColors.onyx.withOpacity(0.88), borderRadius: BorderRadius.circular(8)),
      textStyle: GoogleFonts.inter(color: OhtliColors.cloudDancer, fontSize: 11),
      child: child,
    );
  }

  Widget _buildAvatarWidget({
    required double radius,
    required String initials,
    required String? photoURL,
    VoidCallback? onTap,
  }) {
    Widget initialsText() => Center(
      child: Text(
        initials,
        style: GoogleFonts.inter(color: Colors.white, fontSize: radius * 0.7, fontWeight: FontWeight.w600),
      ),
    );

    Widget avatarContent;
    if (photoURL != null && photoURL.isNotEmpty) {
      if (photoURL.startsWith('data:')) {
        try {
          final Uint8List decodedBytes = base64.decode(photoURL.split(',').last);
          avatarContent = ClipOval(
            child: Image.memory(decodedBytes, width: radius * 2, height: radius * 2, fit: BoxFit.cover),
          );
        } catch (e) {
          avatarContent = initialsText();
        }
      } else {
        avatarContent = ClipOval(
          child: Image.network(
            photoURL,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => initialsText(),
          ),
        );
      }
    } else {
      avatarContent = initialsText();
    }

    Widget mainAvatar = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: OhtliColors.stormyTeal),
      child: avatarContent,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: MouseRegion(cursor: SystemMouseCursors.click, child: mainAvatar),
      );
    }
    return mainAvatar;
  }

  Widget _buildItemIcon(IconData iconData, Color color) => Icon(iconData, color: color, size: 20);

  Widget _withNotificationBadge(Widget icon) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return icon;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        int count = 0;
        if (snapshot.hasData) {
          final now = DateTime.now();
          count = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final String? type = data['type'] as String?;
            final Timestamp? ts = data['timestamp'] as Timestamp?;
            if (ts == null) return true;
            if (type == 'surprise_plan') return !now.isBefore(ts.toDate());
            return true;
          }).length;
        }
        if (count == 0) return icon;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            icon,
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: const BoxDecoration(color: OhtliColors.xoconostle, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                child: Center(
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSidebarItem(_NavItem item, {required bool expanded, VoidCallback? onTap, bool highlighted = false}) {
    final bool isActive = highlighted || (onTap == null && widget.currentIndex == item.index);
    final String hoverKey = 'item_${item.index}';
    final bool isHovered = _hoveredKey == hoverKey;
    final String shortcut = '$_altKey${item.keyLabel}';

    final Color itemColor = isActive
        ? _accent
        : (isHovered ? OhtliColors.xoconostle : OhtliColors.onyx.withOpacity(0.7));

    Widget iconWidget = _buildItemIcon(isActive ? item.activeIcon : item.icon, itemColor);
    if (item.index == 6) iconWidget = _withNotificationBadge(iconWidget);

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0, vertical: 10),
      decoration: BoxDecoration(
        color: isActive
            ? OhtliColors.cloudDancer.withOpacity(0.8)
            : (isHovered ? Colors.white.withOpacity(0.3) : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          iconWidget,
          if (expanded) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: itemColor,
                ),
              ),
            ),
            // Pista del atajo: discreta, se resalta al pasar el puntero.
            AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              opacity: isHovered ? 1 : 0,
              child: _KeyCap(shortcut, small: true),
            ),
          ],
        ],
      ),
    );

    content = _tooltip(message: expanded ? 'Atajo: $shortcut' : '${item.label}  ·  $shortcut', child: content);

    return Semantics(
      button: true,
      selected: isActive,
      label: item.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredKey = hoverKey),
        onExit: (_) => setState(() {
          if (_hoveredKey == hoverKey) _hoveredKey = null;
        }),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap ?? () => _select(item.index),
          child: content,
        ),
      ),
    );
  }

  Widget _buildPlanTripCtaButton({required bool expanded}) {
    final String shortcut = '${_altKey}N';
    Widget ctaContent;

    if (!expanded) {
      ctaContent = Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: OhtliColors.stormyTeal,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: OhtliColors.stormyTeal.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        // El isologo ya aparece arriba como marca; aquí un "+" evita repetirlo al comprimir
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
      );
    } else {
      ctaContent = Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: OhtliColors.stormyTeal,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: OhtliColors.stormyTeal.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/icon_isologo.svg',
              width: 18,
              height: 18,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Planea un viaje',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      button: true,
      label: 'Planea un viaje',
      child: _tooltip(
        message: expanded ? 'Atajo: $shortcut' : 'Planea un viaje  ·  $shortcut',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(onTap: _openPlanner, child: ctaContent),
        ),
      ),
    );
  }

  Widget _headerButton({required IconData icon, required String tooltip, required VoidCallback onTap}) {
    return _tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 18, color: _accent),
          ),
        ),
      ),
    );
  }

  /// Contenido del menú. Se usa tanto en el riel (contraído o fijo) como en el
  /// panel desplegado por hover; [expanded] depende del ancho disponible para que
  /// las animaciones nunca desborden.
  Widget _buildPanelContent({required bool expanded, required bool isPeek}) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? user?.email ?? 'Viajero';
    final initials = displayName.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final colorBorder = OhtliSettings.instance.isDarkMode ? const Color(0xFF2C2C32) : const Color(0xFFD1CDC4);
    final String pinShortcut = '${_modKey}B';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cabecera: logo + botón fijar/contraer
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              if (!expanded)
                Expanded(
                  child: Center(
                    child: _tooltip(
                      message: 'Mi cuenta',
                      child: GestureDetector(
                        onTap: _goToAccount,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: SvgPicture.asset(
                            'assets/icon_isologo.svg',
                            height: 26,
                            fit: BoxFit.contain,
                            colorFilter: ColorFilter.mode(_accent, BlendMode.srcIn),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else ...[
                Expanded(
                  child: GestureDetector(
                    onTap: _goToAccount,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: SvgPicture.asset(
                        'assets/logo.svg',
                        height: 22,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        colorFilter: ColorFilter.mode(_accent, BlendMode.srcIn),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (isPeek && !_isNarrow)
                  _headerButton(
                    icon: Icons.push_pin_outlined,
                    tooltip: 'Fijar menú abierto  ·  $pinShortcut',
                    onTap: _togglePin,
                  )
                else if (isPeek)
                  _headerButton(
                    icon: Icons.keyboard_double_arrow_left_rounded,
                    tooltip: 'Contraer menú  ·  Esc',
                    onTap: () {
                      _suppressDwellUntilExit = true;
                      _closePeek();
                    },
                  )
                else
                  _headerButton(
                    icon: Icons.keyboard_double_arrow_left_rounded,
                    tooltip: 'Contraer menú  ·  $pinShortcut',
                    onTap: _togglePin,
                  ),
              ],
            ],
          ),
        ),

        // Botón para expandir cuando está contraído (centrado bajo el isologo)
        if (!expanded)
          Center(
            child: _headerButton(
              icon: Icons.keyboard_double_arrow_right_rounded,
              tooltip: _isNarrow ? 'Mostrar menú  ·  $pinShortcut' : 'Fijar menú abierto  ·  $pinShortcut',
              onTap: _togglePin,
            ),
          ),

        const SizedBox(height: 16),
        _buildPlanTripCtaButton(expanded: expanded),
        const SizedBox(height: 8),

        for (final item in _items) _buildSidebarItem(item, expanded: expanded),

        const Spacer(),

        _buildSidebarItem(
          _accessibilityItem,
          expanded: expanded,
          onTap: _openAccessibility,
          highlighted: _accessibilityOpen,
        ),
        const SizedBox(height: 6),

        // Pie: avatar + nombre + atajos + cerrar sesión
        Divider(height: 1, color: colorBorder),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0, vertical: 12),
          child: Row(
            mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              _tooltip(
                message: 'Mi cuenta',
                child: _buildAvatarWidget(
                  radius: 16,
                  initials: initials,
                  photoURL: _localPhotoURL,
                  onTap: _goToAccount,
                ),
              ),
              if (expanded) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _goToAccount,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text(
                        displayName.split(' ').first,
                        maxLines: 1,
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
                _footerIcon(
                  key: 'shortcuts',
                  icon: Icons.keyboard_outlined,
                  tooltip: 'Atajos de teclado  ·  ?',
                  onTap: _showShortcuts,
                ),
                _footerIcon(
                  key: 'logout',
                  icon: Icons.logout_rounded,
                  tooltip: 'Cerrar sesión',
                  onTap: () {
                    _closePeek(immediate: true);
                    widget.onLogout();
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _footerIcon({
    required String key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final bool hovered = _hoveredKey == key;
    return _tooltip(
      message: tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredKey = key),
        onExit: (_) => setState(() {
          if (_hoveredKey == key) _hoveredKey = null;
        }),
        child: Semantics(
          button: true,
          label: tooltip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(icon, size: 17, color: hovered ? OhtliColors.xoconostle : OhtliColors.onyx.withOpacity(0.5)),
            ),
          ),
        ),
      ),
    );
  }

  Color get _sidebarColor => OhtliSettings.instance.isDarkMode ? const Color(0xFF1E1E22) : const Color(0xFFE4E1DA);
  Color get _borderColor => OhtliSettings.instance.isDarkMode ? const Color(0xFF2C2C32) : const Color(0xFFD1CDC4);

  /// Panel que se despliega sobre el contenido tras el hover prolongado.
  Widget _buildPeekOverlay(BuildContext context, OverlayChildLayoutInfo info) {
    // Se coloca exactamente encima del riel, usando su posición en el Overlay.
    final Offset origin = MatrixUtils.transformPoint(info.childPaintTransform, Offset.zero);
    final double railHeight = info.childSize.height;
    return Positioned(
      left: origin.dx,
      top: origin.dy,
      child: MouseRegion(
        onEnter: (_) => _collapseTimer?.cancel(),
        onExit: (_) => _scheduleCollapse(),
        child: AnimatedBuilder(
          animation: _peekCtrl,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_peekCtrl.value);
            final width = lerpDouble(_railWidth, _panelWidth, t)!;
            return Material(
              color: _sidebarColor,
              elevation: 0,
              child: Container(
                width: width,
                height: railHeight,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: _borderColor, width: 1)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.16 * t), blurRadius: 24, offset: const Offset(6, 0)),
                  ],
                ),
                child: ClipRect(child: _buildPanelContent(expanded: width >= 150, isPeek: true)),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncProfilePic();
    _isNarrow = MediaQuery.sizeOf(context).width < _narrowBreakpoint;
    final bool pinned = _effectivePinned;
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) == true;

    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _peekPortal,
      overlayChildBuilder: _buildPeekOverlay,
      child: MouseRegion(
        onEnter: _onRailEnter,
        onExit: _onRailExit,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          width: pinned ? _panelWidth : _railWidth,
          decoration: BoxDecoration(
            color: _sidebarColor,
            border: Border(right: BorderSide(color: _borderColor, width: 1)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: ClipRect(child: _buildPanelContent(expanded: constraints.maxWidth >= 150, isPeek: false)),
                  ),
                  // Indicador sutil del hover: se llena durante los 2 s antes de desplegar.
                  if (!pinned)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 2,
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _dwellCtrl,
                          builder: (context, _) {
                            final v = _dwellCtrl.value;
                            final opacity = ((v - 0.2) / 0.8).clamp(0.0, 1.0);
                            return Align(
                              alignment: Alignment.topCenter,
                              child: FractionallySizedBox(
                                heightFactor: v,
                                child: Container(color: OhtliColors.stormyTeal.withOpacity(0.55 * opacity)),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Tecla dibujada (para atajos en tooltips, filas y la ayuda).
class _KeyCap extends StatelessWidget {
  final String label;
  final bool small;
  const _KeyCap(this.label, {this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 8, vertical: small ? 1 : 3),
      decoration: BoxDecoration(
        color: OhtliColors.onyx.withOpacity(0.06),
        borderRadius: BorderRadius.circular(small ? 5 : 6),
        border: Border.all(color: OhtliColors.onyx.withOpacity(0.15)),
      ),
      child: Text(
        label,
        style: GoogleFonts.robotoMono(
          fontSize: small ? 10 : 12,
          fontWeight: FontWeight.w500,
          color: OhtliColors.onyx.withOpacity(0.65),
        ),
      ),
    );
  }
}

/// Contenido del panel rápido de accesibilidad.
class _AccessibilityPanel extends StatelessWidget {
  final VoidCallback onMoreOptions;
  const _AccessibilityPanel({required this.onMoreOptions});

  static const _sizes = [
    (OhtliFontSize.small, 'Pequeño', 13.0),
    (OhtliFontSize.medium, 'Normal', 16.0),
    (OhtliFontSize.large, 'Grande', 19.0),
    (OhtliFontSize.extraLarge, 'Muy grande', 22.0),
  ];

  static const _themes = [
    (OhtliThemeMode.system, 'Sistema', Icons.brightness_auto_rounded),
    (OhtliThemeMode.light, 'Claro', Icons.light_mode_rounded),
    (OhtliThemeMode.dark, 'Oscuro', Icons.dark_mode_rounded),
  ];

  static Color _fg(bool selected) => selected ? _accent : OhtliColors.onyx.withOpacity(0.7);

  @override
  Widget build(BuildContext context) {
    final settings = OhtliSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final labelStyle = GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: OhtliColors.onyx.withOpacity(0.7),
        );
        final sizeIndex = _sizes.indexWhere((e) => e.$1 == settings.fontSize);
        return Material(
          color: OhtliColors.cardBg,
          elevation: 12,
          shadowColor: Colors.black.withOpacity(0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: OhtliColors.cardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.accessibility_new_rounded, color: _accent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Accesibilidad',
                        style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: OhtliColors.onyx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Tema', style: labelStyle),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final t in _themes) ...[
                        Expanded(
                          child: _OptionChip(
                            selected: settings.themeMode == t.$1,
                            semanticsLabel: 'Tema ${t.$2}',
                            onTap: () => settings.themeMode = t.$1,
                            child: Column(
                              children: [
                                Icon(t.$3, size: 18, color: _fg(settings.themeMode == t.$1)),
                                const SizedBox(height: 4),
                                Text(
                                  t.$2,
                                  style: GoogleFonts.inter(fontSize: 11, color: _fg(settings.themeMode == t.$1)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (t != _themes.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Tamaño de letra', style: labelStyle),
                      const Spacer(),
                      Text(
                        sizeIndex >= 0 ? _sizes[sizeIndex].$2 : '',
                        style: GoogleFonts.inter(fontSize: 12, color: _accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final sz in _sizes) ...[
                        Expanded(
                          child: _OptionChip(
                            selected: settings.fontSize == sz.$1,
                            semanticsLabel: 'Letra ${sz.$2}',
                            onTap: () => settings.fontSize = sz.$1,
                            child: SizedBox(
                              height: 30,
                              child: Center(
                                child: Text(
                                  'A',
                                  // Sin escalar: la muestra se ve igual sin importar el ajuste actual.
                                  textScaler: TextScaler.noScaling,
                                  style: GoogleFonts.inter(
                                    fontSize: sz.$3,
                                    fontWeight: FontWeight.w600,
                                    color: _fg(settings.fontSize == sz.$1),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (sz != _sizes.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onMoreOptions,
                      child: Text(
                        'Más preferencias en Mi cuenta',
                        style: GoogleFonts.inter(fontSize: 12, color: _accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OptionChip extends StatelessWidget {
  final bool selected;
  final String semanticsLabel;
  final VoidCallback onTap;
  final Widget child;
  const _OptionChip({required this.selected, required this.semanticsLabel, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? OhtliColors.stormyTeal.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _accent : OhtliColors.onyx.withOpacity(0.15),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
