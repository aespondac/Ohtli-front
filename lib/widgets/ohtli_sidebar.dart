// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print

import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'dart:ui' show lerpDouble;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/saved_accounts.dart';
import '../theme/colors.dart';
import '../screens/notifications_page.dart';
import 'ohtli_accessibility_panel.dart';
import 'trip_planner_dialog.dart';

Color get _accent => ohtliAccent;

/// Menú lateral de escritorio.
///
/// Dinámica:
/// - Por defecto está contraído (solo iconos) y no estorba al contenido.
/// - Si dejas el puntero encima ~1.5 s se despliega *sobre* el contenido (sin
///   empujarlo) y se vuelve a contraer en cuanto el puntero sale o eliges una opción.
/// - Doble clic en una zona vacía del menú lo fija abierto o lo contrae (también ⌘B / Ctrl+B).
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
  static const Duration _dwell = Duration(milliseconds: 1500);
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
  bool _notificationsOpen = false;
  String? _focusedKey;
  // Para medir la altura de cada opción y deslizar el indicador de sección activa.
  final Map<bool, GlobalKey> _navListKeys = {false: GlobalKey(), true: GlobalKey()};
  final Map<bool, double> _slotHeight = {};
  final FocusNode _ctaFocus = FocusNode(debugLabel: 'sidebar-cta');
  // La preferencia "fijado" también se guarda en la cuenta (users/{uid}/private/ui).
  static String? _remotePinLoadedFor;
  bool _railHovered = false;
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
        _isPinned = web.window.localStorage.getItem(_pinnedKey) == 'true';
      } catch (e) {
        print("Error reading sidebar pinned state: $e");
      }
      _hasLoadedState = true;
    }
    _loadRemotePinned();
  }

  DocumentReference<Map<String, dynamic>> _uiPrefsRef(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('private').doc('ui');

  /// Trae de la cuenta si el menú está fijado (una vez por sesión y usuario), para
  /// que la preferencia se mantenga entre dispositivos y navegadores.
  Future<void> _loadRemotePinned() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _remotePinLoadedFor == user.uid) return;
    _remotePinLoadedFor = user.uid;
    try {
      final snap = await _uiPrefsRef(user.uid).get();
      final value = snap.data()?['sidebar_pinned'];
      if (value is bool && value != _isPinned && mounted) {
        setState(() => _isPinned = value);
        _savePinnedLocal();
      }
    } catch (e) {
      print("Error reading sidebar pinned state from account: $e");
    }
  }

  void _savePinnedLocal() {
    if (!kIsWeb) return;
    try {
      web.window.localStorage.setItem(_pinnedKey, _isPinned.toString());
    } catch (e) {
      print("Error saving sidebar pinned state: $e");
    }
  }

  void _savePinnedRemote() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _uiPrefsRef(user.uid)
        .set({'sidebar_pinned': _isPinned, 'updated_at': FieldValue.serverTimestamp()}, SetOptions(merge: true))
        .catchError((e) => print("Error saving sidebar pinned state to account: $e"));
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _collapseTimer?.cancel();
    _dwellTimer?.cancel();
    _peekCtrl.dispose();
    _dwellCtrl.dispose();
    _ctaFocus.dispose();
    super.dispose();
  }

  void _syncProfilePic() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && kIsWeb) {
      try {
        final localPic = web.window.localStorage.getItem('ohtli_profile_pic_${user.uid}');
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
    _savePinnedLocal();
    _savePinnedRemote();
  }

  void _onRailEnter(PointerEnterEvent _) {
    _collapseTimer?.cancel();
    if (!_railHovered) setState(() => _railHovered = true);
    if (_effectivePinned || _peekOpen || _suppressDwellUntilExit) return;
    _dwellCtrl.forward(from: 0);
    _dwellTimer?.cancel();
    _dwellTimer = Timer(_dwell, _openPeek);
  }

  void _onRailExit(PointerExitEvent _) {
    if (_railHovered) setState(() => _railHovered = false);
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
    // "Quiero hacerlo por mi cuenta" abre el editor con un borrador en blanco
    TripPlannerDialog.show(context);
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
          _activate(item);
          return true;
        }
      }
      if (key == PhysicalKeyboardKey.keyM) {
        _focusMenu();
        return true;
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

  /// Opción del menú: Notificaciones abre su panel lateral, el resto navega.
  void _activate(_NavItem item) {
    if (item.index == 6) {
      _openNotifications();
    } else if (item.index == -1) {
      _openAccessibility();
    } else {
      _select(item.index);
    }
  }

  /// Lleva el foco del teclado al menú (al botón "Planea un viaje").
  void _focusMenu() {
    _closePeek(immediate: true);
    _ctaFocus.requestFocus();
  }

  double _panelLeft() {
    final box = context.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box.localToGlobal(Offset.zero).dx + box.size.width : _railWidth;
  }

  /// Notificaciones en un panel junto al menú, sin salir de la pantalla actual.
  Future<void> _openNotifications() async {
    if (_notificationsOpen) return;
    _suppressDwellUntilExit = true;
    _cancelDwell();
    _closePeek(immediate: true);
    final double left = _panelLeft();
    setState(() => _notificationsOpen = true);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar notificaciones',
      barrierColor: Colors.black.withOpacity(0.12),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, _) {
        final mq = MediaQuery.of(ctx);
        final double width = (mq.size.width - left - 34).clamp(320.0, 440.0);
        return Stack(
          children: [
            // Tarjeta flotante redondeada (como los paneles del visor de viajes).
            Positioned(
              left: left + 10,
              top: 12,
              bottom: 12,
              width: width,
              child: Material(
                color: OhtliColors.cloudDancer,
                elevation: 16,
                shadowColor: Colors.black.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: BorderSide(color: OhtliColors.cardBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // La página se acomoda como en una pantalla angosta.
                    MediaQuery(
                      data: mq.copyWith(size: Size(width, mq.size.height)),
                      child: const NotificationsPage(),
                    ),
                    Positioned(
                      top: 20,
                      right: 8,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Abrir en pantalla completa',
                            icon: Icon(Icons.open_in_full_rounded, size: 18, color: OhtliColors.onyx.withOpacity(0.6)),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _select(6);
                            },
                          ),
                          IconButton(
                            tooltip: 'Cerrar  ·  Esc',
                            icon: Icon(Icons.close_rounded, size: 20, color: OhtliColors.onyx.withOpacity(0.7)),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(-0.04, 0), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (mounted) setState(() => _notificationsOpen = false);
  }

  /// Menú de la cuenta (avatar): cuentas recordadas para cambiar, Agregar otra cuenta,
  /// Mi cuenta, Accesibilidad, Atajos y Cerrar sesión.
  Future<void> _openAccountMenu(BuildContext anchorContext) async {
    final anchor = anchorContext.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchor == null || overlay == null) return;

    final user = FirebaseAuth.instance.currentUser;
    final saved = SavedAccounts.list();
    final bool currentSaved = user != null && SavedAccounts.isSaved(user.uid);
    // Todas las demás cuentas recordadas; las que perdieron su sesión se muestran como
    // "Inicia sesión de nuevo" en vez de desaparecer.
    final others = saved.where((a) => a.uid != user?.uid).toList();

    // Se abre justo encima del botón: alto estimado de las opciones y separadores.
    final double scale = MediaQuery.textScalerOf(context).scale(1);
    final int accountRows = 1 + others.length;
    final double menuHeight = (accountRows * 54 + (currentSaved ? 5 : 6) * 42) * scale + 2 * 8 + 16;
    final Offset topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    final double top = (topLeft.dy - menuHeight - 6).clamp(
      8.0,
      (overlay.size.height - menuHeight).clamp(8.0, double.infinity),
    );
    final RelativeRect position = RelativeRect.fromLTRB(
      topLeft.dx,
      top,
      overlay.size.width - topLeft.dx - anchor.size.width,
      (overlay.size.height - top - menuHeight).clamp(0.0, double.infinity),
    );
    _suppressDwellUntilExit = true;
    _cancelDwell();
    _closePeek(immediate: true);

    PopupMenuItem<String> entry(
      String value,
      IconData icon,
      String label, {
      String? keyHint,
      Color? color,
      String? subtitle,
    }) {
      final c = color ?? OhtliColors.onyx.withOpacity(0.85);
      return PopupMenuItem<String>(
        value: value,
        height: 42,
        child: Row(
          children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.inter(fontSize: 13, color: c)),
                  if (subtitle != null)
                    Text(subtitle, style: GoogleFonts.inter(fontSize: 10.5, color: OhtliColors.onyx.withOpacity(0.5))),
                ],
              ),
            ),
            if (keyHint != null) ...[const SizedBox(width: 12), _KeyCap(keyHint, small: true)],
          ],
        ),
      );
    }

    Widget accountRow({
      required String initials,
      required String? photo,
      required String name,
      required String email,
      required bool current,
      bool needsLogin = false,
    }) {
      return Row(
        children: [
          _buildAvatarWidget(radius: 15, initials: initials, photoURL: photo),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx),
                ),
                if (needsLogin)
                  Text(
                    'Inicia sesión de nuevo',
                    maxLines: 1,
                    style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.xoconostle),
                  )
                else if (name.isNotEmpty && email.isNotEmpty)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.onyx.withOpacity(0.55)),
                  ),
              ],
            ),
          ),
          if (current) Icon(Icons.check_rounded, size: 18, color: _accent),
          if (needsLogin) Icon(Icons.login_rounded, size: 17, color: OhtliColors.onyx.withOpacity(0.5)),
        ],
      );
    }

    final String currentName = user?.displayName ?? '';
    final String currentEmail = user?.email ?? '';
    final String currentInitials = (currentName.isNotEmpty ? currentName : currentEmail)
        .split(RegExp(r'[\s@.]+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    final choice = await showMenu<String>(
      context: context,
      position: position,
      color: OhtliColors.cardBg,
      elevation: 10,
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: OhtliColors.cardBorder),
      ),
      items: [
        // Cuenta actual (no se elige: solo indica con cuál estás)
        PopupMenuItem<String>(
          enabled: false,
          height: 54,
          child: accountRow(
            initials: currentInitials,
            photo: _localPhotoURL ?? user?.photoURL,
            name: currentName,
            email: currentEmail,
            current: true,
          ),
        ),
        // Otras cuentas recordadas en este navegador: un clic para cambiar
        for (final a in others)
          PopupMenuItem<String>(
            value: 'switch:${a.uid}',
            height: 54,
            child: Tooltip(
              message: SavedAccounts.needsLogin(a.uid)
                  ? 'Su sesión ya no es válida: inicia sesión con ${a.email.isNotEmpty ? a.email : 'esa cuenta'}'
                  : 'Cambiar a esta cuenta',
              waitDuration: const Duration(milliseconds: 600),
              child: accountRow(
                initials: a.initials,
                photo: a.photoURL,
                name: a.name,
                email: a.email,
                current: false,
                needsLogin: SavedAccounts.needsLogin(a.uid),
              ),
            ),
          ),
        if (!currentSaved && user != null)
          entry(
            'remember',
            Icons.bookmark_add_outlined,
            'Recordar esta cuenta',
            subtitle: 'Para volver a ella con un clic',
          ),
        entry(
          'add',
          Icons.person_add_alt_1_outlined,
          'Agregar otra cuenta',
          subtitle: 'Marca "Recordarme" al iniciar sesión para poder cambiar',
        ),
        const PopupMenuDivider(height: 8),
        entry('account', Icons.person_outline, 'Mi cuenta'),
        entry('a11y', Icons.accessibility_new_rounded, 'Accesibilidad', keyHint: '${_altKey}A'),
        entry('shortcuts', Icons.keyboard_outlined, 'Atajos de teclado', keyHint: '?'),
        const PopupMenuDivider(height: 8),
        entry(
          'logout',
          Icons.logout_rounded,
          'Cerrar sesión',
          color: OhtliColors.xoconostle,
          subtitle: currentSaved ? 'Y olvidar esta cuenta en este navegador' : null,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice.startsWith('switch:')) {
      final target = others.firstWhere((a) => 'switch:${a.uid}' == choice);
      if (SavedAccounts.needsLogin(target.uid)) {
        await _addAccount(currentSaved: currentSaved);
      } else {
        await _switchAccount(target);
      }
      return;
    }
    switch (choice) {
      case 'remember':
        await SavedAccounts.remember(user!);
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              backgroundColor: OhtliColors.stormyTeal,
              content: Text(
                SavedAccounts.isSaved(user.uid)
                    ? 'Listo: podrás volver a esta cuenta desde el menú.'
                    : 'No pudimos recordar esta cuenta. Intenta de nuevo.',
                style: GoogleFonts.inter(color: Colors.white),
              ),
            ),
          );
        }
      case 'add':
        await _addAccount(currentSaved: currentSaved);
      case 'account':
        _goToAccount();
      case 'a11y':
        _openAccessibility();
      case 'shortcuts':
        _showShortcuts();
      case 'logout':
        // Si la cuenta se recordó en este dispositivo, se guarda su sesión más reciente para
        // el inicio rápido; se olvida con la × en la pantalla de inicio de sesión.
        if (user != null && SavedAccounts.isSaved(user.uid)) await SavedAccounts.remember(user);
        widget.onLogout();
    }
  }

  Future<void> _switchAccount(SavedAccount account) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final label = account.name.isNotEmpty ? account.name : account.email;
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Cambiando a $label…', style: GoogleFonts.inter()),
        duration: const Duration(seconds: 6),
      ),
    );
    final result = await SavedAccounts.switchTo(account.uid);
    if (result == SwitchAccountResult.switched) {
      // Arranca la app desde el inicio con la nueva cuenta (sin datos en memoria de la anterior).
      web.window.location.assign('${web.window.location.origin}/');
      return;
    }
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        backgroundColor: OhtliColors.xoconostle,
        content: Text(
          result == SwitchAccountResult.expired
              ? 'La sesión de $label caducó. Inicia sesión de nuevo con esa cuenta para recordarla.'
              : 'No pudimos cambiar a $label. Intenta de nuevo.',
          style: GoogleFonts.inter(color: Colors.white),
        ),
      ),
    );
  }

  /// Lleva al inicio de sesión sin olvidar las cuentas recordadas.
  Future<void> _addAccount({required bool currentSaved}) async {
    if (!currentSaved) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: OhtliColors.cloudDancer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            'Agregar otra cuenta',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: OhtliColors.onyx),
          ),
          content: Text(
            'Tu cuenta actual no está recordada en este navegador, así que para volver a ella '
            'tendrás que iniciar sesión otra vez. Para poder cambiar con un clic, inicia sesión '
            'con "Recordarme en este dispositivo" marcado.',
            style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.onyx.withOpacity(0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancelar', style: GoogleFonts.inter(color: OhtliColors.onyx.withOpacity(0.7))),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Continuar',
                style: GoogleFonts.inter(color: _accent, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    widget.onLogout();
  }

  /// Panel rápido de accesibilidad: tema y tamaño de letra, junto al menú.
  Future<void> _openAccessibility() async {
    if (_accessibilityOpen) return;
    _suppressDwellUntilExit = true;
    _cancelDwell();
    _closePeek(immediate: true);
    final double left = _panelLeft() + 10;
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
            child: OhtliAccessibilityPanel(
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
      ('Fijar / contraer el menú (o doble clic en él)', '${_modKey}B'),
      ('Planea un viaje', '${_altKey}N'),
      for (final item in _items) (item.label, '$_altKey${item.keyLabel}'),
      ('Accesibilidad: tema y tamaño de letra', '$_altKey${_accessibilityItem.keyLabel}'),
      ('Ir al menú con el teclado (luego ↑ ↓ y Enter)', '${_altKey}M'),
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
                'Deja el puntero sobre el menú contraído 1.5 s para desplegarlo, y haz doble clic en una zona vacía del menú para fijarlo o contraerlo.',
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
    final bool isFocused = _focusedKey == hoverKey;
    final VoidCallback tap = onTap ?? () => _activate(item);
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
        // Anillo de foco visible al navegar con el teclado (borde fijo para no mover el contenido).
        border: Border.all(color: isFocused ? _accent : Colors.transparent, width: 2),
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

    // Contraído: el tooltip da nombre + atajo. Expandido: la tecla ya se ve en la fila.
    content = _tooltip(message: '${item.label}  ·  $shortcut', show: !expanded, child: content);

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
        child: _focusable(
          focusKey: hoverKey,
          onActivate: tap,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: tap, child: content),
        ),
      ),
    );
  }

  /// Hace enfocable un control del menú: Enter/Espacio lo activan y el foco se dibuja.
  Widget _focusable({
    required String focusKey,
    required VoidCallback onActivate,
    required Widget child,
    FocusNode? focusNode,
  }) {
    return FocusableActionDetector(
      focusNode: focusNode,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onActivate();
            return null;
          },
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) {
            onActivate();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (show) => setState(() {
        if (show) {
          _focusedKey = focusKey;
        } else if (_focusedKey == focusKey) {
          _focusedKey = null;
        }
      }),
      child: child,
    );
  }

  /// Opciones de navegación con el indicador deslizante de la sección activa.
  Widget _buildNavList({required bool expanded, required bool isPeek}) {
    final key = _navListKeys[isPeek]!;
    final int slot = _items.indexWhere((it) => it.index == widget.currentIndex);
    final double? h = _slotHeight[isPeek];
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) == true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = (key.currentContext?.findRenderObject() as RenderBox?)?.size;
      if (size == null) return;
      final double measured = size.height / _items.length;
      final double previous = _slotHeight[isPeek] ?? -1;
      if ((previous - measured).abs() > 0.5) setState(() => _slotHeight[isPeek] = measured);
    });

    return Stack(
      children: [
        Column(
          key: key,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in _items)
              item.index == 6
                  ? _buildSidebarItem(
                      item,
                      expanded: expanded,
                      onTap: _openNotifications,
                      highlighted: _notificationsOpen || widget.currentIndex == 6,
                    )
                  : _buildSidebarItem(item, expanded: expanded),
          ],
        ),
        if (slot >= 0 && h != null)
          AnimatedPositioned(
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            left: 2,
            top: slot * h + h * 0.27,
            height: h * 0.46,
            width: 3,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlanTripCtaButton({required bool expanded, required bool isPeek}) {
    final String shortcut = '${_altKey}N';
    final bool isFocused = _focusedKey == 'cta';
    final Border focusRing = Border.all(color: isFocused ? _accent : Colors.transparent, width: 2);
    Widget ctaContent;

    if (!expanded) {
      ctaContent = Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: OhtliColors.stormyTeal,
          borderRadius: BorderRadius.circular(14),
          border: focusRing,
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
          border: focusRing,
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
          child: _focusable(
            focusKey: 'cta',
            onActivate: _openPlanner,
            // Solo el riel lleva el nodo de foco (el panel desplegado es una copia temporal).
            focusNode: isPeek ? null : _ctaFocus,
            child: GestureDetector(onTap: _openPlanner, child: ctaContent),
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

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cabecera: logo + pista de doble clic
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
                const SizedBox(width: 6),
                // Pista de doble clic: siempre en el despliegue temporal; fijo, solo al pasar el puntero.
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: (isPeek || _railHovered) ? 1 : 0,
                  child: _tooltip(
                    message: 'También con $pinShortcut',
                    child: Text(
                      isPeek
                          ? (_isNarrow ? 'Doble clic\npara cerrar' : 'Doble clic\npara fijar')
                          : 'Doble clic\npara contraer',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        color: OhtliColors.onyx.withOpacity(0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),
        _buildPlanTripCtaButton(expanded: expanded, isPeek: isPeek),
        const SizedBox(height: 8),

        _buildNavList(expanded: expanded, isPeek: isPeek),

        const Spacer(),

        _buildSidebarItem(
          _accessibilityItem,
          expanded: expanded,
          onTap: _openAccessibility,
          highlighted: _accessibilityOpen,
        ),
        const SizedBox(height: 6),

        // Pie: botón de cuenta (avatar + nombre) que abre el menú de la cuenta
        Divider(height: 1, color: colorBorder),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: expanded ? 8 : 0, vertical: 8),
          child: Builder(
            builder: (anchorContext) {
              final bool hovered = _hoveredKey == 'account';
              final bool focused = _focusedKey == 'account';
              final Widget avatar = _buildAvatarWidget(radius: 16, initials: initials, photoURL: _localPhotoURL);
              final Widget body = AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: EdgeInsets.symmetric(horizontal: expanded ? 6 : 0, vertical: 4),
                margin: EdgeInsets.symmetric(horizontal: expanded ? 0 : 10),
                decoration: BoxDecoration(
                  color: hovered ? Colors.white.withOpacity(0.3) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: focused ? _accent : Colors.transparent, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: [
                    avatar,
                    if (expanded) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          displayName.split(' ').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: OhtliColors.onyx.withOpacity(0.85),
                          ),
                        ),
                      ),
                      Icon(Icons.unfold_more_rounded, size: 18, color: OhtliColors.onyx.withOpacity(0.5)),
                    ],
                  ],
                ),
              );
              void open() => _openAccountMenu(anchorContext);
              return Semantics(
                button: true,
                label: 'Tu cuenta: cambiar de cuenta, Mi cuenta, Accesibilidad, Atajos y Cerrar sesión',
                child: _tooltip(
                  message: 'Tu cuenta',
                  show: !expanded,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _hoveredKey = 'account'),
                    onExit: (_) => setState(() {
                      if (_hoveredKey == 'account') _hoveredKey = null;
                    }),
                    child: _focusable(
                      focusKey: 'account',
                      onActivate: open,
                      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: open, child: body),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
    return _withDoubleClick(content);
  }

  /// Capa de fondo: el doble clic en cualquier zona vacía del menú lo fija o lo
  /// contrae. Los botones quedan encima y reciben sus clics sin retraso.
  Widget _withDoubleClick(Widget content) {
    // ↑ ↓ recorren las opciones, Enter/Espacio las activan y Esc suelta el foco.
    content = Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              FocusManager.instance.primaryFocus?.unfocus();
              return null;
            },
          ),
        },
        child: FocusTraversalGroup(child: content),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Semantics(
            label: 'Menú lateral: doble clic para fijar o contraer',
            child: GestureDetector(behavior: HitTestBehavior.opaque, onDoubleTap: _onMenuDoubleTap),
          ),
        ),
        Positioned.fill(child: content),
      ],
    );
  }

  void _onMenuDoubleTap() {
    // Al contraer con el puntero encima, no volver a desplegar hasta que salga.
    if (_effectivePinned || _peekOpen) _suppressDwellUntilExit = true;
    _togglePin();
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
                  // Indicador sutil del hover: se llena durante los 1.5 s antes de desplegar.
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
