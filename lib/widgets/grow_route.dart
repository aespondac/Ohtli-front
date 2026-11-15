import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Abre una página "creciendo" desde una tarjeta: la tarjeta se agranda hasta cubrir la
/// pantalla y la página aparece dentro de ella con la misma forma (al volver, se encoge).
///
/// [from] es el rectángulo de la tarjeta respecto al Navigator (ver [GrowPageRoute.rectOf]).
/// [closed] es una copia visual de la tarjeta que se desvanece mientras crece.
class GrowPageRoute<T> extends PageRoute<T> {
  GrowPageRoute({
    required this.from,
    required this.builder,
    this.closed,
    this.radius = 28,
    this.background = Colors.black,
    super.settings,
  });

  final Rect from;
  final WidgetBuilder builder;
  final Widget? closed;
  final double radius;
  final Color background;

  /// Rectángulo de [context] (la tarjeta) en las coordenadas del Navigator que la abrirá.
  static Rect? rectOf(BuildContext context) {
    final box = context.findRenderObject();
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (box is! RenderBox || overlay is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  }

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 560);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 440);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return LayoutBuilder(
      builder: (context, box) {
        final Size size = box.biggest;
        return AnimatedBuilder(
          animation: animation,
          // La página va siempre en el mismo lugar del árbol: así no pierde su estado al terminar.
          child: child,
          builder: (context, page) {
            final double v = animation.value;
            final double t = Curves.easeInOutCubic.transform(v);
            final Rect rect = Rect.lerp(from, Offset.zero & size, t)!;
            final double r = lerpDouble(radius, 0, t)!;
            final double pageOpacity = const Interval(0.12, 0.55, curve: Curves.easeOut).transform(v);
            final double cardOpacity = 1 - const Interval(0.0, 0.5).transform(v);
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(r),
                    child: ColoredBox(
                      color: background,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // La tarjeta crece con la ventana (su foto se agranda) y se desvanece.
                          KeyedSubtree(
                            key: const ValueKey('grow_closed'),
                            child: Opacity(
                              opacity: closed == null ? 0 : cardOpacity,
                              child: closed == null
                                  ? const SizedBox.shrink()
                                  : FittedBox(
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      child: SizedBox.fromSize(
                                        size: from.size,
                                        // Material: estilos de texto normales fuera de la pantalla original.
                                        child: IgnorePointer(child: Material(type: MaterialType.transparency, child: closed)),
                                      ),
                                    ),
                            ),
                          ),
                          // La página se dibuja a su tamaño real y se escala al ancho de la ventana.
                          KeyedSubtree(
                            key: const ValueKey('grow_page'),
                            child: Opacity(
                              opacity: pageOpacity,
                              child: FittedBox(
                                fit: BoxFit.fitWidth,
                                alignment: Alignment.topCenter,
                                child: SizedBox.fromSize(size: size, child: page),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
