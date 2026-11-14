import 'dart:async';

import 'package:flutter/material.dart';

/// Hace aparecer [child] (se desvanece y se desliza) la primera vez que entra en pantalla.
/// [scroll] es el desplazamiento que se observa (el de la página, no el de listas internas).
class RevealOnScroll extends StatefulWidget {
  final Widget child;
  final Listenable? scroll;
  final Duration delay;

  /// Desde dónde llega, en píxeles (por defecto, un poco desde abajo).
  final Offset from;

  const RevealOnScroll({
    super.key,
    required this.child,
    this.scroll,
    this.delay = Duration.zero,
    this.from = const Offset(0, 28),
  });

  @override
  State<RevealOnScroll> createState() => _RevealOnScrollState();
}

class _RevealOnScrollState extends State<RevealOnScroll> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  bool _started = false;
  Timer? _delayTimer;
  final List<Timer> _retries = [];

  @override
  void initState() {
    super.initState();
    widget.scroll?.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    // La página puede terminar de acomodarse (portada, imágenes) después del primer cuadro:
    // se vuelve a revisar un par de veces aunque no haya desplazamiento.
    for (final ms in const [250, 700, 1500]) {
      _retries.add(Timer(Duration(milliseconds: ms), _check));
    }
  }

  @override
  void didUpdateWidget(covariant RevealOnScroll old) {
    super.didUpdateWidget(old);
    if (old.scroll != widget.scroll) {
      old.scroll?.removeListener(_check);
      if (!_started) widget.scroll?.addListener(_check);
    }
  }

  void _check() {
    if (_started || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final double top = box.localToGlobal(Offset.zero).dy;
    final double screenH = MediaQuery.sizeOf(context).height;
    // Basta con que asome un poco por abajo (o que ya esté arriba, p. ej. al saltar con el índice).
    if (top < screenH - 40) {
      _started = true;
      for (final t in _retries) {
        t.cancel();
      }
      widget.scroll?.removeListener(_check);
      if (widget.delay == Duration.zero) {
        _c.forward();
      } else {
        _delayTimer = Timer(widget.delay, () {
          if (mounted) _c.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    for (final t in _retries) {
      t.cancel();
    }
    widget.scroll?.removeListener(_check);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: widget.from * (1 - _t.value), child: child),
      ),
    );
  }
}
