import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/friendly_errors.dart' show kOhtliDesktopBreakpoint;

/// Avisos de la app como toasts arriba, que se van solos.
///
/// Las pantallas siguen usando `ScaffoldMessenger.of(context).showSnackBar(...)`: este
/// messenger, puesto sobre toda la app, recibe esos avisos y los muestra arriba (a la derecha
/// en escritorio) en vez de como barra abajo, que tapaba botones y contenido. La barra de abajo
/// queda solo para el estado de la conexión.
class OhtliToastMessenger extends ScaffoldMessenger {
  const OhtliToastMessenger({super.key, required super.child});

  @override
  ScaffoldMessengerState createState() => _OhtliToastMessengerState();
}

class _ToastData {
  _ToastData(this.id, this.snackBar);
  final int id;
  final SnackBar snackBar;
}

class _OhtliToastMessengerState extends ScaffoldMessengerState {
  static const int _maxVisible = 3;
  final List<_ToastData> _toasts = [];
  final Map<int, GlobalKey<_ToastCardState>> _keys = {};
  int _nextId = 0;

  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    final id = _nextId++;
    setState(() {
      _toasts.add(_ToastData(id, snackBar));
      _keys[id] = GlobalKey<_ToastCardState>();
      // Los más viejos se van si ya hay muchos
      while (_toasts.length > _maxVisible) {
        _keys.remove(_toasts.removeAt(0).id);
      }
    });
    // El tipo de regreso solo lo puede crear el messenger original: se le pide uno con un
    // aviso vacío y se quita en seguida, antes de dibujarse. Lo que se ve es el toast.
    final controller = super.showSnackBar(
      const SnackBar(content: SizedBox.shrink(), duration: Duration(milliseconds: 1)),
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
    super.removeCurrentSnackBar();
    return controller;
  }

  void _dismiss(int id) {
    final key = _keys[id];
    if (key?.currentState != null) {
      key!.currentState!.close();
    } else {
      _remove(id);
    }
  }

  void _remove(int id) {
    if (!mounted) return;
    setState(() {
      _toasts.removeWhere((t) => t.id == id);
      _keys.remove(id);
    });
  }

  @override
  void hideCurrentSnackBar({SnackBarClosedReason reason = SnackBarClosedReason.hide}) {
    if (_toasts.isNotEmpty) _dismiss(_toasts.last.id);
    super.hideCurrentSnackBar(reason: reason);
  }

  @override
  void removeCurrentSnackBar({SnackBarClosedReason reason = SnackBarClosedReason.remove}) {
    if (_toasts.isNotEmpty) _remove(_toasts.last.id);
    super.removeCurrentSnackBar(reason: reason);
  }

  @override
  void clearSnackBars() {
    for (final t in [..._toasts]) {
      _dismiss(t.id);
    }
    super.clearSnackBars();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isMobile = media.size.width < kOhtliDesktopBreakpoint;
    final width = isMobile ? media.size.width - 28 : 400.0;
    return Stack(
      children: [
        super.build(context),
        // Solo ocupa lo que miden los toasts: el resto de la pantalla sigue recibiendo toques
        Positioned(
          top: media.padding.top + 14,
          right: 14,
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final t in _toasts)
                _ToastCard(key: _keys[t.id], snackBar: t.snackBar, onClosed: () => _remove(t.id)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({super.key, required this.snackBar, required this.onClosed});

  final SnackBar snackBar;
  final VoidCallback onClosed;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..forward();
  Timer? _timer;
  bool _closing = false;
  bool _hovered = false;

  Duration get _lifetime {
    final d = widget.snackBar.duration;
    // Con acción (p. ej. "Deshacer") se da más tiempo para alcanzar a usarla
    final min = widget.snackBar.action != null ? const Duration(seconds: 7) : const Duration(seconds: 4);
    return d > min ? d : min;
  }

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(_lifetime, close);
  }

  Future<void> close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _anim.reverse();
    widget.onClosed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snackBar;
    final bg = s.backgroundColor ?? const Color(0xFF1E1E22);
    final fg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark ? Colors.white : const Color(0xFF0A090C);
    final action = s.action;
    final curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    return SizeTransition(
      sizeFactor: curve,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.25), end: Offset.zero).animate(curve),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: MouseRegion(
              // Al pasar el mouse por encima no se va, para alcanzar a leerlo
              onEnter: (_) {
                _hovered = true;
                _timer?.cancel();
              },
              onExit: (_) {
                _hovered = false;
                if (!_closing) _startTimer();
              },
              child: Semantics(
                liveRegion: true,
                container: true,
                child: Material(
                  color: bg,
                  elevation: 8,
                  shadowColor: Colors.black.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: DefaultTextStyle.merge(
                            style: GoogleFonts.inter(color: fg, fontSize: 14, height: 1.35, fontWeight: FontWeight.w500),
                            child: IconTheme.merge(data: IconThemeData(color: fg), child: s.content),
                          ),
                        ),
                        if (action != null)
                          TextButton(
                            onPressed: () {
                              action.onPressed();
                              close();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: action.textColor ?? const Color(0xFFF5A55C),
                              textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            child: Text(action.label),
                          ),
                        // Sin tooltip: esta capa está fuera del Navigator y no tiene Overlay
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: close,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            semanticLabel: 'Cerrar aviso',
                            color: fg.withValues(alpha: _hovered ? 1 : 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
